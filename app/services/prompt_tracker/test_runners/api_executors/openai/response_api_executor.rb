# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module ApiExecutors
      module Openai
        # Executor for OpenAI Response API.
        #
        # This executor handles both single-turn and conversational tests using
        # the OpenAI Response API, which supports stateful conversations via
        # previous_response_id.
        #
        # Response API provides:
        # - Stateful multi-turn conversations
        # - Built-in tools (web_search, file_search, code_interpreter)
        # - Function calling
        #
        # @example Single-turn execution
        #   executor = ResponseApiExecutor.new(model_config: config, use_real_llm: true)
        #   output_data = executor.execute(
        #     mode: :single_turn,
        #     system_prompt: "You are helpful.",
        #     first_user_message: "Hello"
        #   )
        #
        # @example Conversational execution
        #   executor = ResponseApiExecutor.new(model_config: config, use_real_llm: true)
        #   output_data = executor.execute(
        #     mode: :conversational,
        #     system_prompt: "You are a doctor.",
        #     interlocutor_prompt: "You are a patient with headache.",
        #     max_turns: 5
        #   )
        #
        class ResponseApiExecutor < Base
          # Execute the test
          #
          # @param params [Hash] execution parameters
          # @return [Hash] output_data with standardized format
          def execute(params)
            messages = []
            @previous_response_id = nil
            start_time = Time.current

            messages = execute_conversation(params)

            response_time_ms = ((Time.current - start_time) * 1000).to_i

            build_output_data(
              messages: messages,
              params: params,
              response_time_ms: response_time_ms,
              tokens: calculate_tokens(messages),
              previous_response_id: @previous_response_id,
              tools_used: tools.map(&:to_s)
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
                generate_next_user_message(params[:interlocutor_prompt], messages, turn)
              end

              break if user_message.nil?

              messages << { "role" => "user", "content" => user_message, "turn" => turn }

              # Call Response API (uses previous_response_id for context)
              response = call_response_api(
                user_prompt: user_message,
                system_prompt: turn == 1 ? params[:system_prompt] : nil
              )

              @previous_response_id = response[:response_id]

              messages << {
                "role" => "assistant",
                "content" => response[:text],
                "turn" => turn,
                "response_id" => response[:response_id],
                "usage" => response[:usage],
                "tool_calls" => response[:tool_calls]
              }
            end

            messages
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
                user_prompt: user_prompt,
                previous_response_id: @previous_response_id,
                tools: tools.map(&:to_sym)
              )
            else
              OpenaiResponseService.call(
                model: model,
                user_prompt: user_prompt,
                system_prompt: system_prompt,
                tools: tools.map(&:to_sym),
                temperature: temperature
              )
            end
          end

          # Generate a mock Response API response
          #
          # @return [Hash] mock response
          def mock_response_api_response
            @mock_response_counter ||= 0
            @mock_response_counter += 1

            {
              text: "Mock Response API response for testing (#{@mock_response_counter})",
              response_id: "resp_mock_#{SecureRandom.hex(8)}",
              usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
              model: model,
              tool_calls: [],
              raw: {}
            }
          end

          # Generate next user message based on conversation history
          #
          # @param interlocutor_prompt [String] the simulation prompt
          # @param messages [Array<Hash>] conversation so far
          # @param turn [Integer] current turn number
          # @return [String, nil] generated message or nil to end conversation
          def generate_next_user_message(interlocutor_prompt, messages, turn)
            return "I have another question." unless use_real_llm

            history_text = messages.map do |msg|
              "#{msg['role'].capitalize}: #{msg['content']}"
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
end
