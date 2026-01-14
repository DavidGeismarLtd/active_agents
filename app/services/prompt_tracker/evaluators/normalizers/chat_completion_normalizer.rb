# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Normalizers
      # Normalizer for OpenAI Chat Completion API responses.
      #
      # Transforms Chat Completion API responses into the standard format
      # expected by evaluators.
      #
      # @example Normalize a response
      #   normalizer = ChatCompletionNormalizer.new
      #   normalized = normalizer.normalize_single_response(response)
      #
      class ChatCompletionNormalizer < BaseNormalizer
        # Normalize a single response from Chat Completion API
        #
        # @param raw_response [Hash, String] the raw response
        # @return [Hash] normalized single response format
        def normalize_single_response(raw_response)
          case raw_response
          when String
            { text: raw_response, tool_calls: [], metadata: {} }
          when Hash
            {
              text: extract_text(raw_response),
              tool_calls: extract_tool_calls(raw_response),
              metadata: extract_metadata(raw_response)
            }
          else
            { text: raw_response.to_s, tool_calls: [], metadata: {} }
          end
        end

        # Normalize a conversation from Chat Completion API
        #
        # For Chat Completion, conversations are typically maintained client-side,
        # so we normalize the messages array.
        #
        # @param raw_data [Hash] the raw conversation data
        # @return [Hash] normalized conversation format
        def normalize_conversation(raw_data)
          messages = raw_data[:messages] || raw_data["messages"] || []

          {
            messages: normalize_messages(messages),
            tool_usage: extract_tool_usage_from_messages(messages),
            file_search_results: [],  # Chat Completion doesn't have file search
            web_search_results: [],   # Chat Completion doesn't have web search
            code_interpreter_results: [],  # Chat Completion doesn't have code interpreter
            run_steps: []  # Chat Completion doesn't have run_steps
          }
        end

        private

        def extract_text(response)
          # Try various paths where text content might be
          response[:text] || response["text"] ||
            response.dig(:choices, 0, :message, :content) ||
            response.dig("choices", 0, "message", "content") ||
            response[:content] || response["content"] ||
            ""
        end

        def extract_tool_calls(response)
          tool_calls = response[:tool_calls] || response["tool_calls"] ||
            response.dig(:choices, 0, :message, :tool_calls) ||
            response.dig("choices", 0, "message", "tool_calls") || []

          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type] || "function",
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_metadata(response)
          {
            model: response[:model] || response["model"],
            finish_reason: response.dig(:choices, 0, :finish_reason) ||
                          response.dig("choices", 0, "finish_reason"),
            usage: response[:usage] || response["usage"]
          }.compact
        end

        def normalize_messages(messages)
          messages.map.with_index do |msg, index|
            {
              role: msg[:role] || msg["role"],
              content: extract_text_content(msg[:content] || msg["content"]),
              tool_calls: extract_message_tool_calls(msg),
              turn: calculate_turn(messages, index)
            }
          end
        end

        def extract_message_tool_calls(message)
          tool_calls = message[:tool_calls] || message["tool_calls"] || []
          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type] || "function",
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_tool_usage_from_messages(messages)
          messages.flat_map do |msg|
            (msg[:tool_calls] || msg["tool_calls"] || []).map do |tc|
              {
                function_name: tc.dig("function", "name") || tc.dig(:function, :name),
                call_id: tc["id"] || tc[:id],
                arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments)),
                result: nil  # Results would be in separate tool messages
              }
            end
          end
        end

        # Calculate the turn number for a message
        # A turn is defined as a user message followed by assistant response(s)
        def calculate_turn(messages, current_index)
          turn = 0
          messages.each_with_index do |msg, idx|
            break if idx > current_index
            turn += 1 if (msg[:role] || msg["role"]) == "user"
          end
          turn
        end
      end
    end
  end
end
