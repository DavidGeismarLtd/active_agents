# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskScheduleCalculator, type: :service do
  let(:task_agent) { create(:deployed_agent, :task_agent) }

  describe "#next_run_time" do
    context "with cron schedule" do
      it "calculates next run time from cron expression" do
        # Daily at 9am
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "cron",
                         cron_expression: "0 9 * * *",
                         timezone: "UTC")

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_a(Time)
        expect(next_time.hour).to eq(9)
        expect(next_time.min).to eq(0)
        expect(next_time).to be > Time.current
      end

      it "handles timezone correctly" do
        # Daily at 9am EST
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "cron",
                         cron_expression: "0 9 * * *",
                         timezone: "America/New_York")

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        # Result should be in UTC
        expect(next_time).to be_a(Time)
        expect(next_time.zone).to eq("UTC")

        # Convert to EST to check - should be 9am in EST
        next_time_est = next_time.in_time_zone("America/New_York")
        expect(next_time_est.hour).to eq(9)
        expect(next_time_est.min).to eq(0)
      end

      it "handles every 5 minutes cron" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "cron",
                         cron_expression: "*/5 * * * *",
                         timezone: "UTC")

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_a(Time)
        expect(next_time.min % 5).to eq(0)
        expect(next_time).to be > Time.current
        expect(next_time).to be < 6.minutes.from_now
      end

      it "raises error for invalid cron expression" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "cron",
                         cron_expression: "invalid cron",
                         timezone: "UTC")

        calculator = described_class.new(schedule)

        expect { calculator.next_run_time }.to raise_error(ArgumentError, /Invalid cron expression/)
      end
    end

    context "with interval schedule" do
      it "calculates next run time for minutes interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 30,
                         interval_unit: "minutes",
                         last_run_at: 10.minutes.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(20.minutes.from_now)
      end

      it "calculates next run time for hours interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 2,
                         interval_unit: "hours",
                         last_run_at: 1.hour.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(1.hour.from_now)
      end

      it "calculates next run time for days interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 1,
                         interval_unit: "days",
                         last_run_at: 12.hours.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(12.hours.from_now)
      end

      it "calculates next run time for weeks interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 1,
                         interval_unit: "weeks",
                         last_run_at: 3.days.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(4.days.from_now)
      end

      it "uses current time if last_run_at is nil" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 1,
                         interval_unit: "hours",
                         last_run_at: nil)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(1.hour.from_now)
      end

      it "raises error for unknown interval unit" do
        # Create a valid schedule first
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "interval",
                         interval_value: 1,
                         interval_unit: "minutes")

        # Stub the interval_unit method to return an invalid value
        allow(schedule).to receive(:interval_unit).and_return("fortnights")

        calculator = described_class.new(schedule)

        expect { calculator.next_run_time }.to raise_error(ArgumentError, /Unknown interval unit/)
      end
    end

    context "with unknown schedule type" do
      it "raises error" do
        # Create a valid schedule first, then manually set invalid type to bypass validation
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         schedule_type: "cron",
                         cron_expression: "0 9 * * *")

        # Manually update to invalid value
        schedule.update_column(:schedule_type, "unknown")

        calculator = described_class.new(schedule)

        expect { calculator.next_run_time }.to raise_error(ArgumentError, /Unknown schedule type/)
      end
    end
  end
end
