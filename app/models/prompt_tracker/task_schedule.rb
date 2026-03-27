# frozen_string_literal: true

module PromptTracker
  # Manages scheduling for task agents.
  #
  # TaskSchedules define when and how often task agents should run:
  # - Cron-based scheduling (e.g., "0 9 * * *" for daily at 9am)
  # - Interval-based scheduling (e.g., every 6 hours)
  # - Timezone support
  # - Enable/disable functionality
  #
  # @example Create a daily schedule
  #   TaskSchedule.create!(
  #     deployed_agent: task_agent,
  #     schedule_type: "cron",
  #     cron_expression: "0 9 * * *",
  #     timezone: "America/New_York"
  #   )
  #
  # @example Create an interval schedule
  #   TaskSchedule.create!(
  #     deployed_agent: task_agent,
  #     schedule_type: "interval",
  #     interval_value: 6,
  #     interval_unit: "hours"
  #   )
  #
  class TaskSchedule < ApplicationRecord
    # Schedule type enum
    enum schedule_type: {
      cron: "cron",
      interval: "interval"
    }, _prefix: true

    # Interval unit enum
    enum interval_unit: {
      minutes: "minutes",
      hours: "hours",
      days: "days",
      weeks: "weeks"
    }, _prefix: true, _default: nil

    # Associations
    belongs_to :deployed_agent,
               class_name: "PromptTracker::DeployedAgent",
               inverse_of: :task_schedules

    # Validations
    validates :schedule_type, presence: true
    validates :timezone, presence: true

    # Cron-specific validations
    validates :cron_expression,
              presence: true,
              if: :schedule_type_cron?

    # Interval-specific validations
    validates :interval_value,
              presence: true,
              numericality: { greater_than: 0 },
              if: :schedule_type_interval?
    validates :interval_unit,
              presence: true,
              if: :schedule_type_interval?

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :due, -> { enabled.where("next_run_at <= ?", Time.current) }

    # Callbacks
    before_create :calculate_next_run

    # Enable the schedule
    def enable!
      update!(enabled: true)
      calculate_next_run
      save!
    end

    # Disable the schedule
    def disable!
      update!(enabled: false)
    end

    # Check if schedule is overdue
    # @return [Boolean]
    def overdue?
      enabled? && next_run_at.present? && next_run_at < Time.current
    end

    # Record that a run occurred
    def record_run!
      update!(
        last_run_at: Time.current,
        run_count: run_count + 1
      )
      calculate_next_run
      save!
    end

    # Calculate the next run time based on schedule type
    def calculate_next_run
      return if next_run_at.present? # Don't override if already set

      self.next_run_at = case schedule_type
      when "cron"
                           calculate_next_run_from_cron
      when "interval"
                           calculate_next_run_from_interval
      end
    end

    private

    # Calculate next run time from cron expression
    # @return [Time]
    def calculate_next_run_from_cron
      return nil unless cron_expression.present?

      # For Phase 1, we'll use a simple implementation
      # In Phase 3, we'll integrate the fugit gem for proper cron parsing
      # For now, just schedule 1 hour from now as a placeholder
      Time.current + 1.hour
    end

    # Calculate next run time from interval
    # @return [Time]
    def calculate_next_run_from_interval
      return nil unless interval_value.present? && interval_unit.present?

      base_time = last_run_at || Time.current
      base_time + interval_value.send(interval_unit)
    end
  end
end
