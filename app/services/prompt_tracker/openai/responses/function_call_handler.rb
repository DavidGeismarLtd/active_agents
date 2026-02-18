# frozen_string_literal: true

module PromptTracker
  module Openai
    module Responses
      # Handles function call loops for OpenAI Responses API.
      #
      # The Responses API may return function calls that need to be executed
      # and sent back before getting a final text response. This class manages
      # that iterative loop with safeguards against infinite loops.
      #
      # This class delegates to:
      # - FunctionExecutor: executes individual function calls
      # - FunctionInputBuilder: builds the input array for API continuation
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
          @input_builder = build_input_builder(mock_function_outputs)
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

            tool_calls = response[:tool_calls]
            log_function_calls_received(tool_calls, iteration_count, turn)

            # Collect tool calls
            all_tool_calls.concat(tool_calls)

            # Update previous_response_id for next call
            previous_response_id = response[:response_id]

            # Build continuation input (executes functions and pairs calls with outputs)
            input_items = @input_builder.build_continuation_input(tool_calls)
            log_continuation_input(input_items, previous_response_id)

            # Call API with paired function call/output items
            response = call_api_with_function_outputs(input_items, previous_response_id)
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

        # Build the input builder with a function executor
        #
        # @param mock_function_outputs [Hash, nil] custom mock responses
        # @return [FunctionInputBuilder]
        def build_input_builder(mock_function_outputs)
          executor = FunctionExecutor.new(mock_function_outputs: mock_function_outputs)
          FunctionInputBuilder.new(executor: executor)
        end

        # Call the Response API with function call/output pairs
        #
        # @param input_items [Array<Hash>] paired function_call + function_call_output items
        # @param previous_response_id [String] the response ID to continue from
        # @return [Hash] API response
        def call_api_with_function_outputs(input_items, previous_response_id)
          return mock_response unless @use_real_llm

          LlmClients::OpenaiResponseService.call_with_context(
            model: @model,
            input: input_items,
            previous_response_id: previous_response_id,
            tools: @tools.map(&:to_sym),
            tool_config: @tool_config
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
            api_metadata: { response_id: "resp_mock_#{SecureRandom.hex(8)}" },
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
            "[FunctionCallHandler] Turn #{turn}, Iteration #{iteration}: " \
              "Received #{tool_calls.size} function call(s): #{function_names}"
          end
        end

        # Log the continuation input being sent to the API
        #
        # @param input_items [Array<Hash>] the paired input items
        # @param previous_response_id [String] the response ID
        def log_continuation_input(input_items, previous_response_id)
          Rails.logger.debug do
            "[FunctionCallHandler] Sending continuation request:\n" \
              "  previous_response_id: #{previous_response_id}\n" \
              "  input_items (#{input_items.size} items): #{format_input_items_for_log(input_items)}"
          end
        end

        # Format input items for readable logging
        #
        # @param input_items [Array<Hash>] the input items
        # @return [String] formatted string
        def format_input_items_for_log(input_items)
          input_items.map do |item|
            if item[:type] == "function_call"
              "function_call(#{item[:name]}, call_id: #{item[:call_id]})"
            else
              output_preview = item[:output].to_s.truncate(100)
              "function_call_output(call_id: #{item[:call_id]}, output: #{output_preview})"
            end
          end.join(", ")
        end

        # Log warning if iteration limit was reached
        #
        # @param iteration_count [Integer] number of iterations
        # @param response [Hash] final response
        # @param turn [Integer] current turn
        def log_iteration_limit_warning(iteration_count, response, turn)
          return unless iteration_count >= MAX_ITERATIONS && response[:tool_calls].present?

          Rails.logger.warn(
            "[FunctionCallHandler] Iteration limit (#{MAX_ITERATIONS}) reached for turn #{turn}. " \
            "Model may be stuck in a function calling loop."
          )
        end
      end
    end
  end
end
