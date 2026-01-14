# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_evaluations
#
#  created_at             :datetime         not null
#  evaluation_context     :string           default("tracked_call")
#  evaluator_config_id    :bigint
#  evaluator_type         :string           not null
#  feedback               :text
#  id                     :bigint           not null, primary key
#  llm_response_id        :bigint           not null
#  metadata               :jsonb
#  passed                 :boolean
#  test_run_id            :bigint           (renamed from prompt_test_run_id)
#  score                  :decimal(10, 2)   not null
#  score_max              :decimal(10, 2)   default(5.0)
#  score_min              :decimal(10, 2)   default(0.0)
#  updated_at             :datetime         not null
#
module PromptTracker
  # Represents a quality evaluation of an LLM response.
  #
  # Evaluations can be created by:
  # - Humans: Manual review and rating
  # - Automated systems: Rule-based scoring
  # - LLM judges: Another LLM evaluates the response
  #
  # @example Creating a human evaluation
  #   evaluation = Evaluation.create!(
  #     llm_response: response,
  #     score: 4.5,
  #     score_min: 0,
  #     score_max: 5,
  #     criteria_scores: {
  #       "helpfulness" => 5,
  #       "tone" => 4,
  #       "accuracy" => 4.5
  #     },
  #     evaluator_type: "human",
  #     evaluator_id: "john@example.com",
  #     feedback: "Good response, but could be more concise"
  #   )
  #
  # @example Creating an automated evaluation
  #   evaluation = Evaluation.create!(
  #     llm_response: response,
  #     score: 85,
  #     score_min: 0,
  #     score_max: 100,
  #     evaluator_type: "automated",
  #     evaluator_id: "sentiment_analyzer_v1"
  #   )
  #
  class Evaluation < ApplicationRecord
    # Associations
    # For production tracked call evaluations
    belongs_to :llm_response,
               class_name: "PromptTracker::LlmResponse",
               inverse_of: :evaluations,
               optional: true

    # For test run evaluations
    belongs_to :test_run,
               class_name: "PromptTracker::TestRun",
               optional: true

    belongs_to :evaluator_config,
               class_name: "PromptTracker::EvaluatorConfig",
               optional: true

    has_one :prompt_version,
            through: :llm_response,
            class_name: "PromptTracker::PromptVersion"

    has_one :prompt,
            through: :prompt_version,
            class_name: "PromptTracker::Prompt"

    has_many :human_evaluations,
             class_name: "PromptTracker::HumanEvaluation",
             dependent: :destroy

    # Validations
    validates :score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :evaluator_type, presence: true
    validates :evaluation_context, presence: true, inclusion: { in: %w[tracked_call test_run manual] }

    validate :metadata_must_be_hash
    validate :must_have_evaluatable

    # Enums
    enum evaluation_context: {
      tracked_call: "tracked_call",  # From host app via track_llm_call
      test_run: "test_run",          # From PromptTest execution
      manual: "manual"               # Manual evaluation in UI
    }

    # Scopes

    # Returns evaluations by a specific evaluator class
    # @param evaluator_type [String] the evaluator class name
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :by_evaluator, ->(evaluator_type) { where(evaluator_type: evaluator_type) }

    # Returns evaluations from tracked calls (host app)
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :tracked, -> { where(evaluation_context: "tracked_call") }

    # Returns evaluations from test runs
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :from_tests, -> { where(evaluation_context: "test_run") }

    # Returns manual evaluations
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :manual_only, -> { where(evaluation_context: "manual") }

    # Returns evaluations with score above threshold
    # @param threshold [Numeric] the minimum score
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :above_score, ->(threshold) { where("score >= ?", threshold) }

    # Returns evaluations with score below threshold
    # @param threshold [Numeric] the maximum score
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :below_score, ->(threshold) { where("score <= ?", threshold) }

    # Returns recent evaluations (last 24 hours by default)
    # @param hours [Integer] number of hours to look back
    # @return [ActiveRecord::Relation<Evaluation>]
    scope :recent, ->(hours = 24) { where("created_at > ?", hours.hours.ago) }

    # Instance Methods

    # Checks if the score is passing (above 70 by default).
    # All scores are 0-100, so no normalization needed.
    #
    # @param threshold [Float] passing threshold (default: 70)
    # @return [Boolean] true if score is passing
    def passing?(threshold = 70)
      score >= threshold
    end

    # Returns the evaluator key derived from the class name
    # e.g., "PromptTracker::Evaluators::KeywordEvaluator" -> :keyword
    #
    # @return [Symbol] evaluator key
    def evaluator_key
      evaluator_type.demodulize.underscore.gsub("_evaluator", "").to_sym
    end

    # Returns the evaluator class
    #
    # @return [Class] the evaluator class
    def evaluator_class
      evaluator_type.constantize
    end

    # Returns a human-readable evaluator name
    #
    # @return [String] evaluator name
    def evaluator_name
      evaluator_type.demodulize.gsub("Evaluator", "").titleize
    end

    # Returns a human-readable summary of this evaluation.
    #
    # @return [String] summary
    def summary
      type_label = evaluator_type.humanize
      # Format numbers without unnecessary decimals
      score_formatted = score % 1 == 0 ? score.to_i : score
      max_formatted = score_max % 1 == 0 ? score_max.to_i : score_max
      score_label = "#{score_formatted}/#{max_formatted}"
      percentage = "(#{score_percentage.round(1)}%)"

      "#{type_label}: #{score_label} #{percentage}"
    end

    private

    # Validates that metadata is a hash
    def metadata_must_be_hash
      return if metadata.nil? || metadata.is_a?(Hash)

      errors.add(:metadata, "must be a hash")
    end

    # Validates that evaluation belongs to exactly one evaluatable (llm_response OR test_run)
    # - Production evaluations (tracked_call context) should have llm_response_id
    # - Test evaluations (test_run context) should have test_run_id
    def must_have_evaluatable
      if llm_response_id.nil? && test_run_id.nil?
        errors.add(:base, "must belong to either llm_response or test_run")
      end

      if llm_response_id.present? && test_run_id.present?
        errors.add(:base, "cannot belong to both llm_response and test_run")
      end
    end
  end
end
