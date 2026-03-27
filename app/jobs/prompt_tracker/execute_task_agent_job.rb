# frozen_string_literal: true

module PromptTracker
  # Background job for executing task agents.
  #
  # This job:
  # 1. Loads the task agent and task run (or creates one if task_run_id is nil)
  # 2. Calls TaskAgentRuntimeService to execute the task
  # 3. Handles errors and updates task run status
  #
  # @example Enqueue with existing task run
  #   ExecuteTaskAgentJob.perform_later(task_agent.id, task_run.id)
  #
  # @example Enqueue for scheduled execution (creates task run)
  #   ExecuteTaskAgentJob.perform_later(task_agent.id, nil, trigger_type: "scheduled")
  #
  class ExecuteTaskAgentJob < ApplicationJob
    queue_as :default

    # Execute the task agent
    #
    # @param task_agent_id [Integer] ID of the deployed agent (task type)
    # @param task_run_id [Integer, nil] ID of the task run to execute (or nil to create one)
    # @param options [Hash] Additional options
    # @option options [String] :trigger_type Type of trigger (scheduled, manual, api) - only used if task_run_id is nil
    # @option options [Hash] :variables Variables to pass to the task agent
    #
    def perform(task_agent_id, task_run_id = nil, options = {})
      task_agent = DeployedAgent.find(task_agent_id)

      unless task_agent.agent_type_task?
        Rails.logger.error "[ExecuteTaskAgentJob] Agent #{task_agent_id} is not a task agent"
        return
      end

      # Get or create task run
      task_run = if task_run_id
        TaskRun.find(task_run_id)
      else
        trigger_type = options[:trigger_type] || "manual"
        TaskRun.create!(
          deployed_agent: task_agent,
          trigger_type: trigger_type,
          status: "queued"
        )
      end

      # Set up dedicated logger for this task run
      setup_task_logger(task_run.id)

      log_task "[ExecuteTaskAgentJob] =========================================="
      log_task "[ExecuteTaskAgentJob] Starting Task Run ##{task_run.id}"
      log_task "[ExecuteTaskAgentJob] Agent: #{task_agent.name}"
      log_task "[ExecuteTaskAgentJob] Trigger: #{task_run.trigger_type}"
      log_task "[ExecuteTaskAgentJob] Metadata: #{task_run.metadata.inspect}"
      log_task "[ExecuteTaskAgentJob] Variables: #{options[:variables].inspect}"
      log_task "[ExecuteTaskAgentJob] =========================================="

      Rails.logger.info "[ExecuteTaskAgentJob] Executing task agent #{task_agent.name} (run ##{task_run.id})"

      # Execute the task
      result = TaskAgentRuntimeService.call(
        task_agent: task_agent,
        task_run: task_run,
        variables: options[:variables],
        logger: @task_logger
      )

      if result[:success]
        log_task "[ExecuteTaskAgentJob] ✅ Task run #{task_run.id} completed successfully"
        Rails.logger.info "[ExecuteTaskAgentJob] Task run #{task_run.id} completed successfully"
      else
        log_task "[ExecuteTaskAgentJob] ❌ Task run #{task_run.id} failed: #{result[:error]}"
        Rails.logger.error "[ExecuteTaskAgentJob] Task run #{task_run.id} failed: #{result[:error]}"
      end

      log_task "[ExecuteTaskAgentJob] =========================================="
      log_task "[ExecuteTaskAgentJob] Task Run ##{task_run.id} Complete"
      log_task "[ExecuteTaskAgentJob] =========================================="
    rescue StandardError => e
      log_task "[ExecuteTaskAgentJob] 💥 EXCEPTION: #{e.class.name}"
      log_task "[ExecuteTaskAgentJob] 💥 Message: #{e.message}"
      log_task "[ExecuteTaskAgentJob] 💥 Backtrace:"
      e.backtrace.first(30).each do |line|
        log_task "[ExecuteTaskAgentJob] 💥   #{line}"
      end

      Rails.logger.error "[ExecuteTaskAgentJob] Task run failed with exception: #{e.message}"
      Rails.logger.error e.backtrace.first(30).join("\n")

      # Mark task run as failed if it exists and isn't already in a terminal state
      if task_run && !task_run.finished?
        begin
          task_run.fail!(error: e.message)
        rescue StandardError => fail_error
          log_task "[ExecuteTaskAgentJob] ⚠️  Failed to mark task as failed: #{fail_error.message}"
          Rails.logger.error "[ExecuteTaskAgentJob] Failed to mark task as failed: #{fail_error.message}"
          # Try to update status directly without validation
          task_run.update_columns(
            status: "failed",
            error_message: e.message,
            completed_at: Time.current
          )
        end
      end

      # DO NOT re-raise - we want to handle errors gracefully without retries
      # The task run is already marked as failed, no need to retry
    ensure
      close_task_logger
    end

    private

    def setup_task_logger(task_run_id)
      log_dir = Rails.root.join("log", "task_executions")
      FileUtils.mkdir_p(log_dir)

      log_file = log_dir.join("task_run_#{task_run_id}.log")
      @task_logger = Logger.new(log_file)
      @task_logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity} -- #{msg}\n"
      end
    end

    def log_task(message)
      @task_logger&.info(message)
    end

    def close_task_logger
      @task_logger&.close
    end
  end
end
