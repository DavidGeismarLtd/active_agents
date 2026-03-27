# frozen_string_literal: true

module PromptTracker
  # Background job that runs periodically to check for due task schedules
  #
  # This job should be run every minute via a cron job (e.g., using whenever gem or Heroku Scheduler)
  #
  # It:
  # 1. Finds all enabled schedules where next_run_at <= current time
  # 2. Enqueues ExecuteTaskAgentJob for each due schedule
  # 3. Updates the schedule's last_run_at and next_run_at
  #
  # @example Run manually (for testing)
  #   ScheduledTaskRunnerJob.perform_now
  #
  # @example Schedule with whenever gem
  #   # config/schedule.rb
  #   every 1.minute do
  #     runner "PromptTracker::ScheduledTaskRunnerJob.perform_later"
  #   end
  #
  class ScheduledTaskRunnerJob < ApplicationJob
    queue_as :default

    def perform
      Rails.logger.info "[ScheduledTaskRunnerJob] Checking for due task schedules..."

      # Find all enabled schedules that are due
      due_schedules = TaskSchedule
        .enabled
        .where("next_run_at <= ?", Time.current)
        .includes(:deployed_agent)

      if due_schedules.empty?
        Rails.logger.info "[ScheduledTaskRunnerJob] No due schedules found"
        return
      end

      Rails.logger.info "[ScheduledTaskRunnerJob] Found #{due_schedules.count} due schedule(s)"

      due_schedules.each do |schedule|
        process_schedule(schedule)
      end

      Rails.logger.info "[ScheduledTaskRunnerJob] Finished processing due schedules"
    end

    private

    def process_schedule(schedule)
      task_agent = schedule.deployed_agent

      Rails.logger.info "[ScheduledTaskRunnerJob] Processing schedule for agent: #{task_agent.name}"

      # Enqueue the task execution
      ExecuteTaskAgentJob.perform_later(
        task_agent.id,
        nil, # No task_run_id - let the job create one
        trigger_type: "scheduled"
      )

      # Update schedule
      schedule.update!(
        last_run_at: Time.current,
        next_run_at: calculate_next_run(schedule)
      )

      Rails.logger.info "[ScheduledTaskRunnerJob] Enqueued task for agent: #{task_agent.name}, next run: #{schedule.next_run_at}"
    rescue StandardError => e
      Rails.logger.error "[ScheduledTaskRunnerJob] Failed to process schedule #{schedule.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Continue processing other schedules
    end

    def calculate_next_run(schedule)
      calculator = TaskScheduleCalculator.new(schedule)
      calculator.next_run_time
    rescue StandardError => e
      Rails.logger.error "[ScheduledTaskRunnerJob] Failed to calculate next run for schedule #{schedule.id}: #{e.message}"
      # Return a default (1 hour from now) to prevent the schedule from getting stuck
      1.hour.from_now
    end
  end
end
