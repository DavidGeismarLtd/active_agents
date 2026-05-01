#!/usr/bin/env ruby
# frozen_string_literal: true

# Entrypoint for containerized agent runtime.
#
# Reads configuration from environment variables, executes the agent loop,
# and reports all events via HTTP callbacks to the host Rails app.
#
# This script runs OUTSIDE of Rails - it has no database access.
# All persistence is done via the callback API.
#
# Environment variables:
#   TASK_RUN_ID    - ID of the TaskRun being executed
#   AGENT_CONFIG   - JSON blob with agent configuration
#   CALLBACK_URL   - URL for reporting events back to Rails
#   CALLBACK_TOKEN - Authentication token for callback API

require "json"
require "net/http"
require "uri"
require "securerandom"
require "open3"
require "logger"

# Load shared agent-runtime modules (pure Ruby, no Rails deps).
lib_path = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)
require "prompt_tracker/agent_runtime/planning"
require "prompt_tracker/agent_runtime/planning_functions"
require "prompt_tracker/agent_runtime/prompt_enhancer"

# Bootstrap ActiveSupport, Rails.logger stub, PromptTracker.configuration
# stub, configured RubyLLM, and the shared LlmClients::RubyLlmService.
require_relative "runtime_bootstrap"

class AgentContainerRunner
  MAX_CALLBACK_RETRIES = 3
  CALLBACK_RETRY_DELAY = 2

  Planning          = PromptTracker::AgentRuntime::Planning
  PlanningFunctions = PromptTracker::AgentRuntime::PlanningFunctions
  PromptEnhancer    = PromptTracker::AgentRuntime::PromptEnhancer
  RubyLlmService    = PromptTracker::LlmClients::RubyLlmService

  def initialize
    @config = JSON.parse(ENV.fetch("AGENT_CONFIG"))
    @task_run_id = ENV.fetch("TASK_RUN_ID")
    @callback_url = ENV.fetch("CALLBACK_URL")
    @callback_token = ENV.fetch("CALLBACK_TOKEN")
    @iteration_count = 0
    @max_iterations = @config.dig("execution", "max_iterations") || 5
    @timeout_seconds = @config.dig("execution", "timeout_seconds") || 1800
    @planning_enabled = @config.dig("planning", "enabled") == true
    @plan = nil
    @start_time = Time.now
    @conversation_history = []
    @final_output = nil
    @mcp_process = nil
    @current_iteration_function_calls = []

    @logger = Logger.new($stdout)
    @logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity} -- #{msg}\n"
    end

    # Route in-process services that log via Rails.logger to our stdout logger.
    Rails.instance_variable_set(:@logger, @logger)
  end

  def run
    @logger.info "Starting containerized agent runtime for TaskRun #{@task_run_id} (planning=#{@planning_enabled})"
    report_event("status_update", { "status" => "running" })

    setup_mcp_servers
    execute_agent_loop

    report_event("status_update", {
      "status" => "completed",
      "output" => @final_output
    })

    @logger.info "Agent completed successfully"
  rescue => e
    @logger.error "Agent failed: #{e.class.name}: #{e.message}"
    @logger.error e.backtrace&.first(20)&.join("\n")

    report_event("status_update", {
      "status" => "failed",
      "error" => "#{e.class.name}: #{e.message}"
    })
    exit(1)
  ensure
    cleanup_mcp_servers
  end

  private

  def execute_agent_loop
    initial_prompt = render_initial_prompt
    @conversation_history << { "role" => "user", "content" => initial_prompt }

    execute_planning_phase if @planning_enabled

    loop do
      @iteration_count += 1

      if @iteration_count > @max_iterations
        @logger.info "Max iterations (#{@max_iterations}) reached"
        report_event("log", { "level" => "info", "message" => "Max iterations reached" })
        force_plan_failure("Maximum iterations (#{@max_iterations}) reached without explicit completion") if @planning_enabled
        break
      end

      if Time.now - @start_time > @timeout_seconds
        @logger.info "Timeout (#{@timeout_seconds}s) reached"
        report_event("log", { "level" => "info", "message" => "Timeout reached" })
        force_plan_failure("Timeout (#{@timeout_seconds}s) reached") if @planning_enabled
        break
      end

      @logger.info "=== Iteration #{@iteration_count}/#{@max_iterations} ==="
      result = execute_iteration(phase: :execution)
      break if result[:completed]
    end

    @final_output ||= extract_final_output
  end

  # Planning phase (iteration 0): agent creates a plan, no other work.
  def execute_planning_phase
    @logger.info "🎯 Starting planning phase"
    report_event("log", { "level" => "info", "message" => "Starting planning phase" })
    execute_iteration(phase: :planning)
  end

  def execute_iteration(phase:)
    @current_iteration_function_calls = []
    @initial_event_emitted_for_iteration = false
    response = call_llm(phase: phase)

    # Append assistant text to history so the next iteration's user_prompt
    # has some context (even though only the last message is forwarded to
    # the LLM — same behaviour as the in-process service).
    @conversation_history << { "role" => "assistant", "content" => response[:text] }

    @current_iteration_function_calls.each do |fc|
      @conversation_history << {
        "role" => "function",
        "name" => fc[:name],
        "content" => fc[:result].to_json
      }
    end

    # With planning, only stop when the plan is explicitly marked completed.
    if @planning_enabled
      if @plan && @plan["status"] == "completed"
        @final_output = @plan["completion_summary"]
        return { completed: true }
      end
      return { completed: false }
    end

    # Without planning: complete when the iteration produced no tool calls.
    if @current_iteration_function_calls.empty?
      @final_output = response[:text]
      return { completed: true }
    end

    { completed: false }
  end

  # Route to the right LLM call implementation based on the agent's
  # configured API type. Both implementations are responsible for emitting
  # their own llm_response events so the timeline mirrors what the LLM
  # actually did (one event per LLM call, not one per outer iteration).
  def call_llm(phase:)
    case api_type_for(@config["model_config"])
    when :openai_responses
      call_via_responses_api(phase: phase)
    else
      call_via_ruby_llm(phase: phase)
    end
  end

  def api_type_for(model_config)
    api = model_config["api"].to_s.downcase
    provider = model_config["provider"].to_s.downcase
    return :openai_responses if provider == "openai" && api == "responses"
    :ruby_llm
  end

  def call_via_ruby_llm(phase:)
    model_config = @config["model_config"]
    model = model_config["model"]
    temperature = model_config["temperature"]
    max_tokens = model_config["max_tokens"]

    system_prompt = build_system_prompt(phase: phase)
    user_prompt = last_user_prompt
    tool_config = build_tool_config(phase: phase)
    tools_param = tool_config["functions"].any? ? [ :functions ] : []

    @logger.info "Calling #{model_config['provider']}/#{model} via RubyLlmService with #{tool_config['functions'].length} tools (phase=#{phase})"

    response = RubyLlmService.new(
      model: model,
      prompt: user_prompt,
      system: system_prompt,
      tools: tools_param,
      tool_config: tool_config,
      function_executor: function_executor,
      temperature: temperature,
      max_tokens: max_tokens
    ).call

    # RubyLLM auto-executes tools internally, so we only see the final
    # message after the loop. Emit one llm_response event for it.
    emit_llm_response_event(response, rendered_prompt: user_prompt, phase: phase)

    {
      model: response.model,
      text: response.text,
      prompt_tokens: response.usage[:prompt_tokens],
      completion_tokens: response.usage[:completion_tokens],
      cost_usd: nil,
      tool_calls: response.tool_calls
    }
  end

  # OpenAI Responses API path. Mirrors TaskAgentRuntimeService::OpenaiResponses
  # but emits events via the callback API instead of writing to ActiveRecord.
  #
  # Key differences from the RubyLlmService path:
  # - During planning phase, sets tool_choice="required" so the LLM cannot
  #   skip create_plan.
  # - Manually loops on tool calls (rather than relying on auto-execution),
  #   so we can emit a separate llm_response event for every API call. This
  #   gives the timeline visibility into what the LLM intended at each step.
  def call_via_responses_api(phase:)
    model_config = @config["model_config"]
    model = model_config["model"]
    temperature = model_config["model"]&.start_with?("gpt-5") ? nil : model_config["temperature"]

    system_prompt = build_system_prompt(phase: phase)
    user_prompt = last_user_prompt
    tools_array = build_tool_config(phase: phase)["functions"]
    tools_param = tools_array.any? ? [ :functions ] : []
    builtin_tools = (model_config["tools"] || []).map(&:to_sym) - [ :functions ]
    tools_param = (tools_param + builtin_tools).uniq

    @logger.info "Calling #{model}/responses with #{tools_array.length} functions (phase=#{phase})"

    call_params = {
      model: model,
      input: user_prompt,
      instructions: system_prompt,
      tools: tools_param,
      tool_config: { "functions" => tools_array },
      temperature: temperature
    }

    if phase == :planning && tools_array.any?
      @logger.info "🎯 Forcing tool_choice=required for planning phase (tools: #{tools_array.map { |t| t['name'] }.join(', ')})"
      call_params[:tool_choice] = "required"
    end

    response = PromptTracker::LlmClients::OpenaiResponseService.call(**call_params)

    @logger.info "Initial Responses API call returned #{response.tool_calls.length} tool_call(s); text=#{response.text.to_s[0..120].inspect}"

    # Track the initial response — captures the LLM's INTENT before tools run.
    if response.tool_calls.any?
      emit_llm_response_event(response, rendered_prompt: user_prompt, phase: phase)
    end

    # Manual function-call loop. Each turn around this loop is one extra LLM
    # call that we want recorded as its own timeline event.
    inner_iteration = 0
    max_inner_iterations = 10

    while response.tool_calls.any? && inner_iteration < max_inner_iterations
      inner_iteration += 1
      tool_calls = response.tool_calls

      input_items = []
      tool_calls.each do |tc|
        result = dispatch_tool_call(tc[:function_name], tc[:arguments] || {}, tool_call_id: tc[:id])
        input_items << {
          type: "function_call",
          call_id: tc[:id],
          name: tc[:function_name],
          arguments: (tc[:arguments] || {}).to_json
        }
        input_items << {
          type: "function_call_output",
          call_id: tc[:id],
          output: result.to_json
        }
      end

      response_id = response.api_metadata[:response_id]
      unless response_id
        @logger.error "No response_id in api_metadata; aborting Responses loop"
        break
      end

      continuation_tools = ([ :functions ] + builtin_tools).uniq

      response = PromptTracker::LlmClients::OpenaiResponseService.call_with_context(
        model: model,
        input: input_items,
        previous_response_id: response_id,
        tools: continuation_tools,
        tool_config: { "functions" => build_tool_config(phase: phase)["functions"] }
      )

      function_summary = tool_calls.map { |tc| tc[:function_name] }.join(", ")
      emit_llm_response_event(
        response,
        rendered_prompt: "Function results for: #{function_summary}",
        phase: phase
      )
    end

    if inner_iteration >= max_inner_iterations && response.tool_calls.any?
      @logger.warn "Max inner Responses iterations (#{max_inner_iterations}) reached"
    end

    {
      model: response.model,
      text: response.text,
      prompt_tokens: response.usage[:prompt_tokens],
      completion_tokens: response.usage[:completion_tokens],
      cost_usd: nil,
      tool_calls: [] # tools already executed in the loop above
    }
  end

  # Emit one llm_response event. Only the FIRST event of an execution-phase
  # iteration carries new_iteration=true (so the controller increments the
  # iteration counter exactly once per outer loop turn).
  def emit_llm_response_event(response, rendered_prompt:, phase:)
    is_initial = phase == :execution && !@initial_event_emitted_for_iteration
    @initial_event_emitted_for_iteration ||= is_initial

    tool_calls = (response.tool_calls || []).map do |tc|
      tc.is_a?(Hash) ? tc.transform_keys(&:to_s) : tc
    end
    tools_used = tool_calls.filter_map { |tc| tc["function_name"] || tc["name"] }.uniq

    # OpenAI Responses normalizer occasionally falls back to raw_response["text"]
    # which is the response_format config blob ({"format":{"type":"text"},...}),
    # not actual prose. Strip that here so the UI doesn't render config as content.
    text = response.text
    text = nil if text.is_a?(Hash) || (text.is_a?(String) && text.start_with?("{") && text.include?('"format"'))

    report_event("llm_response", {
      "model" => response.model,
      "prompt_tokens" => response.usage[:prompt_tokens],
      "completion_tokens" => response.usage[:completion_tokens],
      "cost_usd" => nil,
      "text" => text,
      "rendered_prompt" => rendered_prompt,
      "tool_calls" => tool_calls,
      "tools_used" => tools_used,
      "context" => {
        "iteration" => @iteration_count,
        "new_iteration" => is_initial,
        "phase" => phase.to_s
      }
    })
  end

  def build_system_prompt(phase:)
    base = render_template(@config["system_prompt"])

    base = PromptEnhancer.with_planning(base, phase: phase) if @planning_enabled

    if phase == :execution
      base = PromptEnhancer.with_iteration_context(
        base,
        iteration: @iteration_count,
        max_iterations: @max_iterations
      )
    end

    base = "#{base}\n\n#{workspace_instructions}" if base && !base.empty?
    base
  end

  def workspace_instructions
    <<~INSTRUCTIONS
      You have access to a filesystem workspace:
      - /workspace/input/ — Read-only input files provided for this task
      - /workspace/output/ — Write any files you want to deliver as output here
      - /workspace/tmp/ — Temporary scratch space for intermediate work

      Files in /workspace/output/ will be automatically saved and made available
      to the user after task completion. Use descriptive filenames.
    INSTRUCTIONS
  end

  # Tool config in the shape RubyLlmService / DynamicToolBuilder expects:
  #   { "functions" => [{ "name" => ..., "description" => ..., "parameters" => {...} }] }
  def build_tool_config(phase:)
    functions =
      if phase == :planning
        # Only expose create_plan during planning — and only if a plan does
        # not yet exist.
        @plan.nil? ? PlanningFunctions.planning_phase_functions : []
      else
        user_funcs = (@config["functions"] || []).map do |fn|
          {
            "name" => fn["name"],
            "description" => fn["description"],
            "parameters" => fn["parameters"] || {}
          }
        end
        list = user_funcs.dup
        list += PlanningFunctions.execution_phase_functions if @planning_enabled
        list += mcp_tools_for_llm
        list
      end

    { "functions" => functions }
  end

  # MCP tools currently exposed to the LLM. Cached after the first
  # tools/list call so we don't query the MCP subprocess every iteration.
  def mcp_tools_for_llm
    @mcp_tools_for_llm ||= []
  end

  # Lambda passed to RubyLlmService. Called by RubyLLM for each tool the LLM
  # invokes during a service.call.
  def function_executor
    lambda do |fn_name, arguments|
      dispatch_tool_call(fn_name, arguments)
    end
  end

  # Dispatch a single tool call: run the tool, emit the function_execution
  # event, track it for the iteration's accounting. Used by both the
  # RubyLLM-auto-exec path (via the function_executor lambda) and the
  # manual Responses API loop.
  def dispatch_tool_call(fn_name, arguments, tool_call_id: nil)
    @logger.info "Executing tool: #{fn_name}"
    start_time = Time.now
    arguments = arguments.is_a?(Hash) ? arguments : {}

    begin
      result = execute_tool(fn_name, arguments)
      execution_time_ms = ((Time.now - start_time) * 1000).round

      report_event("function_execution", {
        "function_name" => fn_name,
        "arguments" => arguments,
        "result" => result,
        "success" => true,
        "execution_time_ms" => execution_time_ms
      })

      @current_iteration_function_calls << { name: fn_name, arguments: arguments, result: result }
      result
    rescue => e
      execution_time_ms = ((Time.now - start_time) * 1000).round
      @logger.error "Tool execution failed: #{e.message}"

      report_event("function_execution", {
        "function_name" => fn_name,
        "arguments" => arguments,
        "error_message" => e.message,
        "success" => false,
        "execution_time_ms" => execution_time_ms
      })

      error_result = { "error" => e.message }
      @current_iteration_function_calls << { name: fn_name, arguments: arguments, result: error_result }
      error_result
    end
  end

  def execute_tool(name, arguments)
    if PlanningFunctions.planning_function?(name)
      execute_planning_function(name, arguments)
    elsif @mcp_process && name.start_with?("filesystem__")
      execute_mcp_tool(name, arguments)
    else
      execute_lambda_function(name, arguments)
    end
  end

  def execute_planning_function(name, arguments)
    @logger.info "🎯 Executing planning function: #{name} with #{arguments.inspect}"

    result =
      case name
      when "create_plan"
        response = Planning.create_plan(@plan, arguments)
        if response["success"]
          @plan = response["plan"]
          @logger.info "🎯 Plan CREATED with #{@plan['steps'].size} steps. Goal: #{@plan['goal'].to_s[0..120]}"
        else
          @logger.warn "🎯 create_plan failed: #{response['error']}"
        end
        response
      when "get_plan"
        Planning.get_plan(@plan)
      when "update_step"
        Planning.update_step(@plan, arguments)
      when "add_step"
        Planning.add_step(@plan, arguments)
      when "mark_task_complete"
        Planning.mark_task_complete(@plan, arguments)
      else
        { "success" => false, "error" => "Unknown planning function: #{name}" }
      end

    broadcast_plan if @plan
    result
  end

  def broadcast_plan
    @logger.info "📤 Broadcasting plan_update (status=#{@plan['status']}, steps=#{@plan['steps'].size})"
    report_event("plan_update", { "plan" => @plan })
  end

  def force_plan_failure(reason)
    return unless @plan

    Planning.force_failure(@plan, reason)
    @final_output = @plan["completion_summary"]
    broadcast_plan
  end

  def execute_mcp_tool(name, arguments)
    tool_name = name.sub("filesystem__", "")

    response = mcp_jsonrpc("tools/call", {
      "name" => tool_name,
      "arguments" => arguments
    })

    if response["error"]
      raise "MCP tool error: #{response['error']['message']}"
    end

    response.dig("result", "content", 0, "text") || response["result"]
  end

  def execute_lambda_function(name, arguments)
    fn_config = (@config["functions"] || []).find { |f| f["name"] == name }
    raise "Unknown function: #{name}" unless fn_config

    lambda_name = fn_config["lambda_function_name"]
    raise "Function #{name} has no Lambda deployment" unless lambda_name

    require "aws-sdk-lambda"

    # The Lambda handler expects { "arguments": { ... } } and returns
    # { "result": ... } on success or { "errorMessage": ..., "errorType": ... }
    # on failure (see app/services/prompt_tracker/code_executor/lambda_adapter.rb).
    payload = { arguments: arguments }.to_json

    client = Aws::Lambda::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    response = client.invoke(function_name: lambda_name, payload: payload)
    parsed = JSON.parse(response.payload.read)

    if parsed["errorMessage"] || parsed["errorType"]
      raise "Lambda error: #{parsed['errorType']} - #{parsed['errorMessage']}"
    end

    # Unwrap to match in-process behaviour: callers see the raw user result,
    # not the { result: ... } envelope.
    parsed.key?("result") ? parsed["result"] : parsed
  end

  def render_initial_prompt
    render_template(@config["initial_prompt"])
  end

  def last_user_prompt
    last = @conversation_history.reverse.find { |m| m["role"] == "user" }
    return "" unless last
    content = last["content"]
    content.is_a?(String) ? content : content.to_s
  end

  def render_template(template)
    return "" if template.nil?

    rendered = template.dup
    variables = @config["variables"] || {}
    variables.each do |key, value|
      rendered.gsub!("{{#{key}}}", value.to_s)
    end

    rendered
  end

  def extract_final_output
    last_assistant = @conversation_history.reverse.find { |m| m["role"] == "assistant" }
    return "No output generated" unless last_assistant

    content = last_assistant["content"]
    case content
    when String then content
    when Array
      content.select { |c| c["type"] == "text" }.map { |c| c["text"] }.join("\n")
    else
      content.to_s
    end
  end

  def setup_mcp_servers
    mcp_servers = @config["mcp_servers"]
    return if mcp_servers.nil? || mcp_servers.empty?

    @logger.info "Setting up MCP filesystem server scoped to /workspace"

    @mcp_stdin, @mcp_stdout, @mcp_stderr, @mcp_wait = Open3.popen3(
      "npx", "-y", "@modelcontextprotocol/server-filesystem", "/workspace"
    )

    @mcp_process = @mcp_wait

    mcp_jsonrpc("initialize", {
      "protocolVersion" => "2024-11-05",
      "capabilities" => {},
      "clientInfo" => { "name" => "agent-runtime", "version" => "1.0" }
    })

    # MCP requires an initialized notification before regular method calls.
    mcp_notify("notifications/initialized")

    # Discover the available tools so we can expose them to the LLM with the
    # `filesystem__` prefix the dispatcher expects.
    tools_response = mcp_jsonrpc("tools/list", {})
    discovered = (tools_response.dig("result", "tools") || [])
    @mcp_tools_for_llm = discovered.map do |tool|
      {
        "name" => "filesystem__#{tool['name']}",
        "description" => tool["description"] || "MCP tool: filesystem/#{tool['name']}",
        "parameters" => tool["inputSchema"] || { "type" => "object", "properties" => {} }
      }
    end

    @logger.info "MCP filesystem server ready — discovered #{@mcp_tools_for_llm.size} tool(s): #{@mcp_tools_for_llm.map { |t| t['name'] }.join(', ')}"
  rescue => e
    @logger.error "Failed to start MCP server: #{e.message}"
    @logger.error e.backtrace&.first(10)&.join("\n")
    @mcp_process = nil
    @mcp_tools_for_llm = []
  end

  # Send a JSON-RPC request to the MCP subprocess and read one response.
  def mcp_jsonrpc(method, params)
    request = {
      "jsonrpc" => "2.0",
      "id" => SecureRandom.uuid,
      "method" => method,
      "params" => params
    }
    @mcp_stdin.puts(request.to_json)
    line = @mcp_stdout.gets
    raise "MCP server returned no response for #{method}" if line.nil?

    JSON.parse(line)
  end

  # Send a JSON-RPC notification (no response expected).
  def mcp_notify(method, params = {})
    notification = {
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
    @mcp_stdin.puts(notification.to_json)
  end

  def cleanup_mcp_servers
    return unless @mcp_stdin

    @mcp_stdin.close rescue nil
    @mcp_stdout.close rescue nil
    @mcp_stderr.close rescue nil
    @mcp_wait&.value rescue nil
  end

  def report_event(event_type, data)
    uri = URI(@callback_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    body = { "task_run_id" => @task_run_id, "event_type" => event_type, "data" => data }

    retries = 0
    begin
      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-Callback-Token"] = @callback_token
      request.body = body.to_json

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise "Callback failed with status #{response.code}: #{response.body}"
      end
    rescue => e
      retries += 1
      if retries <= MAX_CALLBACK_RETRIES
        @logger.warn "Callback failed (attempt #{retries}/#{MAX_CALLBACK_RETRIES}): #{e.message}"
        sleep(CALLBACK_RETRY_DELAY * retries)
        retry
      end

      @logger.error "Callback permanently failed: #{e.message}"
      write_fallback_event(body)
    end
  end

  def write_fallback_event(event)
    fallback_path = "/workspace/output/_events.jsonl"
    File.open(fallback_path, "a") do |f|
      f.puts(event.to_json)
    end
  end
end

AgentContainerRunner.new.run
