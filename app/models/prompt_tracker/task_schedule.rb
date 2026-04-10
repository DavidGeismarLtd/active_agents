# frozen_string_literal: true

module PromptTracker
  # Manages scheduling for task agents.
  #
  # TaskSchedules define when and how often task agents should run:
  # - Interval-based scheduling (e.g., every 6 hours)
  # - Timezone support
  # - Enable/disable functionality
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
    enum :schedule_type, {
      interval: "interval"
    }, prefix: true

    # Interval unit enum
    enum :interval_unit, {
      minutes: "minutes",
      hours: "hours",
      days: "days",
      weeks: "weeks",
      months: "months"
    }, prefix: true, default: nil

    INTERVAL_PRESETS = {
      "every_1_hour" => { value: 1, unit: "hours" },
      "every_6_hours" => { value: 6, unit: "hours" },
      "every_24_hours" => { value: 24, unit: "hours" },
      "every_7_days" => { value: 7, unit: "days" },
      "every_1_month" => { value: 1, unit: "months" }
    }.freeze

    attr_writer :interval_preset

    # Associations
    belongs_to :deployed_agent,
               class_name: "PromptTracker::DeployedAgent",
               inverse_of: :task_schedules

    # Validations
    validates :schedule_type, presence: true
    validates :timezone, presence: true
    validates :run_at_time, presence: true

    # Interval-specific validations
    validates :interval_value,
              presence: true,
              numericality: { greater_than: 0 },
              if: :schedule_type_interval?
    validates :interval_unit,
              presence: true,
              if: :schedule_type_interval?

    validate :run_at_time_format

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :due, -> { enabled.where("next_run_at <= ?", Time.current) }

    # Callbacks
    before_validation :set_interval_defaults
    before_validation :apply_interval_preset
    before_create :set_initial_next_run

    # Enable the schedule
    def enable!
      update!(enabled: true)
      update!(next_run_at: initial_next_run_at)
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

      self.next_run_at = nil
      update!(next_run_at: TaskScheduleCalculator.new(self).next_run_time)
    end

    def interval_preset
      @interval_preset || self.class.interval_preset_for(interval_value: interval_value, interval_unit: interval_unit)
    end

    private

    def set_interval_defaults
      self.schedule_type ||= "interval"
    end

    def apply_interval_preset
      return if interval_preset.blank?

      preset = INTERVAL_PRESETS[interval_preset]
      return if preset.nil?

      self.interval_value = preset[:value]
      self.interval_unit = preset[:unit]
    end

    def set_initial_next_run
      self.next_run_at ||= initial_next_run_at
    end

    def initial_next_run_at
      tz = ActiveSupport::TimeZone[timezone]
      raise ArgumentError, "Unknown timezone: #{timezone}" if tz.nil?

      hour, minute = run_at_time.split(":").map(&:to_i)
      now_local = Time.current.in_time_zone(tz)
      candidate = now_local.change(hour: hour, min: minute, sec: 0)
      candidate += 1.day if candidate <= now_local

      candidate.utc
    end

    def run_at_time_format
      return if run_at_time.blank?

      unless run_at_time.match?(/\A[0-2][0-9]:[0-5][0-9]\z/)
        errors.add(:run_at_time, "must be in HH:MM format")
        return
      end

      hour, minute = run_at_time.split(":").map(&:to_i)
      if hour > 23 || minute > 59
        errors.add(:run_at_time, "must be a valid time")
      end
    end

    def self.interval_preset_for(interval_value:, interval_unit:)
      match = INTERVAL_PRESETS.find { |_k, v| v[:value] == interval_value && v[:unit] == interval_unit }
      match&.first
    end
  end
end
