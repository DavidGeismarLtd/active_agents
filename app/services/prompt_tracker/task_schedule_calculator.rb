# frozen_string_literal: true

module PromptTracker
  # Calculates next run time for task schedules
  #
  # Supports simple interval schedules (every N minutes/hours/days/weeks/months)
  #
  # @example Calculate next run for interval schedule
  #   calculator = TaskScheduleCalculator.new(schedule)
  #   next_time = calculator.next_run_time
  #
  class TaskScheduleCalculator
    attr_reader :schedule

    def initialize(schedule)
      @schedule = schedule
    end

    # Calculate the next run time based on schedule type
    # @return [Time] Next run time in UTC
    def next_run_time
      raise ArgumentError, "Unsupported schedule type: #{schedule.schedule_type}" unless schedule.schedule_type == "interval"

      calculate_from_interval
    end

    private

    # Calculate next run time from interval
    # @return [Time] Next run time in UTC
    def calculate_from_interval
      return nil if schedule.interval_value.blank? || schedule.interval_unit.blank?

      tz = ActiveSupport::TimeZone[schedule.timezone]
      raise ArgumentError, "Unknown timezone: #{schedule.timezone}" if tz.nil?

      base_time_utc = schedule.next_run_at || schedule.last_run_at || Time.current
      base_local = base_time_utc.in_time_zone(tz)

      next_local = case schedule.interval_unit
      when "minutes"
        base_local + schedule.interval_value.minutes
      when "hours"
        base_local + schedule.interval_value.hours
      when "days"
        base_local + schedule.interval_value.days
      when "weeks"
        base_local + schedule.interval_value.weeks
      when "months"
        base_local.advance(months: schedule.interval_value)
      else
        raise ArgumentError, "Unknown interval unit: #{schedule.interval_unit}"
      end

      next_local.utc
    end
  end
end
