# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Normalizers
      # Normalizer for Anthropic Messages API responses.
      #
      # Transforms Anthropic API responses into the standard format
      # expected by evaluators.
      #
      # @example Normalize a response
      #   normalizer = AnthropicNormalizer.new
      #   normalized = normalizer.normalize_single_response(response)
      #
      class AnthropicNormalizer < BaseNormalizer
        # Normalize a single response from Anthropic Messages API
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

        # Normalize a conversation from Anthropic Messages API
        #
        # @param raw_data [Hash] the raw conversation data
        # @return [Hash] normalized conversation format
        def normalize_conversation(raw_data)
          messages = raw_data[:messages] || raw_data["messages"] || []

          {
            messages: normalize_messages(messages),
            tool_usage: extract_tool_usage_from_messages(messages),
            file_search_results: []  # Anthropic doesn't have built-in file search
          }
        end

        private

        def extract_text(response)
          # Anthropic uses content array with type: "text"
          content = response[:content] || response["content"]

          case content
          when Array
            content.filter_map do |item|
              item[:text] || item["text"] if (item[:type] || item["type"]) == "text"
            end.join("\n")
          when String
            content
          else
            response[:text] || response["text"] || ""
          end
        end

        def extract_tool_calls(response)
          content = response[:content] || response["content"] || []
          return [] unless content.is_a?(Array)

          content.filter_map do |item|
            next unless (item[:type] || item["type"]) == "tool_use"

            {
              id: item[:id] || item["id"],
              type: "function",
              function_name: item[:name] || item["name"],
              arguments: item[:input] || item["input"] || {}
            }
          end
        end

        def extract_metadata(response)
          {
            id: response[:id] || response["id"],
            model: response[:model] || response["model"],
            stop_reason: response[:stop_reason] || response["stop_reason"],
            usage: response[:usage] || response["usage"]
          }.compact
        end

        def normalize_messages(messages)
          messages.map.with_index do |msg, index|
            content = msg[:content] || msg["content"]
            text = case content
            when Array
                     content.filter_map do |item|
                       item[:text] || item["text"] if (item[:type] || item["type"]) == "text"
                     end.join("\n")
            when String
                     content
            else
                     ""
            end

            {
              role: msg[:role] || msg["role"],
              content: text,
              tool_calls: extract_message_tool_calls(msg),
              turn: calculate_turn(messages, index)
            }
          end
        end

        def extract_message_tool_calls(message)
          content = message[:content] || message["content"] || []
          return [] unless content.is_a?(Array)

          content.filter_map do |item|
            next unless (item[:type] || item["type"]) == "tool_use"

            {
              id: item[:id] || item["id"],
              type: "function",
              function_name: item[:name] || item["name"],
              arguments: item[:input] || item["input"] || {}
            }
          end
        end

        def extract_tool_usage_from_messages(messages)
          messages.flat_map { |msg| extract_message_tool_calls(msg) }.map do |tc|
            {
              function_name: tc[:function_name],
              call_id: tc[:id],
              arguments: tc[:arguments],
              result: nil  # Results would be in separate tool_result messages
            }
          end
        end

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
