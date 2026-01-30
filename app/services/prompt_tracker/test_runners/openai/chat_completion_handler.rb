# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      # Handler for OpenAI Chat Completion API and compatible APIs.
      #
      # This handler executes both single-turn and conversational tests using
      # the chat completions interface via LlmClientService.
      #
      # While namespaced under Openai, this handler works with any provider
      # that follows the chat completion pattern (OpenAI, Anthropic, Google, etc.)
      # because it delegates to LlmClientService which handles provider-specific details.
      #
      # For conversational mode, it simulates multi-turn conversations by
      # generating user messages via an interlocutor LLM.
      #
      # @example Single-turn execution
      #   handler = ChatCompletionHandler.new(model_config: config, use_real_llm: true)
      #   output_data = handler.execute(
      #     system_prompt: "You are helpful.",
      #     max_turns: 1,
      #     first_user_message: "Hello"
      #   )
      #
      # @example Conversational execution
      #   handler = ChatCompletionHandler.new(model_config: config, use_real_llm: true)
      #   output_data = handler.execute(
      #     system_prompt: "You are a doctor.",
      #     max_turns: 5,
      #     interlocutor_prompt: "You are a patient with headache.",
      #     first_user_message: "Hello doctor"
      #   )
      #
      class ChatCompletionHandler < ConversationTestHandler
        # Execute the test
        #
        # @param params [Hash] execution parameters
        # @return [Hash] output_data with standardized format
        def execute(params)
          messages = []
          start_time = Time.current

          messages = execute_conversation(params)

          response_time_ms = ((Time.current - start_time) * 1000).to_i

          build_output_data(
            messages: messages,
            params: params,
            response_time_ms: response_time_ms,
            tokens: token_aggregator.aggregate_from_messages(messages)
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
          conversation_history = []
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
                conversation_history: conversation_history,
                turn: turn
              )
            end

            break if user_message.nil?

            messages << { "role" => "user", "content" => user_message, "turn" => turn }
            conversation_history << { role: "user", content: user_message }

            # Get assistant response
            response = call_llm_with_history(
              conversation_history: conversation_history,
              system_prompt: params[:system_prompt]
            )

            messages << {
              "role" => "assistant",
              "content" => response[:text],
              "turn" => turn,
              "usage" => response[:usage]
            }
            conversation_history << { role: "assistant", content: response[:text] }
          end

          messages
        end

        # Call LLM with conversation history
        #
        # @param conversation_history [Array<Hash>] previous messages
        # @param system_prompt [String] the system prompt
        # @return [Hash] LLM response
        def call_llm_with_history(conversation_history:, system_prompt:)
          if use_real_llm
            # Build the last user message
            last_user_message = conversation_history.last[:content]
            previous_messages = conversation_history[0..-2]  # All but last (which is the prompt)

            call_params = {
              provider: provider,
              api: api,
              model: model,
              prompt: last_user_message,
              system_prompt: system_prompt,
              temperature: temperature,
              tools: tools.presence
            }

            # Only include messages if there are previous messages
            call_params[:messages] = previous_messages if previous_messages.any?
            LlmClientService.call(**call_params)
          else
            turn = (conversation_history.count { |m| m[:role] == "user" })
            mock_llm_response(turn: turn)
          end
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
