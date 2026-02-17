# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Anthropic
      module Messages
        # Simulated conversation runner for Anthropic Messages API.
        #
        # This runner executes both single-turn and conversational tests using
        # the Anthropic Messages API. Unlike OpenAI Responses API, Anthropic is
        # stateless - we must manage the full conversation history ourselves.
        #
        # Key differences from OpenAI:
        # - No previous_response_id - full message history must be sent each turn
        # - System prompt is a separate parameter (not in messages array)
        # - max_tokens is REQUIRED (we use DEFAULT_MAX_TOKENS)
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
            @conversation_history = []  # Track full conversation for stateless API
            @all_responses = []
            @mock_function_outputs = params[:mock_function_outputs]  # Store custom mock configurations
            @function_call_handler = nil  # Clear memoized handler to pick up new mock_function_outputs
            start_time = Time.current

            messages = execute_conversation(params)

            response_time_ms = ((Time.current - start_time) * 1000).to_i

            build_output_data(
              messages: messages,
              params: params,
              response_time_ms: response_time_ms,
              tokens: token_aggregator.aggregate_from_messages(messages),
              tools_used: tools.map(&:to_s)
            )
          end

          private

          # Execute a conversation (single-turn or multi-turn)
          #
          # @param params [Hash] execution parameters
          # @return [Array<Hash>] array of messages
          def execute_conversation(params)
            messages = []
            max_turns = params[:max_turns] || 1

            (1..max_turns).each do |turn|
              # Generate user message
              user_message = if turn == 1
                params[:first_user_message]
              else
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
              @conversation_history << { role: "user", content: user_message }

              # Call Messages API with function handling
              result = call_messages_api_with_function_handling(
                system_prompt: params[:system_prompt],
                turn: turn
              )

              @all_responses.concat(result[:all_responses])

              # Update conversation history (FunctionCallHandler already appended tool messages)
              @conversation_history = result[:updated_history]
              # Add final assistant response to conversation history
              @conversation_history << { role: "assistant", content: result[:final_response][:text] }

              # Build message with standardized structure
              messages << ConversationMessage.new(
                role: "assistant",
                content: result[:final_response][:text],
                turn: turn,
                usage: result[:aggregated_usage],
                tool_calls: result[:all_tool_calls],
                web_search_results: result[:final_response][:web_search_results],
                api_metadata: result[:final_response][:api_metadata]
              ).to_h
            end

            messages
          end

          # Call the Anthropic Messages API and handle function calls
          #
          # @param system_prompt [String] the system prompt
          # @param turn [Integer] current turn number
          # @return [Hash] result with:
          #   - :final_response [NormalizedLlmResponse] the final API response
          #   - :all_tool_calls [Array<Hash>] all tool calls made during this turn
          #   - :aggregated_usage [Hash] aggregated token usage from ALL API calls
          #   - :all_responses [Array<NormalizedLlmResponse>] all responses
          #   - :updated_history [Array<Hash>] updated conversation history
          def call_messages_api_with_function_handling(system_prompt:, turn:)
            # First call
            initial_response = call_messages_api(system_prompt: system_prompt)

            # Handle function calls using FunctionCallHandler
            result = function_call_handler.process_with_function_handling(
              initial_response: initial_response,
              conversation_history: @conversation_history,
              system_prompt: system_prompt,
              turn: turn
            )

            # Aggregate usage from all API calls in this turn
            aggregated_usage = token_aggregator.aggregate_from_responses(result[:all_responses])

            {
              final_response: result[:final_response],
              all_tool_calls: result[:all_tool_calls],
              aggregated_usage: aggregated_usage,
              all_responses: result[:all_responses],
              updated_history: result[:updated_history]
            }
          end

          # Call the Anthropic Messages API
          #
          # @param system_prompt [String] the system prompt
          # @return [NormalizedLlmResponse] API response
          def call_messages_api(system_prompt:)
            if use_real_llm
              call_real_messages_api(system_prompt: system_prompt)
            else
              mock_messages_api_response
            end
          end

          # Call the real Anthropic Messages API
          def call_real_messages_api(system_prompt:)
            AnthropicMessagesService.call(
              model: model,
              messages: @conversation_history,
              system: system_prompt,
              tools: tools.map(&:to_sym),
              tool_config: tool_config,
              temperature: temperature
            )
          end

          # Generate a mock Messages API response
          #
          # @return [NormalizedLlmResponse] mock response
          def mock_messages_api_response
            PromptTracker::NormalizedLlmResponse.new(
              text: "Mock Anthropic Messages API response",
              usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
              model: model,
              tool_calls: [],
              file_search_results: [],
              web_search_results: [],
              code_interpreter_results: [],
              api_metadata: { message_id: "msg_mock_#{SecureRandom.hex(8)}" },
              raw_response: {}
            )
          end

          # Get the function call handler instance
          #
          # @return [PromptTracker::Anthropic::Messages::FunctionCallHandler]
          def function_call_handler
            @function_call_handler ||= PromptTracker::Anthropic::Messages::FunctionCallHandler.new(
              model: model,
              tools: tools,
              tool_config: tool_config,
              use_real_llm: use_real_llm,
              mock_function_outputs: @mock_function_outputs,
              temperature: temperature
            )
          end

          # Get the interlocutor simulator instance
          def interlocutor_simulator
            @interlocutor_simulator ||= Helpers::InterlocutorSimulator.new(use_real_llm: use_real_llm)
          end

          # Get the token aggregator instance
          def token_aggregator
            @token_aggregator ||= Helpers::TokenAggregator.new
          end
        end
      end
    end
  end
end
