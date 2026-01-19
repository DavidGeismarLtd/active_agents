# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module ApiExecutors
      # Executor for standard Chat Completion APIs (OpenAI, Anthropic, Google, etc.).
      #
      # This executor handles both single-turn and conversational tests using
      # the chat completions interface via LlmClientService.
      #
      # For conversational mode, it simulates multi-turn conversations by
      # generating user messages via an interlocutor LLM.
      #
      # @example Single-turn execution
      #   executor = CompletionApiExecutor.new(model_config: config, use_real_llm: true)
      #   output_data = executor.execute(
      #     mode: :single_turn,
      #     system_prompt: "You are helpful.",
      #     first_user_message: "Hello"
      #   )
      #
      # @example Conversational execution
      #   executor = CompletionApiExecutor.new(model_config: config, use_real_llm: true)
      #   output_data = executor.execute(
      #     mode: :conversational,
      #     system_prompt: "You are a doctor.",
      #     interlocutor_prompt: "You are a patient with headache.",
      #     max_turns: 5
      #   )
      #
      class CompletionApiExecutor < Base
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
            tokens: calculate_tokens(messages)
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
              generate_next_user_message(params[:interlocutor_prompt], conversation_history, turn)
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

        # Call LLM for a single message
        #
        # @param prompt [String] the user prompt
        # @param system_prompt [String] the system prompt
        # @return [Hash] LLM response
        def call_llm(prompt:, system_prompt:)
          if use_real_llm
            LlmClientService.call(
              provider: provider,
              api: api,
              model: model,
              prompt: prompt,
              system_prompt: system_prompt,
              temperature: temperature,
              tools: tools.presence
            )
          else
            mock_llm_response(turn: 1)
          end
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

        # Generate next user message based on conversation history
        #
        # @param interlocutor_prompt [String] the simulation prompt
        # @param conversation_history [Array<Hash>] conversation so far
        # @param turn [Integer] current turn number
        # @return [String, nil] generated message or nil to end conversation
        def generate_next_user_message(interlocutor_prompt, conversation_history, turn)
          return "I have another question." unless use_real_llm

          history_text = conversation_history.map do |msg|
            "#{msg[:role].capitalize}: #{msg[:content]}"
          end.join("\n\n")

          prompt = <<~PROMPT
            You are simulating a user in a conversation. Based on the following context and conversation history, generate your NEXT response.

            Context: #{interlocutor_prompt}

            Conversation so far:
            #{history_text}

            If the conversation has naturally concluded, respond with exactly: [END_CONVERSATION]
            Otherwise, generate ONLY the user's next message, nothing else.
          PROMPT

          response = LlmClientService.call(
            provider: "openai",
            api: "chat_completions",
            model: "gpt-4o-mini",
            prompt: prompt,
            temperature: 0.7
          )

          text = response[:text].strip
          return nil if text.include?("[END_CONVERSATION]")
          text
        end

        # Calculate aggregate token usage from messages
        #
        # @param messages [Array<Hash>] array of messages with usage info
        # @return [Hash, nil] aggregated token counts
        def calculate_tokens(messages)
          assistant_messages = messages.select { |m| m["role"] == "assistant" && m["usage"] }
          return nil if assistant_messages.empty?

          {
            "prompt_tokens" => assistant_messages.sum { |m| m.dig("usage", :prompt_tokens) || 0 },
            "completion_tokens" => assistant_messages.sum { |m| m.dig("usage", :completion_tokens) || 0 },
            "total_tokens" => assistant_messages.sum { |m| m.dig("usage", :total_tokens) || 0 }
          }
        end
      end
    end
  end
end
