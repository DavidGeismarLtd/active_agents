# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      module Assistants
        # Simulated conversation runner for OpenAI Assistants API.
        #
        # This runner executes both single-turn and conversational tests using
        # the OpenAI Assistants API, which manages conversation state via threads.
        #
        # Assistants API provides:
        # - Thread-based conversation management
        # - Built-in tools (code_interpreter, file_search)
        # - Function calling
        # - Persistent conversation history
        #
        # Key difference from other APIs: The assistant's instructions (system prompt)
        # are configured on the assistant itself, not passed per-request.
        # We only send user messages to the thread.
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
            @thread_id = nil
            start_time = Time.current

            messages = execute_conversation(params)

            response_time_ms = ((Time.current - start_time) * 1000).to_i

            build_output_data(
              messages: messages,
              params: params,
              response_time_ms: response_time_ms,
              tokens: token_aggregator.aggregate_from_messages(messages),
              thread_id: @thread_id
            )
          end

          private

          # Get the assistant_id from model_config
          #
          # @return [String] the assistant ID
          def assistant_id
            model_config[:assistant_id]
          end

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

              # Call Assistants API
              response = call_assistants_api(user_message: user_message)

              # Store thread_id for subsequent turns (reuse the same thread)
              # Use convenience method since thread_id is now in api_metadata
              @thread_id ||= response.thread_id

              # Build message with standardized structure matching NormalizedResponse
              messages << ConversationMessage.new(
                role: "assistant",
                content: response[:text],
                turn: turn,
                usage: response[:usage],
                tool_calls: response[:tool_calls],
                file_search_results: response[:file_search_results],
                web_search_results: response[:web_search_results],
                code_interpreter_results: response[:code_interpreter_results],
                api_metadata: response[:api_metadata]
              ).to_h
            end

            messages
          end

          # Call the OpenAI Assistants API
          #
          # @param user_message [String] the user message
          # @return [Hash] API response
          def call_assistants_api(user_message:)
            if use_real_llm
              OpenaiAssistantService.call(
                assistant_id: assistant_id,
                user_message: user_message,
                thread_id: @thread_id
              )
            else
              mock_assistants_api_response
            end
          end

          # Generate a mock Assistants API response
          #
          # @return [NormalizedLlmResponse] mock response matching OpenaiAssistantService format
          def mock_assistants_api_response
            @mock_response_counter ||= 0
            @mock_response_counter += 1

            # Use stable thread_id for multi-turn (same thread across turns)
            @mock_thread_id ||= "thread_mock_#{SecureRandom.hex(8)}"
            mock_run_id = "run_mock_#{SecureRandom.hex(8)}"

            PromptTracker::NormalizedLlmResponse.new(
              text: "Mock Assistants API response for testing (#{@mock_response_counter})",
              usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
              model: assistant_id,
              tool_calls: [],
              file_search_results: [],
              web_search_results: [],
              code_interpreter_results: [],
              api_metadata: {
                thread_id: @mock_thread_id,
                run_id: mock_run_id,
                annotations: []
              },
              raw_response: {
                thread_id: @mock_thread_id,
                run_id: mock_run_id
              }
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
        end
      end
    end
  end
end
