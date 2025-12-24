# frozen_string_literal: true

module PromptTracker
  # Represents a human evaluation/review.
  #
  # HumanEvaluations can be used in three ways:
  # 1. Review of automated evaluations (evaluation_id set)
  # 2. Direct evaluation of LLM responses (llm_response_id set)
  # 3. Direct evaluation of test runs (prompt_test_run_id set)
  #
  # @example Creating a review of an automated evaluation
  #   human_eval = HumanEvaluation.create!(
  #     evaluation: evaluation,
  #     score: 85,
  #     feedback: "The automated evaluation was mostly correct, but missed some nuance in tone."
  #   )
  #
  # @example Creating a direct human evaluation of a response
  #   human_eval = HumanEvaluation.create!(
  #     llm_response: response,
  #     score: 90,
  #     feedback: "Excellent response, very helpful and professional."
  #   )
  #
  # @example Creating a direct human evaluation of a test run
  #   human_eval = HumanEvaluation.create!(
  #     prompt_test_run: test_run,
  #     score: 95,
  #     feedback: "Test passed with excellent results."
  #   )
  #
  class HumanEvaluation < ApplicationRecord
    # Associations
    belongs_to :evaluation, optional: true
    belongs_to :llm_response,
               class_name: "PromptTracker::LlmResponse",
               optional: true
    belongs_to :prompt_test_run,
               class_name: "PromptTracker::PromptTestRun",
               optional: true

    # Validations
    validates :score, presence: true, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }
    validates :feedback, presence: true
    validate :must_belong_to_evaluation_or_llm_response

    # Callbacks
    after_create_commit :broadcast_human_evaluation_created

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :high_scores, -> { where("score >= ?", 70) }
    scope :low_scores, -> { where("score < ?", 70) }

    # Instance Methods

    # Get the difference between human score and automated evaluation score
    #
    # @return [Float] difference (positive means human scored higher)
    def score_difference
      score - evaluation.score
    end

    # Check if human agrees with automated evaluation
    # (within 10 points tolerance by default)
    #
    # @param tolerance [Float] acceptable difference (default: 10)
    # @return [Boolean] true if scores are within tolerance
    def agrees_with_evaluation?(tolerance = 10)
      score_difference.abs <= tolerance
    end

    private

    # Validate that exactly one association is set
    def must_belong_to_evaluation_or_llm_response
      associations = [ evaluation_id, llm_response_id, prompt_test_run_id ].compact

      if associations.empty?
        errors.add(:base, "Must belong to either an evaluation, llm_response, or prompt_test_run")
      elsif associations.size > 1
        errors.add(:base, "Cannot belong to multiple associations")
      end
    end

    # Broadcast updates when a human evaluation is created
    def broadcast_human_evaluation_created
      if test_run_id.present?
        broadcast_test_run_updates
      elsif llm_response_id.present?
        broadcast_llm_response_updates
      end
    end

    # Broadcast updates for test run human evaluations
    def broadcast_test_run_updates
      # Reload the run and force reload of human_evaluations association
      run = TestRun.find(test_run_id)
      run.human_evaluations.reload
      version = run.prompt_version
      test = run.test

      # Update the test run row on the prompt version page
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_run_row_#{run.id}",
        partial: "prompt_tracker/testing/test_runs/prompt_versions/row",
        locals: { run: run }
      )

      # Update the test row (shows last_run status)
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_row_#{test.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_row",
        locals: { test: test, prompt: version.prompt, version: version }
      )

      # Update the "View all" modal body on the prompt version page
      # Use broadcast_update to update innerHTML, keeping the wrapper div intact
      broadcast_update(
        stream: "prompt_version_#{version.id}",
        target: "all-human-evals-modal-body-#{run.id}",
        partial: "prompt_tracker/shared/all_human_evaluations_modal_body",
        locals: { record: run, context: "testing" }
      )

      # Also update the "View all" modal body on the test show page
      # Use broadcast_update to update innerHTML, keeping the wrapper div intact
      broadcast_update(
        stream: "prompt_test_#{test.id}",
        target: "all-human-evals-modal-body-#{run.id}",
        partial: "prompt_tracker/shared/all_human_evaluations_modal_body",
        locals: { record: run, context: "testing" }
      )
    end

    # Broadcast updates for LlmResponse (tracked call) human evaluations
    def broadcast_llm_response_updates
      # Reload the llm_response and force reload of human_evaluations association
      call = LlmResponse.find(llm_response_id)
      call.human_evaluations.reload

      # Broadcast to the specific LlmResponse stream (not version stream)
      # This allows any page showing this call to receive updates,
      # regardless of whether it's showing one version or multiple versions

      # Update the human evaluations cell in the tracked calls table
      broadcast_update(
        stream: "llm_response_#{call.id}",
        target: "human_evaluations_cell_#{call.id}",
        partial: "prompt_tracker/shared/human_evaluations_cell",
        locals: { record: call, context: "monitoring" }
      )

      # Update the "View all" modal body
      broadcast_update(
        stream: "llm_response_#{call.id}",
        target: "all-human-evals-modal-body-#{call.id}",
        partial: "prompt_tracker/shared/all_human_evaluations_modal_body",
        locals: { record: call, context: "monitoring" }
      )
    end

    # Helper method to broadcast replace with proper rendering context
    # Replaces the entire target element with new HTML
    def broadcast_replace(stream:, target:, partial:, locals:)
      html = ApplicationController.render(
        partial: partial,
        locals: locals
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        stream,
        target: target,
        html: html
      )
    end

    # Helper method to broadcast update with proper rendering context
    # Updates the innerHTML of the target element, keeping the element itself intact
    def broadcast_update(stream:, target:, partial:, locals:)
      html = ApplicationController.render(
        partial: partial,
        locals: locals
      )
      Turbo::StreamsChannel.broadcast_update_to(
        stream,
        target: target,
        html: html
      )
    end
  end
end
