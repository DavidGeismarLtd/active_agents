# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Base class for evaluators that work with PromptVersion responses.
    #
    # These evaluators receive response_text (String) and evaluate text-based responses.
    # They are compatible with PromptVersion testables.
    #
    # Subclasses should implement:
    # - #evaluate_score: Calculate the numeric score (0-100)
    # - .metadata: Class method providing evaluator metadata
    #
    # @example Creating a text-based evaluator
    #   class MyTextEvaluator < BasePromptVersionEvaluator
    #     def evaluate_score
    #       response_text.length > 100 ? 100 : 50
    #     end
    #   end
    #
    class BasePromptVersionEvaluator < BaseEvaluator
      attr_reader :response_text

      # Returns compatible testable classes
      #
      # @return [Array<Class>] array containing PromptVersion
      def self.compatible_with
        [ PromptTracker::PromptVersion ]
      end

      # Initialize the evaluator with response text
      #
      # @param response_text [String] the response text to evaluate
      # @param config [Hash] configuration for the evaluator
      def initialize(response_text, config = {})
        @response_text = response_text
        super(config)
      end

      # Evaluate and create an Evaluation record
      # This is the ONLY place where Evaluation.create! should be called for PromptVersion evaluations
      # All scores are 0-100
      #
      # @return [Evaluation] the created evaluation
      def evaluate
        score = evaluate_score
        feedback_text = generate_feedback

        Evaluation.create!(
          llm_response: config[:llm_response],
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
