# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Unified base class for all evaluators that work with normalized data.
    #
    # This class receives a normalized data hash that contains all the information
    # needed for evaluation, regardless of the source API (Chat Completion, Response API,
    # Assistants API, etc.). The normalization is done upstream by the appropriate
    # normalizer before the data reaches the evaluator.
    #
    # All evaluators should inherit from this class. The unified format allows
    # evaluators to work with both single-turn and multi-turn conversations.
    #
    # Normalized Data Format:
    #   {
    #     messages: [                          # Array of messages (1 for single-turn, N for multi-turn)
    #       { role: "user", content: "...", tool_calls: [...], turn: 1 },
    #       { role: "assistant", content: "...", tool_calls: [...], turn: 2 }
    #     ],
    #     tool_usage: [...],                   # Aggregated tool usage across messages
    #     web_search_results: [...],           # Web search results (Response API)
    #     code_interpreter_results: [...],     # Code interpreter results (Response API)
    #     file_search_results: [...],          # File search results (any API)
    #     run_steps: [...],                    # Assistants API run steps (optional, nil for other APIs)
    #     metadata: { model: "...", ... }      # Response metadata
    #   }
    #
    # Subclasses should implement:
    # - #evaluate_score: Calculate the numeric score (0-100)
    # - .metadata: Class method providing evaluator metadata
    #
    # @example Creating an evaluator
    #   class MyEvaluator < BaseNormalizedEvaluator
    #     def evaluate_score
    #       response_text.length > 100 ? 100 : 50
    #     end
    #   end
    #
    class BaseNormalizedEvaluator < BaseEvaluator
      attr_reader :data
      alias_method :conversation_data, :data

      # Returns the evaluator category
      # @return [Symbol] :normalized (unified category)
      def self.category
        :normalized
      end

      # Returns the API type (legacy compatibility)
      # @return [Symbol] :normalized
      def self.api_type
        :normalized
      end

      # Returns compatible testable classes
      # All normalized evaluators work with all testables
      # @return [Array<Class>] array of compatible testable classes
      def self.compatible_with
        [ PromptTracker::PromptVersion, PromptTracker::Openai::Assistant ]
      end

      # Returns compatible API types
      # Override in subclasses to restrict to specific APIs
      # @return [Array<Symbol>] array of compatible API types
      def self.compatible_with_apis
        [ :all ]
      end

      # Initialize the evaluator with normalized data
      #
      # @param data [Hash, String] the normalized data or a simple string response
      # @param config [Hash] configuration for the evaluator
      def initialize(data, config = {})
        @raw_data = data
        @data = normalize_input(data)
        super(config)
      end

      # === Message Accessors ===

      # Get all messages from the data
      # @return [Array<Hash>] array of message hashes
      def messages
        @messages ||= data[:messages] || []
      end

      # Get the last message (usually the assistant's response)
      # @return [Hash, nil] the last message or nil
      def last_message
        messages.last
      end

      # Get the response text (from last assistant message)
      # For backward compatibility with single-response evaluators
      # @return [String] the response text
      def response_text
        @response_text ||= begin
          # Find the last assistant message
          assistant_msg = messages.reverse.find { |m| m[:role] == "assistant" }
          assistant_msg&.dig(:content) || ""
        end
      end

      # Get all assistant messages
      # @return [Array<Hash>] array of assistant message hashes
      def assistant_messages
        @assistant_messages ||= messages.select { |m| m[:role] == "assistant" }
      end

      # Get all user messages
      # @return [Array<Hash>] array of user message hashes
      def user_messages
        @user_messages ||= messages.select { |m| m[:role] == "user" }
      end

      # === Tool Usage Accessors ===

      # Get aggregated tool usage
      # @return [Array<Hash>] array of tool usage records
      def tool_usage
        data[:tool_usage] || []
      end

      # Get web search results
      # @return [Array<Hash>] array of web search result records
      def web_search_results
        data[:web_search_results] || []
      end

      # Get code interpreter results
      # @return [Array<Hash>] array of code interpreter result records
      def code_interpreter_results
        data[:code_interpreter_results] || []
      end

      # Get file search results
      # @return [Array<Hash>] array of file search result records
      def file_search_results
        data[:file_search_results] || []
      end

      # Get Assistants API run steps (nil for other APIs)
      # @return [Array<Hash>, nil] array of run steps or nil
      def run_steps
        data[:run_steps]
      end

      # Check if run steps are available (Assistants API only)
      # @return [Boolean] true if run_steps data is present
      def run_steps_available?
        run_steps.present?
      end

      # Get response metadata
      # @return [Hash] metadata about the response
      def response_metadata
        data[:metadata] || {}
      end

      private

      # Normalize input to standard format
      # Handles both new unified format and legacy formats
      #
      # @param input [String, Hash] raw input
      # @return [Hash] normalized data hash
      def normalize_input(input)
        case input
        when String
          # Simple string response (legacy single-response format)
          {
            messages: [ { role: "assistant", content: input, tool_calls: [], turn: 1 } ],
            tool_usage: [],
            web_search_results: [],
            code_interpreter_results: [],
            file_search_results: [],
            run_steps: nil,
            metadata: {}
          }
        when Hash
          normalize_hash_input(input)
        else
          # Fallback: convert to string
          {
            messages: [ { role: "assistant", content: input.to_s, tool_calls: [], turn: 1 } ],
            tool_usage: [],
            web_search_results: [],
            code_interpreter_results: [],
            file_search_results: [],
            run_steps: nil,
            metadata: {}
          }
        end
      end

      # Normalize hash input handling both new and legacy formats
      #
      # @param input [Hash] hash input
      # @return [Hash] normalized data hash
      def normalize_hash_input(input)
        # Check if already in unified format (has :messages key)
        if input.key?(:messages) || input.key?("messages")
          normalize_unified_format(input)
        # Legacy single-response format (has :text key)
        elsif input.key?(:text) || input.key?("text")
          normalize_legacy_single_response(input)
        else
          # Unknown format, try to extract what we can
          normalize_unified_format(input)
        end
      end

      # Normalize unified format input
      def normalize_unified_format(input)
        run_steps = input[:run_steps] || input["run_steps"]

        {
          messages: normalize_messages(input[:messages] || input["messages"] || []),
          tool_usage: input[:tool_usage] || input["tool_usage"] || [],
          web_search_results: input[:web_search_results] || input["web_search_results"] || [],
          code_interpreter_results: input[:code_interpreter_results] || input["code_interpreter_results"] || [],
          file_search_results: extract_file_search_results(input, run_steps),
          run_steps: run_steps,
          metadata: input[:metadata] || input["metadata"] || {}
        }
      end

      # Extract file_search_results from either top-level or nested in run_steps
      def extract_file_search_results(input, run_steps)
        # First check top-level file_search_results
        top_level = input[:file_search_results] || input["file_search_results"]
        return top_level if top_level.present?

        # Extract from run_steps if present (Assistants API format)
        return [] unless run_steps.is_a?(Array)

        run_steps.flat_map do |step|
          step[:file_search_results] || step["file_search_results"] || []
        end
      end

      # Normalize legacy single-response format
      def normalize_legacy_single_response(input)
        text = input[:text] || input["text"] || ""
        tool_calls = input[:tool_calls] || input["tool_calls"] || []

        {
          messages: [ { role: "assistant", content: text, tool_calls: tool_calls, turn: 1 } ],
          tool_usage: tool_calls,
          web_search_results: [],
          code_interpreter_results: [],
          file_search_results: [],
          run_steps: nil,
          metadata: input[:metadata] || input["metadata"] || {}
        }
      end

      # Normalize messages array to ensure consistent format
      def normalize_messages(msgs)
        return [] unless msgs.is_a?(Array)

        msgs.map.with_index do |msg, index|
          {
            role: msg[:role] || msg["role"] || "unknown",
            content: msg[:content] || msg["content"] || "",
            tool_calls: msg[:tool_calls] || msg["tool_calls"] || [],
            turn: msg[:turn] || msg["turn"] || index + 1
          }
        end
      end
    end
  end
end
