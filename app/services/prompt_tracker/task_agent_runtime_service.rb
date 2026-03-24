# frozen_string_literal: true

module PromptTracker
  # Service for executing task agents autonomously.
  #
  # This service handles the complete lifecycle of a task agent execution:
  # 1. Renders initial prompt with variables
  # 2. Executes autonomous loop (up to max_iterations)
  # 3. Calls LLM with function calling enabled
  # 4. Executes functions and feeds results back to LLM
  # 5. Tracks all LLM calls and function executions
  # 6. Updates TaskRun with final status and stats
  #
  # Phase 2 Implementation: Multi-turn autonomous loop with completion detection
  #
  # @example Execute a task
  #   TaskAgentRuntimeService.call(
  #     task_agent: agent,
  #     task_run: run,
  #     variables: { source_url: "https://example.com" }
  #   )
  #
  class TaskAgentRuntimeService
    attr_reader :task_agent, :task_run, :variables, :conversation_history, :logger

    # Factory method that routes to the correct subclass based on API type
    #
    # @param task_agent [DeployedAgent] the task agent to execute
    # @param task_run [TaskRun] the task run record
    # @param variables [Hash, nil] variables to pass to the task
    # @param logger [Logger, nil] custom logger instance
    # @return [Hash] execution result with :success and :output or :error
    def self.call(task_agent:, task_run:, variables: nil, logger: nil)
      # Determine API type from model_config
      model_config = task_agent.prompt_version.model_config
      api_type = ApiTypes.from_config(model_config["provider"], model_config["api"])

      # Route to appropriate subclass
      service_class = case api_type
      when :openai_responses
        TaskAgentRuntimeService::OpenaiResponses
      when :openai_assistants
        raise RuntimeError, "OpenAI Assistants API not yet supported for task agents"
      else
        # Default to base class for RubyLLM (chat completions, etc.)
        TaskAgentRuntimeService
      end

      service_class.new(task_agent: task_agent, task_run: task_run, variables: variables, logger: logger).execute
    end

    def initialize(task_agent:, task_run:, variables: nil, logger: nil)
      @task_agent = task_agent
      @task_run = task_run
      @variables = variables || task_agent.task_configuration.dig(:variables) || {}
      @iteration_count = 0
      @conversation_history = []
      @start_time = Time.current
      @current_iteration_function_calls = []
      @planning_enabled = task_agent.task_configuration.dig(:planning, :enabled) || false
      @logger = logger || Rails.logger
    end

    def execute
      @logger.info "[TaskAgentRuntimeService] Starting task run #{task_run.id} for agent #{task_agent.name}"
      @logger.info "[TaskAgentRuntimeService] Planning enabled: #{@planning_enabled}"

      # Mark task as running
      task_run.start!

      # Get execution config (with optional overrides from task_run metadata)
      execution_overrides = task_run.metadata&.dig("execution_overrides") || {}
      max_iterations = execution_overrides["max_iterations"] ||
                       task_agent.task_configuration.dig(:execution, :max_iterations) || 5
      timeout_seconds = execution_overrides["timeout_seconds"] ||
                        task_agent.task_configuration.dig(:execution, :timeout_seconds) || 3600

      @logger.info "[TaskAgentRuntimeService] 🎯 Execution Config:"
      @logger.info "[TaskAgentRuntimeService]   - Max Iterations: #{max_iterations} (override: #{execution_overrides['max_iterations'].inspect})"
      @logger.info "[TaskAgentRuntimeService]   - Timeout: #{timeout_seconds}s"
      @logger.info "[TaskAgentRuntimeService]   - Planning: #{@planning_enabled}"

      # Render initial prompt with variables
      initial_prompt = render_initial_prompt

      # Add initial user message to conversation history
      @conversation_history << { role: "user", content: initial_prompt }

      # NEW: Execute planning phase if enabled (Iteration 0)
      if @planning_enabled
        execute_planning_phase
      end

      # Phase 2: Autonomous multi-turn execution loop
      final_output = execute_autonomous_loop(max_iterations, timeout_seconds)

        # Persist final output without overriding a cancelled status
        if task_run.status_cancelled?
          task_run.update!(output_summary: final_output)
        else
          task_run.complete!(output: final_output)
        end
      task_run.update_stats!

      @logger.info "[TaskAgentRuntimeService] Task run #{task_run.id} completed successfully"

      { success: true, output: final_output }
    rescue StandardError => e
      @logger.error "[TaskAgentRuntimeService] ❌ Task run #{task_run.id} failed with exception: #{e.class.name}"
      @logger.error "[TaskAgentRuntimeService] ❌ Error message: #{e.message}"
      @logger.error "[TaskAgentRuntimeService] ❌ Backtrace:"
      e.backtrace.first(20).each do |line|
        @logger.error "[TaskAgentRuntimeService] ❌   #{line}"
      end

      # Mark task as failed (don't re-raise - we want to handle gracefully)
      begin
        task_run.fail!(error: e.message)
      rescue StandardError => fail_error
        @logger.error "[TaskAgentRuntimeService] ❌ Failed to mark task as failed: #{fail_error.message}"
        # Try to update status directly without validation
        task_run.update_columns(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )
      end

      { success: false, error: e.message }
    end

    private

    def render_initial_prompt
      template = task_agent.task_configuration[:initial_prompt]
      return template unless template.include?("{{")

      # Simple variable substitution
      rendered = template.dup
      variables.each do |key, value|
        rendered.gsub!("{{#{key}}}", value.to_s)
      end
      rendered
    end

    # Execute planning phase (Iteration 0)
    # This runs BEFORE the main execution loop and focuses solely on creating the plan
    def execute_planning_phase
      @logger.info "[TaskAgentRuntimeService] 🎯 =========================================="
      @logger.info "[TaskAgentRuntimeService] 🎯 Starting Planning Phase (Iteration 0)"
      @logger.info "[TaskAgentRuntimeService] 🎯 =========================================="

      # Mark this as planning phase in metadata
      task_run.metadata ||= {}
      task_run.metadata["planning_phase"] = {
        "started_at" => Time.current.iso8601,
        "status" => "in_progress"
      }
      task_run.save!

      # Reset function calls for planning phase
      @current_iteration_function_calls = []

      # Call LLM with planning-specific system prompt
      llm_response = call_llm(@conversation_history, phase: :planning)

      # Add assistant response to conversation history
      @conversation_history << { role: "assistant", content: llm_response[:text] }

      # Track LLM response (but don't increment iteration count - this is iteration 0)
      track_llm_response(llm_response)

      # If there were function calls, add their results to conversation history
      if @current_iteration_function_calls.present?
        @current_iteration_function_calls.each do |func_call|
          @conversation_history << {
            role: "user",
            content: "Function '#{func_call[:name]}' returned: #{func_call[:result]}"
          }
        end
      end

      # Mark planning phase as complete
      task_run.metadata["planning_phase"]["completed_at"] = Time.current.iso8601
      task_run.metadata["planning_phase"]["status"] = "completed"
      task_run.metadata["planning_phase"]["duration_seconds"] =
        Time.current - Time.parse(task_run.metadata["planning_phase"]["started_at"])
      task_run.save!

      @logger.info "[TaskAgentRuntimeService] 🎯 =========================================="
      @logger.info "[TaskAgentRuntimeService] 🎯 Planning Phase Complete"
      @logger.info "[TaskAgentRuntimeService] 🎯 =========================================="

      # Broadcast planning phase update
      broadcast_planning_phase_update
    end

      # Execute autonomous loop with multi-turn conversation
      def execute_autonomous_loop(max_iterations, timeout_seconds)
        last_response_text = nil

        loop do
          @iteration_count += 1

          # Check if task has been cancelled
          task_run.reload
          if task_run.status_cancelled?
            @logger.warn "[TaskAgentRuntimeService] Task run cancelled by user"

            task_run.metadata ||= {}
            task_run.metadata["termination_reason"] = "cancelled"
            task_run.save!

            return "Task cancelled by user"
          end

          # Check timeout first (higher priority than iteration limit)
          if Time.current - @start_time > timeout_seconds
            @logger.warn "[TaskAgentRuntimeService] Timeout (#{timeout_seconds}s) reached"

            # If planning is enabled, force completion
            if @planning_enabled
              force_plan_completion("Timeout (#{timeout_seconds}s) reached")
            end

            return "Task incomplete: Timeout reached"
          end

          # Check iteration limit
          if @iteration_count > max_iterations
            @logger.warn "[TaskAgentRuntimeService] Max iterations (#{max_iterations}) reached"

            # If planning is enabled, force completion
            if @planning_enabled
              force_plan_completion("Maximum iterations (#{max_iterations}) reached without explicit completion")
            end

            task_run.metadata ||= {}
            task_run.metadata["termination_reason"] = "max_iterations"
            task_run.save!

            return "Task incomplete: Maximum iterations reached"
          end

          # Execute one iteration
          llm_response = execute_iteration

          # Store response text
          last_response_text = llm_response[:text]

          # Check if task is complete
          if task_complete?(llm_response)
            @logger.info "[TaskAgentRuntimeService] Task completed after #{@iteration_count} iteration(s)"

            task_run.metadata ||= {}
            task_run.metadata["termination_reason"] = "success"
            task_run.save!

            return last_response_text
          end

          # If LLM made function calls, results are already in conversation history
          # Continue to next iteration
        end
      end

    # Execute a single iteration of the autonomous loop
    def execute_iteration
      task_run.increment_iteration!

      @logger.info "[TaskAgentRuntimeService] 🔄 Iteration #{@iteration_count}: Calling LLM with #{@conversation_history.length} message(s)"

      # Reset function calls for this iteration
      @current_iteration_function_calls = []

      # Call LLM with current conversation history
      llm_response = call_llm(@conversation_history)

      # Add assistant response to conversation history
      @conversation_history << { role: "assistant", content: llm_response[:text] }

      # Track LLM response
      track_llm_response(llm_response)

      # If there were function calls, add their results to conversation history
      if @current_iteration_function_calls.present?
        @current_iteration_function_calls.each do |func_call|
          @conversation_history << {
            role: "function",
            name: func_call[:name],
            content: func_call[:result].to_json
          }
        end
      end

      llm_response
    end

    # Determine if the task is complete
    # Auto-detection: Task is complete when LLM doesn't make any function calls
    # Planning mode: Task is complete when plan status is "completed"
    def task_complete?(llm_response)
      if @planning_enabled
        # With planning: only stop when plan is explicitly marked complete
        task_run.metadata&.dig("plan", "status") == "completed"
      else
        # Without planning: use configured completion criteria
        completion_type = task_agent.task_configuration.dig(:completion_criteria, :type) || "auto"

        case completion_type
        when "auto"
          # Task is complete when no function calls are made
          @current_iteration_function_calls.blank?
        when "explicit"
          # Task is complete when agent calls a specific completion function
          # (e.g., mark_task_complete)
          @current_iteration_function_calls.any? { |fc| fc[:name] == "mark_task_complete" }
        else
          # Default to auto
          @current_iteration_function_calls.blank?
        end
      end
    end

    # Call LLM with function calling support
    #
    # This is the default implementation for RubyLLM (chat completions).
    # Subclasses can override this method for specialized APIs (e.g., Responses API).
    #
    # @param messages [Array<Hash>] conversation messages
    # @param phase [Symbol] :planning or :execution
    # @return [Hash] normalized LLM response
    def call_llm(messages, phase: :execution)
      model_config = task_agent.prompt_version.model_config
      system_prompt = task_agent.prompt_version.system_prompt

      # Enhance system prompt with planning instructions if enabled
      if @planning_enabled
        @logger.info "[TaskAgentRuntimeService] 🎯 Enhancing system prompt with planning instructions (phase: #{phase})"
        system_prompt = enhance_system_prompt_with_planning(system_prompt, phase: phase)
      end

      # Build tools array from function definitions + planning functions
      tools = build_tools_array(phase: phase)

      @logger.info "[TaskAgentRuntimeService] Calling LLM with #{tools.length} function(s)"
      @logger.info "[TaskAgentRuntimeService] User message: #{messages.last[:content][0..200]}..."

      # Create custom executor for function calls
      executor = lambda do |function_name, arguments|
        @logger.info "[TaskAgentRuntimeService] 🔧 Executor called for: #{function_name}"
        @logger.info "[TaskAgentRuntimeService] 🔧 Arguments received: #{arguments.inspect}"
        @logger.info "[TaskAgentRuntimeService] 🔧 Arguments class: #{arguments.class}"

        # Check if this is a planning function
        if planning_function?(function_name)
          result = execute_planning_function(function_name, arguments)
          @current_iteration_function_calls << { name: function_name, arguments: arguments, result: result }
          return result
        end

        # Regular function execution
        func_def = task_agent.function_definitions.find_by(name: function_name)
        unless func_def
          @logger.error "[TaskAgentRuntimeService] Function not found: #{function_name}"
          error_result = { error: "Function not found: #{function_name}" }
          @current_iteration_function_calls << { name: function_name, arguments: arguments, result: error_result }
          return error_result
        end

        result = execute_function(func_def, arguments)
        function_result = result[:success?] ? result[:result] : { error: result[:error] }

        # Track this function call in the instance variable
        @current_iteration_function_calls << { name: function_name, arguments: arguments, result: function_result }

        function_result
      end

      # Extract user prompt from messages
      user_prompt = messages.last[:content]

      # Build a chat instance and call it
      # This allows RubyLLM to handle the tool execution loop internally
      service = LlmClients::RubyLlmService.new(
        model: model_config["model"],
        prompt: user_prompt,
        system: system_prompt,
        tools: tools.present? ? [ :functions ] : [],
        tool_config: { "functions" => tools },
        function_executor: executor,
        temperature: model_config["temperature"]
      )

      # Call the LLM and get the response
      service.call
    end

    def build_tools_array(phase: :execution)
      tools = []

      # During planning phase, ONLY include create_plan function
      if phase == :planning
        if @planning_enabled && !task_run.metadata&.dig("plan")
          tools << {
            "name" => "create_plan",
            "description" => "Create an execution plan with specific steps. MUST be called before starting work on the first iteration.",
            "parameters" => {
              "type" => "object",
              "required" => [ "goal", "steps" ],
              "properties" => {
                "goal" => {
                  "type" => "string",
                  "description" => "Clear statement of what you're trying to achieve"
                },
                "steps" => {
                  "type" => "array",
                  "description" => "List of 3-7 specific steps to accomplish the goal",
                  "items" => { "type" => "string" }
                }
              }
            }
          }
        end
      else
        # During execution phase, include all regular functions
        tools = task_agent.function_definitions.map do |func_def|
          {
            "name" => func_def.name,
            "description" => func_def.description,
            "parameters" => func_def.parameters
          }
        end

        # Inject planning functions if enabled (but not create_plan)
        if @planning_enabled
          planning_tools = build_planning_functions
          @logger.info "[TaskAgentRuntimeService] Injecting #{planning_tools.size} planning functions"
          tools += planning_tools
        end
      end

      @logger.info "[TaskAgentRuntimeService] Total tools available: #{tools.size} (#{tools.map { |t| t['name'] }.join(', ')})"
      tools
    end

    def execute_function(func_def, arguments)
      @logger.info "[TaskAgentRuntimeService] 🔧 Executing function: #{func_def.name}"
      @logger.info "[TaskAgentRuntimeService]    Deployment status: #{func_def.deployment_status}"
      @logger.info "[TaskAgentRuntimeService]    Lambda function name: #{func_def.lambda_function_name.inspect}"
      @logger.info "[TaskAgentRuntimeService]    Arguments: #{arguments.inspect}"

      # Ensure function is deployed
      unless func_def.deployed?
        @logger.info "[TaskAgentRuntimeService] Function not deployed. Deploying now..."
        deploy_result = func_def.deploy
        @logger.info "[TaskAgentRuntimeService] Deployment result: #{deploy_result}"

        unless deploy_result
          error_msg = "Failed to deploy function: #{func_def.deployment_error}"
          @logger.error "[TaskAgentRuntimeService] #{error_msg}"
          return { success?: false, result: nil, error: error_msg }
        end

        @logger.info "[TaskAgentRuntimeService] Function deployed successfully. Lambda name: #{func_def.lambda_function_name}"
      end

      # Execute via Lambda
      @logger.info "[TaskAgentRuntimeService] Calling CodeExecutor.execute with lambda_function_name: #{func_def.lambda_function_name}"
      result = PromptTracker::CodeExecutor.execute(
        lambda_function_name: func_def.lambda_function_name,
        arguments: arguments
      )

      @logger.info "[TaskAgentRuntimeService] ✅ Execution result - Success: #{result.success?}, Error: #{result.error.inspect}"

      # Track execution
      # TODO: Populate planning_step_id when we have a way to determine which step triggered this execution
      # This could be done by:
      # 1. Adding a "current_step_id" parameter to function calls
      # 2. Inferring from the plan's current in_progress step
      # 3. Having the LLM explicitly state which step it's working on

      # Ensure arguments is always a Hash (never nil)
      normalized_arguments = arguments.is_a?(Hash) ? arguments : {}

      @logger.info "[TaskAgentRuntimeService] 🎯 Creating FunctionExecution for #{func_def.name} with:"
      @logger.info "[TaskAgentRuntimeService] 🎯   - arguments: #{normalized_arguments.inspect}"
      @logger.info "[TaskAgentRuntimeService] 🎯   - result: #{result.result.inspect}"
      @logger.info "[TaskAgentRuntimeService] 🎯   - success: #{result.success?}"

      function_execution = PromptTracker::FunctionExecution.new(
        function_definition: func_def,
        deployed_agent: task_agent,
        task_run: task_run,
        arguments: normalized_arguments,
        result: result.result,
        success: result.success?,
        error_message: result.error,
        execution_time_ms: result.execution_time_ms,
        executed_at: Time.current,
        planning_step_id: nil  # Will be populated in future iteration
      )

      unless function_execution.valid?
        @logger.error "[TaskAgentRuntimeService] ❌ FunctionExecution validation failed for #{func_def.name}!"
        @logger.error "[TaskAgentRuntimeService] ❌ Errors: #{function_execution.errors.full_messages.inspect}"
        function_execution.errors.details.each do |field, errors|
          @logger.error "[TaskAgentRuntimeService] ❌   #{field}: #{errors.inspect}"
        end
      end

      function_execution.save!
      @logger.info "[TaskAgentRuntimeService] ✅ FunctionExecution saved successfully (ID: #{function_execution.id})"

      # Broadcast timeline update via Turbo Stream
      broadcast_timeline_update

      { success?: result.success?, result: result.result, error: result.error }
    end

    def track_llm_response(llm_response, rendered_prompt: nil)
      model_config = task_agent.prompt_version.model_config
      provider = model_config["provider"] || "openai"

      # Use explicit prompt if provided, otherwise fall back to conversation history
      # This allows Responses API to pass custom prompts for continuation calls
      rendered_prompt ||= begin
        last_user_message = @conversation_history.reverse.find { |msg| msg[:role] == "user" }
        last_user_message&.dig(:content) || ""
      end

      llm_response_record = PromptTracker::LlmResponse.create!(
        prompt_version: task_agent.prompt_version,
        deployed_agent: task_agent,
        task_run: task_run,
        rendered_prompt: rendered_prompt,
        response_text: llm_response[:text],
        model: llm_response[:model],
        provider: provider,
        tokens_prompt: llm_response.dig(:usage, :prompt_tokens),
        tokens_completion: llm_response.dig(:usage, :completion_tokens),
        tokens_total: llm_response.dig(:usage, :total_tokens),
        status: "success",
        tool_calls: llm_response[:tool_calls] || [],  # Store LLM's intent to call tools
        context: {
          task_run_id: task_run.id,
          iteration: @iteration_count,
          conversation_length: @conversation_history.length,
          function_calls_count: @current_iteration_function_calls.length
        }
      )

      # Broadcast timeline update via Turbo Stream
      broadcast_timeline_update

      llm_response_record
    end

    # Planning-specific methods

    def planning_function?(function_name)
      %w[create_plan get_plan update_step add_step mark_task_complete].include?(function_name)
    end

    def execute_planning_function(function_name, arguments)
      @logger.info "[TaskAgentRuntimeService] 🎯 Executing planning function: #{function_name}"
      @logger.info "[TaskAgentRuntimeService] 🎯 Arguments: #{arguments.inspect}"
      @logger.info "[TaskAgentRuntimeService] 🎯 Arguments class: #{arguments.class}"
      @logger.info "[TaskAgentRuntimeService] 🎯 Arguments blank?: #{arguments.blank?}"

      start_time = Time.current

      result = case function_name
      when "create_plan"
        PlanningService.create_plan(task_run, arguments)
      when "get_plan"
        PlanningService.get_plan(task_run)
      when "update_step"
        PlanningService.update_step(task_run, arguments)
      when "add_step"
        PlanningService.add_step(task_run, arguments)
      when "mark_task_complete"
        PlanningService.mark_task_complete(task_run, arguments)
      else
        { success: false, error: "Unknown planning function: #{function_name}" }
      end

      execution_time_ms = ((Time.current - start_time) * 1000).round(2)

      @logger.info "[TaskAgentRuntimeService] 🎯 Planning function result: #{result.inspect}"

      # Track planning function execution (without function_definition since it's virtual)
      success = result[:success] || result["success"] || false
      error_message = result[:error] || result["error"]

      # Ensure arguments is always a Hash (never nil)
      normalized_arguments = arguments.is_a?(Hash) ? arguments : {}

      @logger.info "[TaskAgentRuntimeService] 🎯 Creating FunctionExecution with:"
      @logger.info "[TaskAgentRuntimeService] 🎯   - arguments: #{normalized_arguments.inspect}"
      @logger.info "[TaskAgentRuntimeService] 🎯   - result: #{result.inspect}"
      @logger.info "[TaskAgentRuntimeService] 🎯   - success: #{success}"

      function_execution = PromptTracker::FunctionExecution.new(
        function_definition: nil,  # Planning functions are virtual
        deployed_agent: task_agent,
        task_run: task_run,
        arguments: normalized_arguments,
        result: result,
        success: success,
        error_message: error_message,
        execution_time_ms: execution_time_ms,
        executed_at: Time.current,
        planning_step_id: nil  # Will be populated when we link to specific plan steps
      )

      unless function_execution.valid?
        @logger.error "[TaskAgentRuntimeService] ❌ FunctionExecution validation failed!"
        @logger.error "[TaskAgentRuntimeService] ❌ Errors: #{function_execution.errors.full_messages.inspect}"
        function_execution.errors.details.each do |field, errors|
          @logger.error "[TaskAgentRuntimeService] ❌   #{field}: #{errors.inspect}"
        end
      end

      function_execution.save!
      @logger.info "[TaskAgentRuntimeService] ✅ FunctionExecution saved successfully (ID: #{function_execution.id})"

      # Broadcast timeline update
      broadcast_timeline_update

      result
    end

      def build_planning_functions
        [
          {
            "name" => "get_plan",
            "description" => "Get the current execution plan with progress information",
            "parameters" => {
              "type" => "object",
              "properties" => {}
            }
          },
          {
            "name" => "update_step",
            "description" => "Update a step's status and add notes about progress",
            "parameters" => {
              "type" => "object",
              "required" => [ "step_id", "status" ],
              "properties" => {
                "step_id" => {
                  "type" => "string",
                  "description" => "Step ID (e.g., 'step_1', 'step_2')"
                },
                "status" => {
                  "type" => "string",
                  "enum" => [ "pending", "in_progress", "completed", "failed", "skipped" ],
                  "description" => "New status for the step"
                },
                "notes" => {
                  "type" => "string",
                  "description" => "Optional notes about what was done or discovered"
                }
              }
            }
          },
          {
            "name" => "add_step",
            "description" => "Add a new step to the plan if you discover additional work needed",
            "parameters" => {
              "type" => "object",
              "required" => [ "description" ],
              "properties" => {
                "description" => {
                  "type" => "string",
                  "description" => "Description of the new step"
                },
                "after_step_id" => {
                  "type" => "string",
                  "description" => "Optional: Insert after this step ID"
                }
              }
            }
          },
          {
            "name" => "mark_task_complete",
            "description" => "Mark the entire task as complete with a summary. MUST be called when all steps are done.",
            "parameters" => {
              "type" => "object",
              "required" => [ "summary" ],
              "properties" => {
                "summary" => {
                  "type" => "string",
                  "description" => "Comprehensive summary of what was accomplished"
                }
              }
            }
          }
        ]
      end

    def force_plan_completion(reason)
      @logger.warn "[TaskAgentRuntimeService] 🛑 Forcing plan completion: #{reason}"

      plan = task_run.metadata&.dig("plan")
      return unless plan

      # Mark all in-progress steps as incomplete
      in_progress_steps = plan["steps"].select { |s| s["status"] == "in_progress" }
      in_progress_steps.each do |step|
        step["status"] = "failed"
        step["notes"] = (step["notes"] || "") + "\n\n[Auto-failed: #{reason}]"
        step["completed_at"] = Time.current.iso8601
      end

      # Mark plan as failed
      plan["status"] = "failed"
      plan["completion_summary"] = "Task failed to complete properly. #{reason}. #{in_progress_steps.size} step(s) were left incomplete."
      plan["updated_at"] = Time.current.iso8601

      task_run.output_summary = plan["completion_summary"]
      task_run.save!

      # Broadcast final update
      PlanningService.send(:broadcast_plan_update, task_run, "failed")

      @logger.info "[TaskAgentRuntimeService] ✅ Plan forcibly completed with #{in_progress_steps.size} failed steps"
    end

    def enhance_system_prompt_with_planning(original_prompt, phase: :execution)
      if phase == :planning
        # Planning Phase Instructions (Iteration 0)
        planning_instructions = <<~INSTRUCTIONS


          ## 🎯 PLANNING PHASE

          This is the PLANNING PHASE. Your ONLY job right now is to create a plan.

          **What to do:**
          1. Understand the task goal from the user's request
          2. Call `create_plan(goal, steps)` with:
             - A clear, specific goal statement
             - 3-7 concrete, actionable steps
          3. Do NOT execute any work yet - just create the plan

          **Important:**
          - Steps should be ACTUAL WORK steps (e.g., "Fetch news articles", "Analyze data", "Generate summary")
          - Do NOT include "Create a plan" as a step - that's what you're doing right now
          - Each step should be specific and measurable
          - Steps should be in logical order

          **After you create the plan:**
          - The EXECUTION PHASE will begin
          - You'll work through the steps one by one
          - You can update step statuses and adapt the plan as needed

          **Example:**
          ```
          create_plan(
            goal: "Monitor technology news and create a daily summary",
            steps: [
              "Fetch latest AI news articles",
              "Fetch latest cloud computing news",
              "Fetch latest cybersecurity news",
              "Analyze gathered articles for key trends",
              "Draft comprehensive summary"
            ]
          )
          ```

          Now, create your plan!
        INSTRUCTIONS
      else
        # Execution Phase Instructions (Iteration 1+)
        planning_instructions = <<~INSTRUCTIONS


          ## 🎯 EXECUTION PHASE

          You have already created a plan. Now execute it step by step.

          **Workflow:**

          1. **Check Your Plan**:
             - Call `get_plan()` to see your current plan and step statuses
             - Identify which step to work on next (usually the first "pending" step)

          2. **Execute Steps Sequentially**:
             - Work on ONE step at a time
             - For each step:
               a) Call `update_step(step_id, "in_progress", "Starting...")`
               b) Perform the necessary function calls
               c) If successful: Call `update_step(step_id, "completed", "Summary of results")`
               d) If failed: Call `update_step(step_id, "failed", "Error: [description]")`
             - ALWAYS update the step status before moving to the next step
             - At the end of each iteration, reflect: Did I complete/fail the current step?

          3. **Handle Errors Gracefully**:
             - If a function returns an error (e.g., syntax errors, API failures):
               * Mark the current step as "failed" with the error details
               * Decide: Can you continue with remaining steps, or must you abort?
               * If aborting: Clean up remaining steps (see step 5) then call `mark_task_complete()`
               * DO NOT continue calling the same failing function repeatedly

          4. **Adapt if Needed**:
             - If you discover new work, call `add_step()` to add it to the plan
             - Update step status to "skipped" if a step becomes unnecessary

          5. **Clean Up Before Completion** (CRITICAL):
             - BEFORE calling `mark_task_complete()`, you MUST clean up all step statuses:
               * Any steps still "in_progress" → update to "completed", "failed", or "skipped"
               * Any steps still "pending" that won't be done → update to "skipped"
             - Example cleanup sequence:
               ```
               update_step("step_3", "completed", "Finished analysis")
               update_step("step_4", "skipped", "Not needed due to earlier errors")
               update_step("step_5", "skipped", "Cannot proceed without step 2 data")
               mark_task_complete("Summary of what was accomplished...")
               ```

          6. **Complete Explicitly**:
             - When ALL steps are done (or task cannot continue), call `mark_task_complete(summary)`
             - The summary should describe what was accomplished AND any failures encountered
             - DO NOT stop without calling this function
             - Even if you hit errors, you MUST call `mark_task_complete()` to end the task

          7. **Never Over-Iterate**:
             - If you've completed your plan, clean up step statuses then call `mark_task_complete()` immediately
             - Don't perform redundant searches or unnecessary follow-ups
             - Trust your initial findings unless there's a clear gap
             - If you encounter the same error twice, stop, clean up, and complete the task

          You can check your current plan anytime with `get_plan()`.

          REMEMBER: The UI shows step statuses to users. Always keep them accurate and up-to-date!
        INSTRUCTIONS
      end

      original_prompt + planning_instructions
    end

    # Broadcast timeline update to the task run show page
    def broadcast_timeline_update
      @logger.info "[TaskAgentRuntimeService] 📡 Broadcasting timeline update for task run #{task_run.id}"

      # Reload task run to get fresh data
      task_run.reload

      # Get all LLM responses and function executions
      llm_responses = task_run.llm_responses.order(created_at: :asc).to_a
      function_executions = task_run.function_executions.order(created_at: :asc).to_a

      @logger.info "[TaskAgentRuntimeService] 📡 Timeline data: #{llm_responses.count} LLM responses, #{function_executions.count} function executions"

      # Rebuild timeline (same logic as controller)
      timeline = build_timeline_for_broadcast(llm_responses, function_executions)

      @logger.info "[TaskAgentRuntimeService] 📡 Timeline built: #{timeline.count} iterations"

      # Broadcast timeline to the task run's stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "task_run_#{task_run.id}",
        target: "execution_timeline",
        partial: "prompt_tracker/task_runs/timeline",
        locals: { timeline: timeline, task_run: task_run }
      )

      @logger.info "[TaskAgentRuntimeService] ✅ Timeline broadcast successful"

      # Broadcast summary cards update
      broadcast_summary_cards_update
    rescue StandardError => e
      @logger.error "[TaskAgentRuntimeService] ❌ Failed to broadcast timeline update: #{e.message}"
      @logger.error "[TaskAgentRuntimeService] ❌ Backtrace: #{e.backtrace.first(5).join("\n")}"
      # Don't fail the task if broadcast fails
    end

    # Broadcast planning phase update to the task run show page
    def broadcast_planning_phase_update
      # Reload task run to get fresh data
      task_run.reload

      # Get all LLM responses
      llm_responses = task_run.llm_responses.order(created_at: :asc)

      # Broadcast to the task run's stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "task_run_#{task_run.id}",
        target: "planning_phase_card",
        partial: "prompt_tracker/task_runs/planning_phase",
        locals: { task_run: task_run, llm_responses: llm_responses, agent: task_run.deployed_agent }
      )
    rescue StandardError => e
      @logger.error "[TaskAgentRuntimeService] Failed to broadcast planning phase update: #{e.message}"
      # Don't fail the task if broadcast fails
    end

    # Broadcast summary cards update to the task run show page
    def broadcast_summary_cards_update
      @logger.info "[TaskAgentRuntimeService] 📡 Broadcasting summary cards update for task run #{task_run.id}"

      # Reload task run to get fresh data
      task_run.reload

      # Get counts
      llm_responses = task_run.llm_responses
      function_executions = task_run.function_executions

      @logger.info "[TaskAgentRuntimeService] 📡 Summary data: #{llm_responses.count} LLM calls, #{function_executions.count} function calls, iterations: #{task_run.iterations_count}"

      # Broadcast to the task run's stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "task_run_#{task_run.id}",
        target: "summary_cards",
        partial: "prompt_tracker/task_runs/summary_cards",
        locals: {
          task_run: task_run,
          llm_responses: llm_responses,
          function_executions: function_executions
        }
      )

      @logger.info "[TaskAgentRuntimeService] ✅ Summary cards broadcast successful"
    rescue StandardError => e
      @logger.error "[TaskAgentRuntimeService] ❌ Failed to broadcast summary cards update: #{e.message}"
      @logger.error "[TaskAgentRuntimeService] ❌ Backtrace: #{e.backtrace.first(5).join("\n")}"
      # Don't fail the task if broadcast fails
    end

    # Build timeline structure (same as TaskRunsController#build_timeline)
    def build_timeline_for_broadcast(llm_responses, function_executions)
      events = []

      # Add LLM responses
      llm_responses.each do |response|
        iteration = response.context&.dig("iteration") || 0
        events << {
          type: :llm_response,
          timestamp: response.created_at,
          iteration: iteration,
          data: response
        }
      end

      # Add function executions
      function_executions.each do |execution|
        next_response = llm_responses
          .select { |r| r.created_at > execution.created_at }
          .min_by(&:created_at)
        iteration = next_response&.context&.dig("iteration") || 1

        events << {
          type: :function_execution,
          timestamp: execution.created_at,
          iteration: iteration,
          data: execution
        }
      end

      # Sort by timestamp
      events.sort_by! { |e| e[:timestamp] }

      # Group by iteration
      grouped = events.group_by { |e| e[:iteration] }

      # Build hierarchical structure
      iterations = grouped.map do |iteration_num, iteration_events|
        {
          iteration: iteration_num,
          events: iteration_events,
          started_at: iteration_events.first[:timestamp],
          completed_at: iteration_events.last[:timestamp],
          duration_ms: ((iteration_events.last[:timestamp] - iteration_events.first[:timestamp]) * 1000).round(0),
          llm_calls_count: iteration_events.count { |e| e[:type] == :llm_response },
          function_calls_count: iteration_events.count { |e| e[:type] == :function_execution }
        }
      end

      iterations.sort_by { |i| i[:iteration] }
    end
  end
end
