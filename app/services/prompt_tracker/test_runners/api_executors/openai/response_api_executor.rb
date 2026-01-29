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
          # Maximum number of function call iterations per turn to prevent infinite loops.
          # This safeguard ensures that if a model keeps returning function calls,
          # the execution will eventually stop to prevent runaway costs and hanging jobs.
          MAX_FUNCTION_CALL_ITERATIONS = 10

          # Execute the test
          #
          # @param params [Hash] execution parameters
          # @return [Hash] output_data with standardized format
          def execute(params)
            messages = []
            @previous_response_id = nil
            @all_responses = []  # Track all raw responses for tool result extraction
            start_time = Time.current
            messages = execute_conversation(params)

            response_time_ms = ((Time.current - start_time) * 1000).to_i

            build_output_data(
              messages: messages,
              params: params,
              response_time_ms: response_time_ms,
              tokens: calculate_tokens(messages),
              previous_response_id: @previous_response_id,
              tools_used: tools.map(&:to_s),
              web_search_results: extract_all_web_search_results,
              code_interpreter_results: extract_all_code_interpreter_results,
              file_search_results: extract_all_file_search_results
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

              @previous_response_id = response[:response_id]
              # Track ALL responses from this turn (including intermediate function call responses)
              @all_responses.concat(all_responses)

              messages << {
                "role" => "assistant",
                "content" => response[:text],
                "turn" => turn,
                "response_id" => response[:response_id],
                "usage" => aggregated_usage,  # Use aggregated usage from ALL API calls in this turn
                "tool_calls" => all_tool_calls  # Include ALL tool calls from this turn
              }
            end

            messages
          end

          # Call the OpenAI Response API and handle function calls
          #
          # The Response API may return function calls that need to be executed.
          # This method handles the function call loop:
          # 1. Send user message
          # 2. If response contains function calls, execute them and send results back
          # 3. Repeat until we get a text response
          #
          # The loop is protected by MAX_FUNCTION_CALL_ITERATIONS to prevent infinite loops
          # if the model keeps returning function calls.
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
            all_tool_calls = []
            all_responses = []

            # First call with user message
            response = call_response_api(user_prompt: user_prompt, system_prompt: system_prompt)
            all_responses << response

            # Handle function calls in a loop with max iterations safeguard
            response = process_function_call_loop(response, all_tool_calls, all_responses, turn)

            # Aggregate usage from all API calls in this turn
            aggregated_usage = aggregate_usage_from_responses(all_responses)

            {
              final_response: response,
              all_tool_calls: all_tool_calls,
              aggregated_usage: aggregated_usage,
              all_responses: all_responses
            }
          end

          # Process the function call loop until we get a final text response
          #
          # @param response [Hash] the initial API response
          # @param all_tool_calls [Array<Hash>] accumulator for all tool calls
          # @param all_responses [Array<Hash>] accumulator for all API responses
          # @param turn [Integer] current turn number
          # @return [Hash] the final API response (with text, not function calls)
          def process_function_call_loop(response, all_tool_calls, all_responses, turn)
            iteration_count = 0

            while response[:tool_calls].present? && iteration_count < MAX_FUNCTION_CALL_ITERATIONS
              iteration_count += 1

              # Collect all tool calls for this turn
              all_tool_calls.concat(response[:tool_calls])

              # Update previous_response_id so the next call can continue the conversation
              @previous_response_id = response[:response_id]

              # Execute all function calls and collect outputs
              function_outputs = build_function_outputs(response[:tool_calls])

              # Send function outputs back to the API
              response = call_response_api_with_function_outputs(function_outputs)
              all_responses << response
            end

            # Log warning if we hit the iteration limit
            log_iteration_limit_warning(iteration_count, response, turn)

            response
          end

          # Build function call outputs from tool calls
          #
          # @param tool_calls [Array<Hash>] the tool calls to execute
          # @return [Array<Hash>] function call outputs
          def build_function_outputs(tool_calls)
            tool_calls.map do |tool_call|
              {
                type: "function_call_output",
                call_id: tool_call[:id],  # The normalizer returns :id (from call_id)
                output: execute_function_call(tool_call)
              }
            end
          end

          # Aggregate token usage from multiple API responses
          #
          # @param responses [Array<Hash>] array of API responses with usage data
          # @return [Hash] aggregated usage with prompt_tokens, completion_tokens, total_tokens
          def aggregate_usage_from_responses(responses)
            {
              prompt_tokens: responses.sum { |r| r.dig(:usage, :prompt_tokens) || 0 },
              completion_tokens: responses.sum { |r| r.dig(:usage, :completion_tokens) || 0 },
              total_tokens: responses.sum { |r| r.dig(:usage, :total_tokens) || 0 }
            }
          end

          # Log a warning if the function call iteration limit was reached
          #
          # @param iteration_count [Integer] number of iterations performed
          # @param response [Hash] the final response
          # @param turn [Integer] current turn number
          def log_iteration_limit_warning(iteration_count, response, turn)
            return unless iteration_count >= MAX_FUNCTION_CALL_ITERATIONS && response[:tool_calls].present?

            Rails.logger.warn(
              "Function call iteration limit (#{MAX_FUNCTION_CALL_ITERATIONS}) reached for turn #{turn}. " \
              "Model may be stuck in a function calling loop."
            )
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

          # Call the Response API with function call outputs
          #
          # @param function_outputs [Array<Hash>] array of function call outputs
          # @return [Hash] API response
          def call_response_api_with_function_outputs(function_outputs)
            if use_real_llm
              OpenaiResponseService.call_with_context(
                model: model,
                user_prompt: function_outputs,  # Send function outputs as input
                previous_response_id: @previous_response_id,
                tools: tools.map(&:to_sym),
                tool_config: tool_config
              )
            else
              mock_response_api_response
            end
          end

          # Execute a function call (mock implementation for testing)
          #
          # @param tool_call [Hash] the function call details (normalized format)
          #   - :id [String] the call_id
          #   - :function_name [String] the function name
          #   - :arguments [Hash] parsed arguments
          # @return [String] function execution result (JSON string)
          def execute_function_call(tool_call)
            # For testing purposes, return a mock result
            # In a real implementation, this would call the actual function
            function_name = tool_call[:function_name]
            arguments = tool_call[:arguments]

            # Return a JSON string as the function output
            # The Response API expects function outputs to be strings
            {
              success: true,
              message: "Mock result for #{function_name}",
              data: arguments
            }.to_json
          end

          # Call the real OpenAI Response API
          def call_real_response_api(user_prompt:, system_prompt: nil)
            if @previous_response_id
            OpenaiResponseService.call_with_context(
                model: model,
                user_prompt: user_prompt,
                previous_response_id: @previous_response_id,
                tools: tools.map(&:to_sym),
                tool_config: tool_config
              )
            else
              OpenaiResponseService.call(
                model: model,
                user_prompt: user_prompt,
                system_prompt: system_prompt,
                tools: tools.map(&:to_sym),
                tool_config: tool_config,
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
              web_search_results: [],
              code_interpreter_results: [],
              file_search_results: [],
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

          # Extract all web search results from all responses in the conversation
          #
          # @return [Array<Hash>] aggregated web search results
          def extract_all_web_search_results
            @all_responses.flat_map { |r| r[:web_search_results] || [] }
          end

          # Extract all code interpreter results from all responses in the conversation
          #
          # @return [Array<Hash>] aggregated code interpreter results
          def extract_all_code_interpreter_results
            @all_responses.flat_map { |r| r[:code_interpreter_results] || [] }
          end

          # Extract all file search results from all responses in the conversation
          #
          # @return [Array<Hash>] aggregated file search results
          def extract_all_file_search_results
            @all_responses.flat_map { |r| r[:file_search_results] || [] }
          end
        end
      end
    end
  end
end
