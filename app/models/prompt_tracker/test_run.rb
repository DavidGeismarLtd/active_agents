# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_test_runs
#
#  id                       :bigint           not null, primary key
#  test_id                  :bigint           not null
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
#  output_data              :jsonb            (unified output for all test types)
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
  # - output_data with unified format for all test types
  #
  # @example Access test run results
  #   run = TestRun.last
  #   puts "Status: #{run.status}"
  #   puts "Passed: #{run.passed?}"
  #   puts "Evaluators: #{run.passed_evaluators}/#{run.total_evaluators}"
  #   puts "Time: #{run.execution_time_ms}ms"
  #
  # @example Access output data
  #   puts "Rendered prompt: #{run.rendered_prompt}"
  #   puts "Response: #{run.response_text}"
  #   run.output_messages.each do |message|
  #     puts "#{message['role']}: #{message['content']}"
  #   end
  #
  class TestRun < ApplicationRecord
    self.table_name = "prompt_tracker_test_runs"

    # Associations
    belongs_to :test,
               class_name: "PromptTracker::Test",
               foreign_key: :test_id,
               touch: true

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
    after_update_commit :broadcast_status_change, if: :saved_change_to_status?

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

    # =========================================================================
    # Output Data Accessors
    # Unified access to test output regardless of test type (single-turn or multi-turn)
    # =========================================================================

    # Get all output messages (works for single-turn and multi-turn)
    #
    # @return [Array<Hash>] array of message hashes with 'role' and 'content' keys
    def output_messages
      output_data&.dig("messages") || []
    end

    # Get the rendered prompt sent to the LLM
    #
    # @return [String, nil] the rendered prompt
    def rendered_prompt
      output_data&.dig("rendered_prompt")
    end

    # Get the final response text (last assistant message)
    #
    # @return [String, nil] the response text
    def response_text
      output_messages.select { |m| m["role"] == "assistant" }.last&.dig("content")
    end

    # Check if this is a multi-turn conversation
    #
    # @return [Boolean] true if more than one assistant message
    def multi_turn?
      output_messages.count { |m| m["role"] == "assistant" } > 1
    end

    # Get the model used for this test run
    #
    # @return [String, nil] the model name
    def model
      output_data&.dig("model")
    end

    # Get the provider used for this test run
    #
    # @return [String, nil] the provider name
    def provider
      output_data&.dig("provider")
    end

    # Get token usage information
    #
    # @return [Hash] token usage with prompt_tokens, completion_tokens, total_tokens
    def tokens
      output_data&.dig("tokens") || {}
    end

    # Get response time in milliseconds
    #
    # @return [Integer, nil] response time
    def llm_response_time_ms
      output_data&.dig("response_time_ms")
    end

    # Get total number of conversation turns
    #
    # @return [Integer] number of turns
    def total_turns
      output_data&.dig("total_turns") || output_messages.count { |m| m["role"] == "assistant" }
    end

    # Get tools used in this test run
    #
    # @return [Array<String>] array of tool names
    def tools_used
      output_data&.dig("tools_used") || []
    end

    # Get tool outputs from this test run
    #
    # @return [Hash] tool outputs keyed by tool name
    def tool_outputs
      output_data&.dig("tool_outputs") || {}
    end

    private

    def broadcast_status_change
      testable = test.testable
      stream_name = testable.testable_stream_name

      # Render with ApplicationController to include helpers
      # Use test.test_run_row_partial to handle conversational vs single-turn mode
      test_run_html = PromptTracker::ApplicationController.render(
        partial: test.test_run_row_partial,
        locals: { run: self }
      )

      test_row_html = PromptTracker::ApplicationController.render(
        partial: testable.test_row_partial,
        locals: testable.test_row_locals(test)
      )

      # Update the accordion content (test runs table)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test_run_#{id}",
        html: test_run_html
      )

      # Update the test row in the tests table (status, last run, run count)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test_row_#{test.id}",
        html: test_row_html
      )
    end
  end
end
