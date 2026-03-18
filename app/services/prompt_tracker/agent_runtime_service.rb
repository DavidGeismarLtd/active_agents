# frozen_string_literal: true

module PromptTracker
  # Service for executing agent conversations with function calling support.
  #
  # This service:
  # 1. Loads or creates conversation state
  # 2. Calls LLM with conversation history
  # 3. Executes function calls (if any)
  # 4. Loops back to LLM with function results
  # 5. Tracks all interactions for monitoring
  #
  # @example Execute a conversation turn
  #   result = AgentRuntimeService.call(
  #     deployed_agent: agent,
  #     message: "What's the weather in Berlin?",
  #     conversation_id: "conv_123",
  #     metadata: { user_id: "user_456" }
  #   )
  #
  #   if result.success?
  #     puts result.response
  #     puts result.conversation_id
  #     puts result.function_calls
  #   end
  #
  class AgentRuntimeService
    class RuntimeError < StandardError; end

    Result = Struct.new(:success?, :response, :conversation_id, :function_calls, :error, keyword_init: true)

    MAX_FUNCTION_ITERATIONS = 5 # Prevent infinite loops

    def self.call(deployed_agent:, message:, conversation_id: nil, metadata: {})
      new(deployed_agent, message, conversation_id, metadata).execute
    end

    attr_reader :deployed_agent, :message, :conversation_id, :metadata

    def initialize(deployed_agent, message, conversation_id, metadata)
      @deployed_agent = deployed_agent
      @message = message
      @conversation_id = conversation_id || SecureRandom.uuid
      @metadata = metadata
      @function_calls = []
      @iteration_count = 0
    end

    def execute
      validate_input!

      # 1. Load or create conversation
      conversation = load_or_create_conversation

      # 2. Add user message to conversation
      conversation.add_message(role: "user", content: message)

      # 3. Execute LLM call with function calling loop
      llm_response = execute_with_function_calling(conversation)

      # 4. Save assistant response to conversation
      conversation.add_message(role: "assistant", content: llm_response[:text])
      conversation.extend_ttl!

      # 5. Track in monitoring (create LlmResponse record)
      track_response(llm_response, conversation)

      # 6. Update agent stats
      update_agent_stats

      Result.new(
        success?: true,
        response: llm_response[:text],
        conversation_id: @conversation_id,
        function_calls: @function_calls
      )
    rescue RuntimeError => e
      deployed_agent.update!(status: "error", error_message: e.message)
      Result.new(success?: false, error: e.message)
    rescue StandardError => e
      Rails.logger.error("AgentRuntimeService error: #{e.message}\n#{e.backtrace.join("\n")}")
      deployed_agent.update!(status: "error", error_message: e.message)
      Result.new(success?: false, error: "Internal error: #{e.message}")
    end

    private

    def validate_input!
      raise RuntimeError, "Message is required" if message.blank?
      raise RuntimeError, "Message too long (max 10,000 characters)" if message.length > 10_000
      raise RuntimeError, "Conversation ID format invalid" if conversation_id.present? && !valid_conversation_id?
    end

    def valid_conversation_id?
      # Allow UUID format or alphanumeric with hyphens/underscores
      conversation_id.match?(/\A[a-zA-Z0-9_-]+\z/)
    end

    def load_or_create_conversation
      deployed_agent.agent_conversations.find_or_create_by!(conversation_id: conversation_id) do |conv|
        ttl = deployed_agent.config[:conversation_ttl] || 3600
        conv.expires_at = ttl.seconds.from_now
        conv.metadata = metadata
      end
    end

    def execute_with_function_calling(conversation)
      # Build messages array from conversation history
      messages = build_messages_array(conversation)

      # Call LLM (RubyLlmService handles function calls automatically)
      llm_response = call_llm(messages)

      # Extract tool calls from the response (they were executed automatically by RubyLlmService)
      tool_calls = llm_response[:tool_calls] || []

      Rails.logger.info "[AgentRuntimeService] LLM response received. Tool calls: #{tool_calls.length}"

      # Store function calls for tracking
      if tool_calls.present?
        @function_calls = tool_calls.map do |tc|
          {
            name: tc[:function_name],
            arguments: tc[:arguments],
            id: tc[:id]
          }
        end
        Rails.logger.info "[AgentRuntimeService] Captured #{@function_calls.length} function call(s): #{@function_calls.map { |f| f[:name] }.join(', ')}"
      end

      llm_response
    end

    def build_messages_array(conversation)
      messages = []

      # Add system prompt if present
      system_prompt = deployed_agent.prompt_version.system_prompt
      messages << { role: "system", content: system_prompt } if system_prompt.present?

      # Add conversation history
      conversation.messages.each do |msg|
        messages << {
          role: msg["role"],
          content: msg["content"]
        }.tap do |m|
          m[:tool_calls] = msg["tool_calls"] if msg["tool_calls"].present?
          m[:tool_call_id] = msg["tool_call_id"] if msg["tool_call_id"].present?
          m[:name] = msg["name"] if msg["name"].present?
        end
      end

      messages
    end

    def call_llm(messages)
      model_config = deployed_agent.prompt_version.model_config

      # Build tools array from function definitions
      tools = build_tools_array

      Rails.logger.info "[AgentRuntimeService] Calling LLM with #{tools.length} function(s): #{tools.map { |t| t['name'] }.join(', ')}"

      # Determine API type
      api_type = ApiTypes.from_config(model_config[:provider], model_config[:api])

      # Call appropriate LLM service based on API type
      case api_type
      when :openai_responses
        call_openai_responses(messages, model_config, tools)
      when :openai_assistants
        call_openai_assistants(messages, model_config)
      else
        call_ruby_llm(messages, model_config, tools)
      end
    end

    def call_openai_responses(messages, model_config, tools)
      # For Responses API, we need to handle conversation differently
      # It uses previous_response_id for context
      raise RuntimeError, "OpenAI Responses API not yet supported for deployed agents"
    end

    def call_openai_assistants(messages, model_config)
      # For Assistants API, we need assistant_id
      assistant_id = model_config.dig(:metadata, :assistant_id)
      raise RuntimeError, "Assistant ID not configured" unless assistant_id.present?

      LlmClients::OpenaiAssistantService.call(
        assistant_id: assistant_id,
        user_message: message
      )
    end

    def call_ruby_llm(messages, model_config, tools)
      # Extract system prompt from messages
      system_prompt = messages.find { |m| m[:role] == "system" }&.dig(:content)
      user_messages = messages.reject { |m| m[:role] == "system" }

      # For now, we'll use the last user message as the prompt
      # TODO: Support full conversation history
      user_prompt = user_messages.last&.dig(:content) || message

      LlmClients::RubyLlmService.call(
        model: model_config[:model],
        prompt: user_prompt,
        system: system_prompt,
        tools: parse_tool_symbols(tools),
        tool_config: { "functions" => tools }, # Use string key for RubyLlmService
        temperature: model_config[:temperature]
      )
    end

    def build_tools_array
      # Return array of function definitions in the format expected by RubyLlmService
      deployed_agent.function_definitions.map do |func_def|
        {
          "name" => func_def.name,
          "description" => func_def.description,
          "parameters" => func_def.parameters
        }
      end
    end

    def parse_tool_symbols(tools)
      # If we have custom functions, enable :functions tool
      tools.present? ? [ :functions ] : []
    end

    def execute_functions(tool_calls, conversation)
      tool_calls.map do |tool_call|
        func_name = tool_call[:name] || tool_call.dig(:function, :name)
        func_args = tool_call[:arguments] || tool_call.dig(:function, :arguments) || {}

        func_def = deployed_agent.function_definitions.find_by(name: func_name)

        if func_def
          execute_single_function(func_def, func_args, conversation)
        else
          {
            success?: false,
            result: nil,
            error: "Function not found: #{func_name}"
          }
        end
      end
    end

    def execute_single_function(func_def, arguments, conversation)
      start_time = Time.current

      # TODO: Execute via CodeExecutor (Lambda/Docker)
      # For now, return a mock result
      result = {
        success?: true,
        result: { message: "Function execution not yet implemented" },
        error: nil
      }

      execution_time_ms = ((Time.current - start_time) * 1000).to_i

      # Track execution
      PromptTracker::FunctionExecution.create!(
        function_definition: func_def,
        deployed_agent: deployed_agent,
        agent_conversation: conversation,
        arguments: arguments,
        result: result[:result],
        success: result[:success?],
        error_message: result[:error],
        execution_time_ms: execution_time_ms,
        executed_at: Time.current
      )

      result
    rescue StandardError => e
      Rails.logger.error("Function execution error: #{e.message}")
      {
        success?: false,
        result: nil,
        error: e.message
      }
    end

    def add_function_results_to_conversation(conversation, tool_calls, function_results)
      tool_calls.each_with_index do |tool_call, index|
        func_name = tool_call[:name] || tool_call.dig(:function, :name)
        tool_call_id = tool_call[:id] || "call_#{SecureRandom.hex(8)}"
        result = function_results[index]

        conversation.add_tool_result(
          tool_call_id: tool_call_id,
          name: func_name,
          content: result[:result].to_json
        )
      end
    end

    def track_response(llm_response, conversation)
      # Create LlmResponse record for monitoring
      model_config = deployed_agent.prompt_version.model_config
      provider = model_config["provider"] || model_config[:provider] || "openai"

      PromptTracker::LlmResponse.create!(
        prompt_version: deployed_agent.prompt_version,
        agent_conversation: conversation,
        rendered_prompt: message,
        response_text: llm_response[:text],
        model: llm_response[:model],
        provider: provider,
        tokens_prompt: llm_response.dig(:usage, :prompt_tokens),
        tokens_completion: llm_response.dig(:usage, :completion_tokens),
        tokens_total: llm_response.dig(:usage, :total_tokens),
        status: "success",
        context: {
          conversation_id: conversation_id,
          function_calls: @function_calls,
          deployed_agent_id: deployed_agent.id
        }
      )
    rescue StandardError => e
      Rails.logger.error("Failed to track response: #{e.message}")
      # Don't fail the request if tracking fails
    end

    def update_agent_stats
      deployed_agent.increment!(:request_count)
      deployed_agent.update_column(:last_request_at, Time.current)
    rescue StandardError => e
      Rails.logger.error("Failed to update agent stats: #{e.message}")
      # Don't fail the request if stats update fails
    end
  end
end
