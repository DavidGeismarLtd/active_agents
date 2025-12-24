# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_test_runs
#
#  id                       :bigint           not null, primary key
#  test_id                  :bigint           not null
#  llm_response_id          :bigint
#  dataset_id               :bigint
#  dataset_row_id           :bigint
#  status                   :string           default("pending"), not null
#  passed                   :boolean
#  error_message            :text
#  assertion_results        :jsonb            not null
#  passed_evaluators        :integer          default(0), not null
#  failed_evaluators        :integer          default(0), not null
#  total_evaluators         :integer          default(0), not null
#  evaluator_results        :jsonb            not null
#  execution_time_ms        :integer
#  cost_usd                 :decimal(10, 6)
#  metadata                 :jsonb            not null
#  conversation_data        :jsonb            not null (for assistant tests)
#  created_at               :datetime         not null
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
  # - For assistant tests: conversation_data with per-message scores
  #
  # @example Access test run results
  #   run = TestRun.last
  #   puts "Status: #{run.status}"
  #   puts "Passed: #{run.passed?}"
  #   puts "Evaluators: #{run.passed_evaluators}/#{run.total_evaluators}"
  #   puts "Time: #{run.execution_time_ms}ms"
  #
  # @example Access conversation data (for assistant tests)
  #   run.conversation_data.each do |message|
  #     puts "#{message['role']}: #{message['content']}"
  #     puts "Score: #{message['score']}" if message['score']
  #   end
  #
  class TestRun < ApplicationRecord
    self.table_name = "prompt_tracker_test_runs"

    # Associations
    belongs_to :test,
               class_name: "PromptTracker::Test",
               foreign_key: :test_id,
               touch: true

    belongs_to :llm_response,
               class_name: "PromptTracker::LlmResponse",
               optional: true

    belongs_to :dataset,
               class_name: "PromptTracker::Dataset",
               optional: true

    belongs_to :dataset_row,
               class_name: "PromptTracker::DatasetRow",
               optional: true

    has_many :evaluations,
             class_name: "PromptTracker::Evaluation",
             foreign_key: :test_run_id,
             dependent: :destroy

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
    def evaluator_pass_rate
      return 0.0 if total_evaluators.zero?
      (passed_evaluators.to_f / total_evaluators * 100).round(2)
    end

    # Get failed evaluations
    def failed_evaluations
      evaluations.where(passed: false)
    end

    # Get passed evaluations
    def passed_evaluations
      evaluations.where(passed: true)
    end

    # Check if all evaluators passed
    def all_evaluators_passed?
      failed_evaluators.zero? && total_evaluators.positive?
    end

    # Calculate average score from all evaluations
    def avg_score
      return nil if evaluations.empty?
      evaluations.average(:score)&.round(2)
    end

    # Check if this is an assistant test run
    def assistant_test?
      test.testable_type == "PromptTracker::Assistant"
    end

    # Check if this is a prompt version test run
    def prompt_version_test?
      test.testable_type == "PromptTracker::PromptVersion"
    end

    # Get the prompt version (if this is a prompt version test)
    def prompt_version
      return nil unless prompt_version_test?
      test.testable
    end

    private

    def broadcast_creation
      # Only broadcast for prompt version tests (assistant tests have different UI)
      return unless prompt_version_test?

      # Reload test to get fresh last_run association
      test_obj = test.reload
      version = prompt_version
      prompt = version.prompt

      # If this is the first run, remove the placeholder row
      if test_obj.test_runs.count == 1
        broadcast_remove(
          stream: "prompt_test_#{test.id}",
          target: "no_runs_placeholder"
        )
      end

      # Update the recent runs table on the Test#show page
      broadcast_prepend(
        stream: "prompt_test_#{test.id}",
        target: "recent_runs_tbody",
        partial: "prompt_tracker/testing/test_runs/prompt_versions/row",
        locals: { run: self }
      )

      # Update the status card on Test#show page (pass rate, counts, etc.)
      broadcast_replace(
        stream: "prompt_test_#{test.id}",
        target: "test_status_card",
        partial: "prompt_tracker/testing/prompt_tests/test_status_card",
        locals: { test: test_obj }
      )

      # Update the test row on the tests index page (shows last_run status)
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_row_#{test_obj.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_row",
        locals: { test: test_obj, prompt: prompt, version: version }
      )

      # Update the accordion content (preserves open/closed state)
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test-runs-content-#{test_obj.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_runs_accordion_content",
        locals: { test: test_obj, prompt: prompt, version: version }
      )

      # Update the modals container to include new evaluation modals
      all_tests = version.tests.includes(:test_runs).order(created_at: :desc)
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
      # Only broadcast for prompt version tests (assistant tests have different UI)
      return unless prompt_version_test?

      # Reload test to get fresh last_run association
      test_obj = test.reload
      version = prompt_version
      prompt = version.prompt

      # 1) Update the test run row on the Test#show page
      broadcast_replace(
        stream: "prompt_test_#{test.id}",
        target: "test_run_row_#{id}",
        partial: "prompt_tracker/testing/test_runs/prompt_versions/row",
        locals: { run: self }
      )

      # 2) Update the status card on Test#show page (pass rate, counts, etc.)
      broadcast_replace(
        stream: "prompt_test_#{test.id}",
        target: "test_status_card",
        partial: "prompt_tracker/testing/prompt_tests/test_status_card",
        locals: { test: test_obj }
      )

      # 3) Update the test row on the tests index page (shows last_run status)
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_row_#{test_obj.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_row",
        locals: { test: test_obj, prompt: prompt, version: version }
      )

      # 3b) Update the individual test run row on the prompt version page
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_run_row_#{id}",
        partial: "prompt_tracker/testing/test_runs/prompt_versions/row",
        locals: { run: self }
      )

      # 4) Update the accordion content (preserves open/closed state)
      broadcast_replace(
        stream: "prompt_version_#{version.id}",
        target: "test-runs-content-#{test_obj.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_runs_accordion_content",
        locals: { test: test_obj, prompt: prompt, version: version }
      )

      # 5) Update the modals container to include updated evaluation modals
      all_tests = version.tests.includes(:test_runs).order(created_at: :desc)
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
