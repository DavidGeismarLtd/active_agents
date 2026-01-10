# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Conversational
      # Base class for evaluators that work with conversational (normalized) data.
      #
      # These evaluators receive a normalized conversation hash and evaluate multi-turn
      # conversations. The conversation is API-agnostic - it has been normalized by
      # the appropriate normalizer before being passed to the evaluator.
      #
      # Used for: conversational test mode on any testable.
      #
      # Subclasses should implement:
      # - #evaluate_score: Calculate the numeric score (0-100)
      # - .metadata: Class method providing evaluator metadata
      # - .compatible_with_apis: (optional) Override to specify API compatibility
      #
      # @example Creating a conversational evaluator
      #   class MyEvaluator < BaseConversationalEvaluator
      #     def self.compatible_with_apis
      #       [ApiTypes::OPENAI_ASSISTANTS_API]  # Only Assistants API
      #     end
      #
      #     def evaluate_score
      #       file_search_results.any? ? 100 : 0
      #     end
      #   end
      #
      class BaseConversationalEvaluator < BaseEvaluator
        attr_reader :conversation

        # Returns the evaluator category
        #
        # @return [Symbol] :conversational
        def self.category
          :conversational
        end

        # Returns the API type (legacy)
        #
        # @return [Symbol] :conversational
        def self.api_type
          :conversational
        end

        # Returns compatible testable classes (legacy)
        #
        # @return [Array<Class>] array of compatible testable classes
        def self.compatible_with
          [ PromptTracker::PromptVersion, PromptTracker::Openai::Assistant ]
        end

        # Initialize the evaluator with normalized conversation data
        #
        # @param conversation [Hash] the conversation data with:
        #   - :messages [Array<Hash>] array of message objects
        #   - :tool_usage [Array<Hash>] aggregated tool usage
        #   - :file_search_results [Array<Hash>] file search results
        #   - :run_steps [Array<Hash>] (optional) Assistants API run steps
        # @param config [Hash] configuration for the evaluator
        def initialize(conversation, config = {})
          @raw_conversation = conversation || {}
          @conversation = normalize_conversation(conversation)
          super(config)
        end

        # Backward compatibility: access raw conversation data
        # @deprecated Use conversation instead
        #
        # @return [Hash] the raw conversation data
        def conversation_data
          @raw_conversation
        end

        # Get all messages from the conversation
        # Returns raw messages for backward compatibility
        #
        # @return [Array<Hash>] array of message hashes
        def messages
          # Return raw messages for backward compatibility
          @messages ||= conversation_data["messages"] || conversation_data[:messages] || []
        end

        # Get normalized messages with symbol keys
        #
        # @return [Array<Hash>] array of normalized message hashes
        def normalized_messages
          conversation[:messages] || []
        end

        # Get assistant messages only
        #
        # @return [Array<Hash>] array of assistant message hashes
        def assistant_messages
          @assistant_messages ||= messages.select do |m|
            role = m[:role] || m["role"]
            role == "assistant"
          end
        end

        # Get user messages only
        #
        # @return [Array<Hash>] array of user message hashes
        def user_messages
          @user_messages ||= messages.select do |m|
            role = m[:role] || m["role"]
            role == "user"
          end
        end

        # Get aggregated tool usage across the conversation
        #
        # @return [Array<Hash>] array of tool usage records
        def tool_usage
          conversation[:tool_usage] || []
        end

        # Get file search results (normalized from any API)
        #
        # @return [Array<Hash>] array of file search result records
        def file_search_results
          conversation[:file_search_results] || []
        end

        # Evaluate and create an Evaluation record
        #
        # @return [Evaluation] the created evaluation
        def evaluate
          score = evaluate_score
          feedback_text = generate_feedback

          Evaluation.create!(
            test_run: config[:test_run],
            evaluator_type: self.class.name,
            evaluator_config_id: config[:evaluator_config_id],
            score: score,
            score_min: 0,
            score_max: 100,
            passed: passed?,
            feedback: feedback_text,
            metadata: metadata,
            evaluation_context: config[:evaluation_context] || "tracked_call"
          )
        end

        private

        # Normalize input to standard conversation format
        #
        # @param input [Hash, nil] raw conversation input
        # @return [Hash] normalized conversation
        def normalize_conversation(input)
          return { messages: [], tool_usage: [], file_search_results: [] } if input.nil?

          {
            messages: normalize_messages(input[:messages] || input["messages"] || []),
            tool_usage: input[:tool_usage] || input["tool_usage"] || [],
            file_search_results: input[:file_search_results] || input["file_search_results"] || []
          }
        end

        # Normalize messages array
        #
        # @param msgs [Array] raw messages array
        # @return [Array<Hash>] normalized messages with symbol keys
        def normalize_messages(msgs)
          msgs.map do |msg|
            {
              role: msg[:role] || msg["role"],
              content: msg[:content] || msg["content"],
              tool_calls: msg[:tool_calls] || msg["tool_calls"] || [],
              turn: msg[:turn] || msg["turn"]
            }
          end
        end
      end
    end
  end
end
