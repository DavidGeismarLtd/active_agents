# frozen_string_literal: true

module PromptTracker
  # Represents a single execution of a task agent.
  #
  # TaskRuns track the lifecycle of autonomous task execution, including:
  # - Status progression (queued → running → completed/failed)
  # - All LLM calls and function executions
  # - Execution statistics (iterations, cost, duration)
  # - Output and error information
  #
  # @example Create and track a task run
  #   task_run = TaskRun.create!(
  #     deployed_agent: task_agent,
  #     status: "queued",
  #     trigger_type: "manual",
  #     variables_used: { source_url: "https://example.com" }
  #   )
  #   task_run.start!
  #   # ... execute task ...
  #   task_run.complete!(output: "Successfully processed 23 items")
  #
  class TaskRun < ApplicationRecord
    # Status enum
    enum status: {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      cancelled: "cancelled"
    }, _prefix: true

    # Trigger type enum
    enum trigger_type: {
      scheduled: "scheduled",
      manual: "manual",
      api: "api"
    }, _prefix: true

    # Associations
    belongs_to :deployed_agent,
               class_name: "PromptTracker::DeployedAgent",
               inverse_of: :task_runs

    has_many :llm_responses,
             class_name: "PromptTracker::LlmResponse",
             dependent: :nullify,
             inverse_of: :task_run

    has_many :function_executions,
             class_name: "PromptTracker::FunctionExecution",
             dependent: :nullify,
             inverse_of: :task_run

    # Validations
    validates :status, presence: true
    validates :trigger_type, presence: true

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :for_agent, ->(agent) { where(deployed_agent: agent) }
    scope :successful, -> { where(status: "completed") }
    scope :failed_runs, -> { where(status: "failed") }
    scope :in_progress, -> { where(status: [ "queued", "running" ]) }

    # Start the task run
    def start!
      update!(
        status: "running",
        started_at: Time.current
      )
    end

    # Mark task run as completed
    # @param output [String] summary of task output
    def complete!(output: nil)
      update!(
        status: "completed",
        completed_at: Time.current,
        output_summary: output
      )
    end

    # Mark task run as failed
    # @param error [String] error message
    def fail!(error:)
      update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error
      )
    end

    # Cancel the task run
    def cancel!
      update!(
        status: "cancelled",
        completed_at: Time.current
      )
    end

    # Calculate duration in seconds
    # @return [Float, nil] duration in seconds, or nil if not started
    def duration
      return nil unless started_at
      end_time = completed_at || Time.current
      end_time - started_at
    end

    # Check if task run is finished
    # @return [Boolean]
    def finished?
      status_completed? || status_failed? || status_cancelled?
    end

    # Check if task run was successful
    # @return [Boolean]
    def successful?
      status_completed?
    end

    # Update execution statistics from tracked records
    def update_stats!
      update!(
        llm_calls_count: llm_responses.count,
        function_calls_count: function_executions.count,
        total_cost_usd: llm_responses.sum(:cost_usd)
      )
    end

    # Increment iteration count
    def increment_iteration!
      increment!(:iterations_count)
    end
  end
end
