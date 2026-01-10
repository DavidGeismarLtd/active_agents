# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Normalizers
      # Abstract base class for response normalizers.
      #
      # Normalizers transform API-specific responses into a standard format
      # that can be consumed by evaluators. This decouples evaluators from
      # the specifics of each AI provider API.
      #
      # Each API type has its own normalizer that knows how to extract:
      # - Text content
      # - Tool/function calls
      # - File search results
      # - Other API-specific data
      #
      # @example Normalize a Chat Completion response
      #   normalizer = ChatCompletionNormalizer.new
      #   normalized = normalizer.normalize_single_response(raw_response)
      #   # => { text: "...", tool_calls: [...], metadata: {...} }
      #
      # @example Normalize an Assistants API conversation
      #   normalizer = AssistantsApiNormalizer.new
      #   normalized = normalizer.normalize_conversation(raw_data)
      #   # => { messages: [...], tool_usage: [...], file_search_results: [...] }
      #
      class BaseNormalizer
        # Normalize a single response for SingleResponse evaluators
        #
        # @param raw_response [Hash, String] the raw API response
        # @return [Hash] normalized response with:
        #   - :text [String] the response text content
        #   - :tool_calls [Array<Hash>] tool/function calls
        #   - :metadata [Hash] additional metadata
        def normalize_single_response(raw_response)
          raise NotImplementedError, "#{self.class.name} must implement #normalize_single_response"
        end

        # Normalize a conversation for Conversational evaluators
        #
        # @param raw_data [Hash] the raw conversation data
        # @return [Hash] normalized conversation with:
        #   - :messages [Array<Hash>] array of message objects
        #   - :tool_usage [Array<Hash>] aggregated tool usage
        #   - :file_search_results [Array<Hash>] file search results
        def normalize_conversation(raw_data)
          raise NotImplementedError, "#{self.class.name} must implement #normalize_conversation"
        end

        protected

        # Parse JSON arguments safely
        #
        # @param args [String, Hash, nil] arguments to parse
        # @return [Hash] parsed arguments
        def parse_arguments(args)
          return {} if args.nil?
          return args if args.is_a?(Hash)

          begin
            JSON.parse(args)
          rescue JSON::ParserError
            {}
          end
        end

        # Extract text content from various formats
        #
        # @param content [String, Array, nil] content in various formats
        # @return [String] extracted text
        def extract_text_content(content)
          case content
          when String
            content
          when Array
            # Handle content arrays (e.g., from Assistants API)
            content.filter_map do |item|
              case item
              when String
                item
              when Hash
                item["text"] || item[:text] if item["type"] == "text" || item[:type] == "text"
              end
            end.join("\n")
          else
            content.to_s
          end
        end
      end
    end
  end
end
