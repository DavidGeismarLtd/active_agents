# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Base class for evaluators that work with OpenAI Assistant conversations.
    #
    # These evaluators receive conversation_data (Hash) and evaluate multi-turn conversations.
    # They are compatible with PromptTracker::Openai::Assistant testables.
    #
    # Subclasses should implement:
    # - #evaluate_score: Calculate the numeric score (0-100)
    # - .metadata: Class method providing evaluator metadata
    #
    # @example Creating a conversation-based evaluator
    #   class MyConversationEvaluator < BaseOpenAiAssistantEvaluator
    #     def evaluate_score
    #       assistant_messages.length > 2 ? 100 : 50
    #     end
    #   end
    #
    class BaseOpenAiAssistantEvaluator < BaseEvaluator
      attr_reader :conversation_data

      # Returns compatible testable classes
      #
      # @return [Array<Class>] array containing PromptTracker::Openai::Assistant
      def self.compatible_with
        [ PromptTracker::Openai::Assistant ]
      end

      # Initialize the evaluator with conversation data
      #
      # @param conversation_data [Hash] the conversation data with messages array
      # @param config [Hash] configuration for the evaluator
      def initialize(conversation_data, config = {})
        @conversation_data = conversation_data
        super(config)
      end

      # Evaluate and create an Evaluation record
      # This is the ONLY place where Evaluation.create! should be called for Assistant evaluations
      # All scores are 0-100
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
    end
  end
end
