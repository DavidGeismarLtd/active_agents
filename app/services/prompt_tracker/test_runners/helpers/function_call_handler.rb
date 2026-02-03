# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Helpers
      # Handles function call loops for OpenAI Response API.
      #
      # The Response API may return function calls that need to be executed
      # and sent back before getting a final text response. This class manages
      # that iterative loop with safeguards against infinite loops.
      #
      # @example Handle function calls
      #   handler = FunctionCallHandler.new(
      #     model: "gpt-4o",
      #     tools: [:web_search, :functions],
      #     tool_config: { "functions" => [...] },
      #     use_real_llm: true
      #   )
      #   result = handler.process_with_function_handling(
      #     initial_response: response,
      #     previous_response_id: "resp_123"
      #   )
      #   # => { final_response: {...}, all_tool_calls: [...], all_responses: [...] }
      #
      class FunctionCallHandler
        # Maximum iterations to prevent infinite loops
        MAX_ITERATIONS = 10

        # @param model [String] the model name
        # @param tools [Array] enabled tools
        # @param tool_config [Hash] tool configuration
        # @param use_real_llm [Boolean] whether to use real LLM
        # @param mock_function_outputs [Hash] custom mock responses per function name
        def initialize(model:, tools:, tool_config:, use_real_llm:, mock_function_outputs: nil)
          @model = model
          @tools = tools
          @tool_config = tool_config
          @use_real_llm = use_real_llm
          @mock_function_outputs = mock_function_outputs
        end

        # Process an API response and handle any function calls
        #
        # @param initial_response [Hash] the initial API response
        # @param previous_response_id [String] the response ID to continue from
        # @param turn [Integer] current turn number (for logging)
        # @return [Hash] result with :final_response, :all_tool_calls, :all_responses
        def process_with_function_handling(initial_response:, previous_response_id:, turn: 1)
          all_tool_calls = []
          all_responses = [ initial_response ]
          response = initial_response
          iteration_count = 0

          # Loop while response contains function calls and we haven't hit the limit
          while response[:tool_calls].present? && iteration_count < MAX_ITERATIONS
            iteration_count += 1

            # Collect tool calls
            all_tool_calls.concat(response[:tool_calls])

            # Update previous_response_id for next call
            previous_response_id = response[:response_id]

            # Execute function calls and get outputs
            function_outputs = build_function_outputs(response[:tool_calls])

            # Call API with function outputs
            response = call_api_with_function_outputs(function_outputs, previous_response_id)
            all_responses << response
          end

          # If we hit the iteration limit and there are still pending tool calls,
          # add them to all_tool_calls so callers can see what was pending
          if iteration_count >= MAX_ITERATIONS && response[:tool_calls].present?
            all_tool_calls.concat(response[:tool_calls])
          end

          # Log warning if we hit the iteration limit
          log_iteration_limit_warning(iteration_count, response, turn)

          {
            final_response: response,
            all_tool_calls: all_tool_calls,
            all_responses: all_responses
          }
        end

        private

        # Build function call outputs from tool calls
        #
        # @param tool_calls [Array<Hash>] the tool calls to execute
        # @return [Array<Hash>] function call outputs
        def build_function_outputs(tool_calls)
          tool_calls.map do |tool_call|
            {
              type: "function_call_output",
              call_id: tool_call[:id],
              output: execute_function_call(tool_call)
            }
          end
        end

        # Execute a function call (mock implementation)
        #
        # @param tool_call [Hash] the function call details
        # @return [String] function execution result (JSON string)
        def execute_function_call(tool_call)
          function_name = tool_call[:function_name]
          arguments = tool_call[:arguments]

          # Check if custom mock is configured for this function
          custom_mock = @mock_function_outputs&.dig(function_name)

          if custom_mock
            # Use custom mock response (already a JSON string)
            custom_mock
          else
            # Fall back to generic mock
            {
              success: true,
              message: "Mock result for #{function_name}",
              data: arguments
            }.to_json
          end
        end

        # Call the Response API with function outputs
        #
        # @param function_outputs [Array<Hash>] function call outputs
        # @param previous_response_id [String] the response ID to continue from
        # @return [Hash] API response
        def call_api_with_function_outputs(function_outputs, previous_response_id)
          return mock_response unless @use_real_llm

          OpenaiResponseService.call_with_context(
            model: @model,
            user_prompt: function_outputs,
            previous_response_id: previous_response_id,
            tools: @tools.map(&:to_sym),
            tool_config: @tool_config
          )
        end

        # Generate a mock response
        #
        # @return [Hash] mock API response
        def mock_response
          {
            text: "Mock response after function call",
            response_id: "resp_mock_#{SecureRandom.hex(8)}",
            usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
            model: @model,
            tool_calls: [],
            web_search_results: [],
            code_interpreter_results: [],
            file_search_results: [],
            raw: {}
          }
        end

        # Log warning if iteration limit was reached
        #
        # @param iteration_count [Integer] number of iterations
        # @param response [Hash] final response
        # @param turn [Integer] current turn
        def log_iteration_limit_warning(iteration_count, response, turn)
          return unless iteration_count >= MAX_ITERATIONS && response[:tool_calls].present?

          Rails.logger.warn(
            "Function call iteration limit (#{MAX_ITERATIONS}) reached for turn #{turn}. " \
            "Model may be stuck in a function calling loop."
          )
        end
      end
    end
  end
end
