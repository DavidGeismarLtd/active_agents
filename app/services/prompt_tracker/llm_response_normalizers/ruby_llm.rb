# frozen_string_literal: true

module PromptTracker
  module LlmResponseNormalizers
    # Normalizer for RubyLLM::Message responses from any provider.
    #
    # RubyLLM provides a unified interface across providers (OpenAI, Anthropic, etc.),
    # so this single normalizer can handle responses from all providers.
    #
    # When RubyLLM handles tools automatically, the final message has tool_calls=nil
    # because the tool loop was completed internally. Pass chat_messages to extract
    # all tool calls from the conversation history.
    #
    # @example Single message normalization
    #   LlmResponseNormalizers::RubyLlm.normalize(ruby_llm_message)
    #
    # @example With conversation history (extracts all tool calls)
    #   LlmResponseNormalizers::RubyLlm.normalize(ruby_llm_message, chat_messages: chat.messages)
    #
    class RubyLlm < Base
      # Normalize a RubyLLM response
      #
      # @param raw_response [RubyLLM::Message] the response message
      # @param chat_messages [Array<RubyLLM::Message>, nil] optional full conversation history
      # @return [NormalizedLlmResponse]
      def self.normalize(raw_response, chat_messages: nil)
        new(raw_response, chat_messages: chat_messages).normalize
      end

      def initialize(raw_response, chat_messages: nil)
        super(raw_response)
        @chat_messages = chat_messages
      end

      def normalize
        NormalizedLlmResponse.new(
          text: raw_response.content || "",
          usage: extract_usage,
          model: raw_response.model_id,
          tool_calls: extract_tool_calls,
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: extract_api_metadata,
          raw_response: raw_response
        )
      end

      private

      # Extract usage information from RubyLLM response
      #
      # @return [Hash] usage with prompt_tokens, completion_tokens, total_tokens
      def extract_usage
        input = raw_response.input_tokens || 0
        output = raw_response.output_tokens || 0

        {
          prompt_tokens: input,
          completion_tokens: output,
          total_tokens: input + output
        }
      end

      # Extract tool calls from RubyLLM response or conversation history
      #
      # When chat_messages is provided, extracts ALL tool calls from the conversation.
      # Otherwise, extracts only from the current response (may be empty if tools
      # were auto-executed by RubyLLM).
      #
      # @return [Array<Hash>] normalized tool calls
      def extract_tool_calls
        if @chat_messages.present?
          extract_tool_calls_from_history
        else
          extract_tool_calls_from_response
        end
      end

      # Extract tool calls from the final response message only
      #
      # @return [Array<Hash>] normalized tool calls
      def extract_tool_calls_from_response
        return [] unless raw_response.respond_to?(:tool_calls) && raw_response.tool_calls.present?

        normalize_tool_calls_hash(raw_response.tool_calls)
      end

      # Extract all tool calls from conversation history
      #
      # Finds all assistant messages that have tool_calls and extracts them.
      #
      # @return [Array<Hash>] normalized tool calls from entire conversation
      def extract_tool_calls_from_history
        @chat_messages
          .select { |msg| msg.role == :assistant && msg.tool_calls.present? }
          .flat_map { |msg| normalize_tool_calls_hash(msg.tool_calls) }
      end

      # Normalize a hash of tool calls from RubyLLM format
      #
      # RubyLLM stores tool_calls as { "id" => RubyLLM::ToolCall, ... }
      #
      # @param tool_calls_hash [Hash] hash of tool call id => ToolCall object
      # @return [Array<Hash>] normalized tool calls
      def normalize_tool_calls_hash(tool_calls_hash)
        tool_calls_hash.map do |_id, tc|
          {
            id: tc.id,
            type: "function",
            function_name: tc.name,
            arguments: tc.arguments || {}
          }
        end
      end

      # Extract API metadata from response
      #
      # @return [Hash] metadata including message_id and stop_reason if available
      def extract_api_metadata
        metadata = {}
        metadata[:message_id] = raw_response.id if raw_response.respond_to?(:id)
        metadata[:stop_reason] = raw_response.stop_reason if raw_response.respond_to?(:stop_reason)
        metadata
      end
    end
  end
end
