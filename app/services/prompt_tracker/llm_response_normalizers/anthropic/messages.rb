# frozen_string_literal: true

module PromptTracker
  module LlmResponseNormalizers
    module Anthropic
      # Normalizer for Anthropic Messages API responses.
      #
      # Transforms raw Anthropic API responses into NormalizedLlmResponse objects.
      # Handles extraction of text content, tool calls, and usage information.
      #
      # Anthropic response format:
      # {
      #   "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
      #   "type": "message",
      #   "role": "assistant",
      #   "content": [
      #     { "type": "text", "text": "Hello!" },
      #     { "type": "tool_use", "id": "toolu_01", "name": "get_weather", "input": {...} }
      #   ],
      #   "model": "claude-3-5-sonnet-20241022",
      #   "stop_reason": "end_turn",
      #   "usage": { "input_tokens": 12, "output_tokens": 8 }
      # }
      #
      # @example
      #   LlmResponseNormalizers::Anthropic::Messages.normalize(raw_api_response)
      #
      class Messages < Base
        def normalize
          NormalizedLlmResponse.new(
            text: extract_text_from_content,
            usage: extract_usage,
            model: raw_response["model"],
            tool_calls: extract_tool_calls,
            file_search_results: [],  # Anthropic doesn't have built-in file search
            web_search_results: [],   # Web search results would be in tool results
            code_interpreter_results: [],  # Anthropic doesn't have code interpreter
            api_metadata: {
              message_id: raw_response["id"],
              stop_reason: raw_response["stop_reason"]
            },
            raw_response: raw_response
          )
        end

        private

        def content
          @content ||= raw_response["content"] || []
        end

        # Extract text content from Anthropic response
        #
        # Anthropic returns content as an array of blocks:
        # [{ "type": "text", "text": "Hello!" }, ...]
        #
        # @return [String] concatenated text from all text blocks
        def extract_text_from_content
          text_parts = content.filter_map do |block|
            block["text"] if block["type"] == "text"
          end

          text_parts.join("\n").presence || ""
        end

        # Extract tool calls from Anthropic response
        #
        # Anthropic returns tool calls as content blocks with type "tool_use":
        # { "type": "tool_use", "id": "toolu_01", "name": "get_weather", "input": {...} }
        #
        # @return [Array<Hash>] normalized tool calls
        def extract_tool_calls
          content.filter_map do |block|
            next unless block["type"] == "tool_use"

            {
              id: block["id"],
              type: "function",
              function_name: block["name"],
              arguments: block["input"] || {}
            }
          end
        end

        # Extract usage information
        #
        # Anthropic uses different field names:
        # - input_tokens (vs prompt_tokens in OpenAI)
        # - output_tokens (vs completion_tokens in OpenAI)
        #
        # @return [Hash] normalized usage with prompt_tokens, completion_tokens, total_tokens
        def extract_usage
          usage = raw_response["usage"] || {}
          input_tokens = usage["input_tokens"] || 0
          output_tokens = usage["output_tokens"] || 0

          {
            prompt_tokens: input_tokens,
            completion_tokens: output_tokens,
            total_tokens: input_tokens + output_tokens
          }
        end
      end
    end
  end
end
