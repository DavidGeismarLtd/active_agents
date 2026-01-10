# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Normalizers
      # Normalizer for OpenAI Response API responses.
      #
      # The Response API is OpenAI's newer stateful conversation API.
      # It maintains conversation state on the server side and returns
      # responses with a different structure than Chat Completion.
      #
      # @example Normalize a response
      #   normalizer = ResponseApiNormalizer.new
      #   normalized = normalizer.normalize_single_response(response)
      #
      class ResponseApiNormalizer < BaseNormalizer
        # Normalize a single response from Response API
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

        # Normalize a conversation from Response API
        #
        # @param raw_data [Hash] the raw conversation data
        # @return [Hash] normalized conversation format
        def normalize_conversation(raw_data)
          # Response API returns output array with items
          output = raw_data[:output] || raw_data["output"] || []
          messages = raw_data[:messages] || raw_data["messages"] || []

          # Combine output items and any messages
          all_messages = messages.presence || output_to_messages(output)

          {
            messages: normalize_messages(all_messages),
            tool_usage: extract_tool_usage(output),
            file_search_results: extract_file_search_results(output)
          }
        end

        private

        def extract_text(response)
          # Response API structure: output[].content[].text
          output = response[:output] || response["output"] || []

          # Find message items and extract text
          text_parts = output.flat_map do |item|
            next [] unless (item[:type] || item["type"]) == "message"

            content = item[:content] || item["content"] || []
            content.filter_map do |c|
              c[:text] || c["text"] if (c[:type] || c["type"]) == "output_text"
            end
          end

          text_parts.join("\n").presence || response[:text] || response["text"] || ""
        end

        def extract_tool_calls(response)
          output = response[:output] || response["output"] || []

          output.filter_map do |item|
            next unless (item[:type] || item["type"]) == "function_call"

            {
              id: item[:call_id] || item["call_id"] || item[:id] || item["id"],
              type: "function",
              function_name: item[:name] || item["name"],
              arguments: parse_arguments(item[:arguments] || item["arguments"])
            }
          end
        end

        def extract_metadata(response)
          {
            id: response[:id] || response["id"],
            model: response[:model] || response["model"],
            status: response[:status] || response["status"],
            usage: response[:usage] || response["usage"]
          }.compact
        end

        def output_to_messages(output)
          output.filter_map do |item|
            type = item[:type] || item["type"]
            next unless type == "message"

            role = item[:role] || item["role"] || "assistant"
            content = item[:content] || item["content"] || []

            text = content.filter_map do |c|
              c[:text] || c["text"] if (c[:type] || c["type"]) == "output_text"
            end.join("\n")

            { role: role, content: text }
          end
        end

        def normalize_messages(messages)
          messages.map.with_index do |msg, index|
            {
              role: msg[:role] || msg["role"],
              content: extract_text_content(msg[:content] || msg["content"]),
              tool_calls: msg[:tool_calls] || msg["tool_calls"] || [],
              turn: msg[:turn] || msg["turn"] || index + 1
            }
          end
        end

        def extract_tool_usage(output)
          output.filter_map do |item|
            next unless (item[:type] || item["type"]) == "function_call"

            {
              function_name: item[:name] || item["name"],
              call_id: item[:call_id] || item["call_id"],
              arguments: parse_arguments(item[:arguments] || item["arguments"]),
              result: nil  # Results would need to be provided separately
            }
          end
        end

        def extract_file_search_results(output)
          output.filter_map do |item|
            next unless (item[:type] || item["type"]) == "file_search_call"

            results = item[:results] || item["results"] || []
            {
              query: item[:query] || item["query"],
              files: results.map { |r| r[:filename] || r["filename"] },
              scores: results.map { |r| r[:score] || r["score"] }
            }
          end
        end
      end
    end
  end
end
