# frozen_string_literal: true

module PromptTracker
  # Calculates next run time for task schedules
  #
  # Supports:
  # - Cron expressions (using fugit gem)
  # - Simple intervals (every N minutes/hours/days/weeks)
  #
  # @example Calculate next run for cron schedule
  #   calculator = TaskScheduleCalculator.new(schedule)
  #   next_time = calculator.next_run_time
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
      case schedule.schedule_type
      when "cron"
        calculate_from_cron
      when "interval"
        calculate_from_interval
      else
        raise ArgumentError, "Unknown schedule type: #{schedule.schedule_type}"
      end
    end

    private

    # Calculate next run time from cron expression
    # @return [Time] Next run time in UTC
    def calculate_from_cron
      return nil if schedule.cron_expression.blank?

      # Parse cron expression with timezone
      tz_string = schedule.timezone || "UTC"
      cron_string = "#{schedule.cron_expression} #{tz_string}"
      cron = Fugit::Cron.parse(cron_string)
      raise ArgumentError, "Invalid cron expression: #{schedule.cron_expression}" unless cron

      # Calculate next occurrence from current time
      next_time = cron.next_time(Time.current)

      # Convert the EtOrbi::EoTime to Ruby Time in UTC
      Time.at(next_time.to_i).utc
    end

    # Calculate next run time from interval
    # @return [Time] Next run time in UTC
    def calculate_from_interval
      return nil if schedule.interval_value.blank? || schedule.interval_unit.blank?

      # Calculate interval in seconds
      interval_seconds = case schedule.interval_unit
      when "minutes"
        schedule.interval_value.minutes
      when "hours"
        schedule.interval_value.hours
      when "days"
        schedule.interval_value.days
      when "weeks"
        schedule.interval_value.weeks
      else
        raise ArgumentError, "Unknown interval unit: #{schedule.interval_unit}"
      end

      # If last_run_at exists, calculate from that, otherwise from now
      base_time = schedule.last_run_at || Time.current
      base_time + interval_seconds
    end
  end
end
