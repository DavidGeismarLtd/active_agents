# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      module Responses
        # Simulated conversation runner for OpenAI Response API.
        #
        # This runner executes both single-turn and conversational tests using
        # the OpenAI Response API, which supports stateful conversations via
        # previous_response_id.
        #
        # Response API provides:
        # - Stateful multi-turn conversations
        # - Built-in tools (web_search, file_search, code_interpreter)
        # - Function calling
        #
        # @example Single-turn execution
        #   runner = SimulatedConversationRunner.new(model_config: config, use_real_llm: true)
        #   output_data = runner.execute(
        #     mode: :single_turn,
        #     system_prompt: "You are helpful.",
        #     first_user_message: "Hello"
        #   )
        #
        # @example Conversational execution
        #   runner = SimulatedConversationRunner.new(model_config: config, use_real_llm: true)
        #   output_data = runner.execute(
        #     mode: :conversational,
        #     system_prompt: "You are a doctor.",
        #     interlocutor_prompt: "You are a patient with headache.",
        #     max_turns: 5
        #   )
        #
        class SimulatedConversationRunner < TestRunners::SimulatedConversationRunner
        # Execute the test
        #
        # @param params [Hash] execution parameters
        # @return [Hash] output_data with standardized format
        def execute(params)
          messages = []
          @previous_response_id = nil
          @all_responses = []  # Track all raw responses for tool result extraction
          @tool_result_extractor = nil  # Clear memoized extractor when resetting responses
          @mock_function_outputs = params[:mock_function_outputs]  # Store custom mock configurations
          @function_call_handler = nil  # Clear memoized handler to pick up new mock_function_outputs
          start_time = Time.current
          messages = execute_conversation(params)

          response_time_ms = ((Time.current - start_time) * 1000).to_i

          tool_results = tool_result_extractor.all_results

          build_output_data(
            messages: messages,
            params: params,
            response_time_ms: response_time_ms,
            tokens: token_aggregator.aggregate_from_messages(messages),
            previous_response_id: @previous_response_id,
            tools_used: tools.map(&:to_s),
            **tool_results
          )
        end

        private

        # Execute a conversation (single-turn or multi-turn)
        #
        # Single-turn execution is just conversational execution with max_turns = 1.
        # Both modes start with the same first message (rendered user_prompt template).
        #
        # @param params [Hash] execution parameters
        # @return [Array<Hash>] array of messages
        def execute_conversation(params)
          messages = []
          max_turns = params[:max_turns] || 1
          (1..max_turns).each do |turn|
            # Generate user message
            user_message = if turn == 1
              # First turn: use the rendered user_prompt template
              params[:first_user_message]
            else
              # Subsequent turns: generate using interlocutor simulation
              interlocutor_simulator.generate_next_message(
                interlocutor_prompt: params[:interlocutor_prompt],
                conversation_history: messages,
                turn: turn
              )
            end

            break if user_message.nil?

            messages << ConversationMessage.new(
              role: "user",
              content: user_message,
              turn: turn
            ).to_h

            # Call Response API and handle function calls
            # The API may return function calls that need to be executed and sent back
            # before we get the final text response
            result = call_response_api_with_function_handling(
              user_prompt: user_message,
              system_prompt: turn == 1 ? params[:system_prompt] : nil,
              turn: turn
            )

            response = result[:final_response]
            all_tool_calls = result[:all_tool_calls]
            aggregated_usage = result[:aggregated_usage]
            all_responses = result[:all_responses]

            # Store response_id for multi-turn conversations (use convenience method)
            @previous_response_id = response.response_id
            # Track ALL responses from this turn (including intermediate function call responses)
            @all_responses.concat(all_responses)

            # Build message with standardized structure matching NormalizedResponse
            messages << ConversationMessage.new(
              role: "assistant",
              content: response[:text],
              turn: turn,
              usage: aggregated_usage,  # Use aggregated usage from ALL API calls in this turn
              tool_calls: all_tool_calls,  # Include ALL tool calls from this turn
              file_search_results: response[:file_search_results],
              web_search_results: response[:web_search_results],
              code_interpreter_results: response[:code_interpreter_results],
              api_metadata: response[:api_metadata]
            ).to_h
          end

          messages
        end

        # Call the OpenAI Response API and handle function calls
        #
        # The Response API may return function calls that need to be executed.
        # This method handles the function call loop using FunctionCallHandler.
        #
        # @param user_prompt [String] the user message
        # @param system_prompt [String, nil] the system prompt (only for first turn)
        # @param turn [Integer] current turn number
        # @return [Hash] result with:
        #   - :final_response [Hash] the final API response (with text, not function calls)
        #   - :all_tool_calls [Array<Hash>] all tool calls that were made during this turn
        #   - :aggregated_usage [Hash] aggregated token usage from ALL API calls in this turn
        #   - :all_responses [Array<Hash>] all API responses from this turn (including intermediate ones)
        def call_response_api_with_function_handling(user_prompt:, system_prompt: nil, turn:)
          # First call with user message
          initial_response = call_response_api(user_prompt: user_prompt, system_prompt: system_prompt)

          # Handle function calls using FunctionCallHandler
          result = function_call_handler.process_with_function_handling(
            initial_response: initial_response,
            previous_response_id: @previous_response_id,
            turn: turn
          )

          # Update previous_response_id from the final response
          @previous_response_id = result[:final_response][:response_id]

          # Aggregate usage from all API calls in this turn
          aggregated_usage = token_aggregator.aggregate_from_responses(result[:all_responses])

          {
            final_response: result[:final_response],
            all_tool_calls: result[:all_tool_calls],
            aggregated_usage: aggregated_usage,
            all_responses: result[:all_responses]
          }
        end

        # Call the OpenAI Response API
        #
        # @param user_prompt [String] the user message
        # @param system_prompt [String, nil] the system prompt (only for first turn)
        # @return [Hash] API response
        def call_response_api(user_prompt:, system_prompt: nil)
          if use_real_llm
            call_real_response_api(user_prompt: user_prompt, system_prompt: system_prompt)
          else
            mock_response_api_response
          end
        end

        # Call the real OpenAI Response API
        def call_real_response_api(user_prompt:, system_prompt: nil)
          if @previous_response_id
            OpenaiResponseService.call_with_context(
              model: model,
              input: user_prompt,
              previous_response_id: @previous_response_id,
              tools: tools.map(&:to_sym),
              tool_config: tool_config
            )
          else
            OpenaiResponseService.call(
              model: model,
              input: user_prompt,
              instructions: system_prompt,
              tools: tools.map(&:to_sym),
              tool_config: tool_config,
              temperature: temperature
            )
          end
        end

        # Generate a mock Response API response
        #
        # @return [PromptTracker::NormalizedLlmResponse] mock response
        def mock_response_api_response
          @mock_response_counter ||= 0
          @mock_response_counter += 1

          PromptTracker::NormalizedLlmResponse.new(
            text: "Mock Response API response for testing (#{@mock_response_counter})",
            usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
            model: model,
            tool_calls: [],
            file_search_results: [],
            web_search_results: [],
            code_interpreter_results: [],
            api_metadata: { response_id: "resp_mock_#{SecureRandom.hex(8)}" },
            raw_response: {}
          )
        end

        # Get the interlocutor simulator instance
        #
        # @return [Helpers::InterlocutorSimulator]
        def interlocutor_simulator
          @interlocutor_simulator ||= Helpers::InterlocutorSimulator.new(use_real_llm: use_real_llm)
        end

        # Get the token aggregator instance
        #
        # @return [Helpers::TokenAggregator]
        def token_aggregator
          @token_aggregator ||= Helpers::TokenAggregator.new
        end

        # Get the function call handler instance
        #
        # @return [PromptTracker::Openai::Responses::FunctionCallHandler]
        def function_call_handler
          @function_call_handler ||= PromptTracker::Openai::Responses::FunctionCallHandler.new(
            model: model,
            tools: tools,
            tool_config: tool_config,
            use_real_llm: use_real_llm,
            mock_function_outputs: @mock_function_outputs
          )
        end

        # Get the tool result extractor instance
        #
        # @return [Helpers::ToolResultExtractor]
        def tool_result_extractor
          @tool_result_extractor ||= Helpers::ToolResultExtractor.new(@all_responses)
        end
        end
      end
    end
  end
end
