# frozen_string_literal: true

module PromptTracker
  module Anthropic
    module Messages
      # Handles function call loops for Anthropic Messages API.
      #
      # The Messages API may return tool_use content blocks that need to be
      # executed and sent back before getting a final text response. This class
      # manages that iterative loop with safeguards against infinite loops.
      #
      # Key differences from OpenAI:
      # - Stateless: must track full conversation history ourselves
      # - Tool results sent as user messages with tool_result content blocks
      # - No previous_response_id - we append to message history
      #
      # @example Handle function calls
      #   handler = FunctionCallHandler.new(
      #     model: "claude-3-5-sonnet-20241022",
      #     tools: [:functions],
      #     tool_config: { "functions" => [...] },
      #     use_real_llm: true
      #   )
      #   result = handler.process_with_function_handling(
      #     initial_response: response,
      #     conversation_history: messages,
      #     system_prompt: "You are helpful."
      #   )
      #   # => { final_response: {...}, all_tool_calls: [...], all_responses: [...], updated_history: [...] }
      #
      class FunctionCallHandler
        # Maximum iterations to prevent infinite loops
        MAX_ITERATIONS = 10

        # @param model [String] the model name
        # @param tools [Array] enabled tools
        # @param tool_config [Hash] tool configuration
        # @param use_real_llm [Boolean] whether to use real LLM
        # @param mock_function_outputs [Hash] custom mock responses per function name
        # @param temperature [Float, nil] temperature for API calls
        def initialize(model:, tools:, tool_config:, use_real_llm:, mock_function_outputs: nil, temperature: nil)
          @model = model
          @tools = tools
          @tool_config = tool_config
          @use_real_llm = use_real_llm
          @temperature = temperature
          @input_builder = build_input_builder(mock_function_outputs)
        end

        # Process an API response and handle any function calls
        #
        # @param initial_response [NormalizedLlmResponse] the initial API response
        # @param conversation_history [Array<Hash>] current conversation messages
        # @param system_prompt [String, nil] system prompt for continuation calls
        # @param turn [Integer] current turn number (for logging)
        # @return [Hash] result with :final_response, :all_tool_calls, :all_responses, :updated_history
        def process_with_function_handling(initial_response:, conversation_history:, system_prompt: nil, turn: 1)
          all_tool_calls = []
          all_responses = [ initial_response ]
          response = initial_response
          history = conversation_history.dup
          iteration_count = 0

          # Loop while response contains tool calls and we haven't hit the limit
          while response[:tool_calls].present? && iteration_count < MAX_ITERATIONS
            iteration_count += 1

            tool_calls = response[:tool_calls]
            log_function_calls_received(tool_calls, iteration_count, turn)

            # Collect tool calls
            all_tool_calls.concat(tool_calls)

            # Add assistant's tool_use response to history
            history << build_assistant_tool_use_message(response)

            # Build and add tool_result message to history
            tool_result_message = @input_builder.build_tool_result_message(tool_calls)
            history << tool_result_message
            log_continuation_input(tool_result_message, iteration_count)

            # Call API with updated history
            response = call_api_with_history(history, system_prompt)
            all_responses << response
          end

          # Handle remaining tool calls if limit reached
          if iteration_count >= MAX_ITERATIONS && response[:tool_calls].present?
            all_tool_calls.concat(response[:tool_calls])
          end

          log_iteration_limit_warning(iteration_count, response, turn)

          {
            final_response: response,
            all_tool_calls: all_tool_calls,
            all_responses: all_responses,
            updated_history: history
          }
        end

        private

        # Build the input builder with a function executor
        #
        # @param mock_function_outputs [Hash, nil] custom mock responses
        # @return [FunctionInputBuilder]
        def build_input_builder(mock_function_outputs)
          # Reuse OpenAI's FunctionExecutor - the logic is identical
          executor = Openai::Responses::FunctionExecutor.new(mock_function_outputs: mock_function_outputs)
          FunctionInputBuilder.new(executor: executor)
        end

        # Build an assistant message representing the tool_use response
        #
        # @param response [NormalizedLlmResponse] the API response with tool_calls
        # @return [Hash] assistant message with tool_use content
        def build_assistant_tool_use_message(response)
          content = []

          # Add text if present
          content << { type: "text", text: response[:text] } if response[:text].present?

          # Add tool_use blocks
          response[:tool_calls].each do |tc|
            content << {
              type: "tool_use",
              id: tc[:id],
              name: tc[:function_name],
              input: normalize_arguments(tc[:arguments])
            }
          end

          { role: "assistant", content: content }
        end

        # Normalize arguments to Hash format
        #
        # @param arguments [Hash, String] the arguments
        # @return [Hash] parsed arguments
        def normalize_arguments(arguments)
          return arguments if arguments.is_a?(Hash)
          return {} if arguments.blank?

          JSON.parse(arguments)
        rescue JSON::ParserError
          { raw: arguments }
        end

        # Call the Messages API with updated conversation history
        #
        # @param history [Array<Hash>] the full conversation history
        # @param system_prompt [String, nil] the system prompt
        # @return [NormalizedLlmResponse] API response
        def call_api_with_history(history, system_prompt)
          return mock_response unless @use_real_llm

          AnthropicMessagesService.call(
            model: @model,
            messages: history,
            system: system_prompt,
            tools: @tools.map(&:to_sym),
            tool_config: @tool_config,
            temperature: @temperature
          )
        end

        # Generate a mock response
        #
        # @return [NormalizedLlmResponse] mock API response
        def mock_response
          NormalizedLlmResponse.new(
            text: "Mock response after function call",
            usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
            model: @model,
            tool_calls: [],
            file_search_results: [],
            web_search_results: [],
            code_interpreter_results: [],
            api_metadata: { message_id: "msg_mock_#{SecureRandom.hex(8)}" },
            raw_response: {}
          )
        end

        # Log received function calls for debugging
        #
        # @param tool_calls [Array<Hash>] the tool calls received
        # @param iteration [Integer] current iteration number
        # @param turn [Integer] current turn number
        def log_function_calls_received(tool_calls, iteration, turn)
          Rails.logger.debug do
            function_names = tool_calls.map { |tc| tc[:function_name] }.join(", ")
            "[Anthropic::FunctionCallHandler] Turn #{turn}, Iteration #{iteration}: " \
              "Received #{tool_calls.size} function call(s): #{function_names}"
          end
        end

        # Log the continuation input being sent to the API
        #
        # @param tool_result_message [Hash] the tool result message
        # @param iteration [Integer] current iteration
        def log_continuation_input(tool_result_message, iteration)
          Rails.logger.debug do
            tool_count = tool_result_message[:content]&.size || 0
            "[Anthropic::FunctionCallHandler] Iteration #{iteration}: " \
              "Sending tool_result message with #{tool_count} result(s)"
          end
        end

        # Log warning if iteration limit was reached
        #
        # @param iteration_count [Integer] number of iterations
        # @param response [NormalizedLlmResponse] final response
        # @param turn [Integer] current turn
        def log_iteration_limit_warning(iteration_count, response, turn)
          return unless iteration_count >= MAX_ITERATIONS && response[:tool_calls].present?

          Rails.logger.warn(
            "[Anthropic::FunctionCallHandler] Iteration limit (#{MAX_ITERATIONS}) reached for turn #{turn}. " \
            "Model may be stuck in a function calling loop."
          )
        end
      end
    end
  end
end
