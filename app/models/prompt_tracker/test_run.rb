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

    # broadcast change only if status changes
    after_update_commit :broadcast_changes, if: :status_changed?

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

    def broadcast_changes
      # Reload test to get fresh associations
      test_obj = test.reload

      # Broadcast updates to the testable's show page (PromptVersion or Assistant)
      broadcast_to_testable_show_page

      # Broadcast updates specific to PromptVersion (if applicable)
      broadcast_to_prompt_version_modals if prompt_version_test?
    end

    # Broadcasts updates to the testable's show page
    # This works for both PromptVersion and Assistant (and any future testable types)
    def broadcast_to_testable_show_page
      test_obj = test
      testable = test_obj.testable
      stream_name = testable.testable_stream_name

      # Update the accordion content (test runs table)
      broadcast_replace(
        stream: stream_name,
        target: "test-runs-content-#{test_obj.id}",
        partial: "prompt_tracker/testing/tests/test_runs_accordion_content",
        locals: { test: test_obj }
      )

      # Update the test row in the tests table (status, last run, run count)
      broadcast_replace(
        stream: stream_name,
        target: "test_row_#{test_obj.id}",
        partial: testable.test_row_partial,
        locals: testable.test_row_locals(test_obj)
      )
    end

    # Broadcasts updates to PromptVersion-specific modals
    # This is only needed for PromptVersion because it has a special test_modals partial
    def broadcast_to_prompt_version_modals
      version = prompt_version
      prompt = version.prompt
      all_tests = version.tests.includes(:test_runs).order(created_at: :desc)

      broadcast_replace(
        stream: testable.testable_stream_name,
        target: "test-modals",
        partial: "prompt_tracker/testing/prompt_versions/test_modals",
        locals: { tests: all_tests, prompt: prompt, version: version }
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
