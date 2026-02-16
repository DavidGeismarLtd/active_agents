# frozen_string_literal: true

module PromptTracker
  module LlmResponseNormalizers
    module Openai
      # Normalizer for OpenAI Chat Completions API (via RubyLLM).
      #
      # Transforms RubyLLM::Message objects into NormalizedLlmResponse objects.
      # Handles extraction of text, usage, and tool calls.
      #
      # @example
      #   LlmResponseNormalizers::Openai::ChatCompletions.normalize(ruby_llm_message)
      #
      class ChatCompletions < Base
        def normalize
          NormalizedLlmResponse.new(
            text: raw_response.content,
            usage: extract_usage,
            model: raw_response.model_id,
            tool_calls: extract_tool_calls,
            file_search_results: [],
            web_search_results: [],
            code_interpreter_results: [],
            api_metadata: {},
            raw_response: raw_response
          )
        end

        private

        # Extract usage information from RubyLLM response
        def extract_usage
          {
            prompt_tokens: raw_response.input_tokens || 0,
            completion_tokens: raw_response.output_tokens || 0,
            total_tokens: (raw_response.input_tokens || 0) + (raw_response.output_tokens || 0)
          }
        end

        # Extract tool calls from RubyLLM response
        def extract_tool_calls
          return [] unless raw_response.respond_to?(:tool_calls) && raw_response.tool_calls.present?

          raw_response.tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: "function",
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_json_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end
      end
    end
  end
end
