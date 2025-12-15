# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_test_runs
#
#  assertion_results        :jsonb            not null
#  cost_usd                 :decimal(10, 6)
#  created_at               :datetime         not null
#  error_message            :text
#  evaluator_results        :jsonb            not null
#  execution_time_ms        :integer
#  failed_evaluators        :integer          default(0), not null
#  id                       :bigint           not null, primary key
#  llm_response_id          :bigint
#  metadata                 :jsonb            not null
#  passed                   :boolean
#  passed_evaluators        :integer          default(0), not null
#  prompt_test_id           :bigint           not null
#  prompt_test_suite_run_id :bigint
#  prompt_version_id        :bigint           not null
#  status                   :string           default("pending"), not null
#  total_evaluators         :integer          default(0), not null
#  updated_at               :datetime         not null
#
module PromptTracker
  # Represents the result of running a single test.
  #
  # Records all details about test execution including:
  # - Pass/fail status
  # - Evaluator results
  # - Performance metrics
  # - Error details
  #
  # @example Access test run results
  #   run = PromptTestRun.last
  #   puts "Status: #{run.status}"
  #   puts "Passed: #{run.passed?}"
  #   puts "Evaluators: #{run.passed_evaluators}/#{run.total_evaluators}"
  #   puts "Time: #{run.execution_time_ms}ms"
  #
  class PromptTestRun < ApplicationRecord
    # Associations
    belongs_to :prompt_test, touch: true
    belongs_to :prompt_version
    belongs_to :llm_response, optional: true
    belongs_to :dataset, optional: true, class_name: "PromptTracker::Dataset"
    belongs_to :dataset_row, optional: true, class_name: "PromptTracker::DatasetRow"
    has_many :evaluations, class_name: "PromptTracker::Evaluation", foreign_key: :prompt_test_run_id, dependent: :destroy
    has_many :human_evaluations,
             class_name: "PromptTracker::HumanEvaluation",
             dependent: :destroy

    # Validations
    validates :status, presence: true
    validates :status, inclusion: { in: %w[pending running passed failed error skipped] }

    # Scopes
    scope :passed, -> { where(passed: true) }
    scope :failed, -> { where(passed: false) }
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: [ "passed", "failed", "error" ]) }
    scope :recent, -> { order(created_at: :desc) }


    after_create_commit :broadcast_creation
    after_update_commit :broadcast_changes

    # Status helpers
    def pending?
      status == "pending"
    end

    def running?
      status == "running"
    end

    def completed?
      %w[passed failed error skipped].include?(status)
    end

    def error?
      status == "error"
    end

    def skipped?
      status == "skipped"
    end

    # Get evaluator pass rate
    #
    # @return [Float] percentage of evaluators that passed
    def evaluator_pass_rate
      return 0.0 if total_evaluators.zero?
      (passed_evaluators.to_f / total_evaluators * 100).round(2)
    end

    # Get failed evaluations
    #
    # @return [ActiveRecord::Relation] evaluations that failed
    def failed_evaluations
      evaluations.where(passed: false)
    end

    # Get passed evaluations
    #
    # @return [ActiveRecord::Relation] evaluations that passed
    def passed_evaluations
      evaluations.where(passed: true)
    end

    # Check if all evaluators passed
    #
    # @return [Boolean]
    def all_evaluators_passed?
      failed_evaluators.zero? && total_evaluators.positive?
    end

    # Calculate average score from all evaluations
    # All scores are 0-100, so just average them
    #
    # @return [Float, nil] average score (0-100) or nil if no evaluations
    def avg_score
      return nil if evaluations.empty?

      evaluations.average(:score)&.round(2)
    end

    private

  def broadcast_creation
    # Reload test to get fresh last_run association
    test = prompt_test.reload
    version = prompt_version
    prompt = version.prompt

    # If this is the first run, remove the placeholder row
    if test.prompt_test_runs.count == 1
      broadcast_remove(
        stream: "prompt_test_#{prompt_test_id}",
        target: "no_runs_placeholder"
      )
    end

    # Update the recent runs table on the PromptTest#show page
    broadcast_prepend(
      stream: "prompt_test_#{prompt_test_id}",
      target: "recent_runs_tbody",
      partial: "prompt_tracker/testing/prompt_tests/test_run_row",
      locals: { run: self }
    )

    # Update the status card on PromptTest#show page (pass rate, counts, etc.)
    broadcast_replace(
      stream: "prompt_test_#{prompt_test_id}",
      target: "test_status_card",
      partial: "prompt_tracker/testing/prompt_tests/test_status_card",
      locals: { test: test }
    )

    # Update the test row on the tests index page (shows last_run status)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test_row_#{test.id}",
      partial: "prompt_tracker/testing/prompt_tests/test_row",
      locals: { test: test, prompt: prompt, version: version }
    )

    # Update the accordion content (preserves open/closed state)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test-runs-content-#{test.id}",
      partial: "prompt_tracker/testing/prompt_tests/test_runs_accordion_content",
      locals: { test: test }
    )

    # Update the modals container to include new evaluation modals
    all_tests = version.prompt_tests.includes(:prompt_test_runs).order(created_at: :desc)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test-modals",
      partial: "prompt_tracker/testing/prompt_versions/test_modals",
      locals: { tests: all_tests, prompt: prompt, version: version }
    )

    # Update the overall status card on tests index page
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "overall_status_card",
      partial: "prompt_tracker/testing/prompt_tests/overall_status_card",
      locals: { tests: all_tests }
    )
  end

  def broadcast_changes
    # Reload test to get fresh last_run association
    test = prompt_test.reload
    version = prompt_version
    prompt = version.prompt

    # 1) Update the test run row on the PromptTest#show page
    broadcast_replace(
      stream: "prompt_test_#{prompt_test_id}",
      target: "test_run_row_#{id}",
      partial: "prompt_tracker/testing/prompt_tests/test_run_row",
      locals: { run: self }
    )

    # 2) Update the status card on PromptTest#show page (pass rate, counts, etc.)
    broadcast_replace(
      stream: "prompt_test_#{prompt_test_id}",
      target: "test_status_card",
      partial: "prompt_tracker/testing/prompt_tests/test_status_card",
      locals: { test: test }
    )

    # 3) Update the test row on the tests index page (shows last_run status)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test_row_#{test.id}",
      partial: "prompt_tracker/testing/prompt_tests/test_row",
      locals: { test: test, prompt: prompt, version: version }
    )

    # 3b) Update the individual test run row on the prompt version page
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test_run_row_#{id}",
      partial: "prompt_tracker/testing/prompt_tests/test_run_row",
      locals: { run: self }
    )

    # 4) Update the accordion content (preserves open/closed state)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test-runs-content-#{test.id}",
      partial: "prompt_tracker/testing/prompt_tests/test_runs_accordion_content",
      locals: { test: test }
    )

    # 5) Update the modals container to include updated evaluation modals
    all_tests = version.prompt_tests.includes(:prompt_test_runs).order(created_at: :desc)
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "test-modals",
      partial: "prompt_tracker/testing/prompt_versions/test_modals",
      locals: { tests: all_tests, prompt: prompt, version: version }
    )

    # 6) Update the overall status card on tests index page
    broadcast_replace(
      stream: "prompt_version_#{version.id}",
      target: "overall_status_card",
      partial: "prompt_tracker/testing/prompt_tests/overall_status_card",
      locals: { tests: all_tests }
    )
  end

  # Helper method to broadcast with proper rendering context (includes helpers)
  def broadcast_prepend(stream:, target:, partial:, locals:)
    html = ApplicationController.render(
      partial: partial,
      locals: locals
    )
    Turbo::StreamsChannel.broadcast_prepend_to(
      stream,
      target: target,
      html: html
    )
  end

  # Helper method to broadcast with proper rendering context (includes helpers)
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

  # Helper method to broadcast remove action
  def broadcast_remove(stream:, target:)
    Turbo::StreamsChannel.broadcast_remove_to(
      stream,
      target: target
    )
  end
  end
end
