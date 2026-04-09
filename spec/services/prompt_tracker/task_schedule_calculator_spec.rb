# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskScheduleCalculator, type: :service do
  let(:task_agent) { create(:deployed_agent, :task_agent) }

  describe "#next_run_time" do
    context "with interval schedule" do
      it "calculates next run time for minutes interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         interval_value: 30,
                         interval_unit: "minutes",
                         next_run_at: 10.minutes.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(20.minutes.from_now)
      end

      it "calculates next run time for hours interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         interval_value: 2,
                         interval_unit: "hours",
                         next_run_at: 1.hour.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(1.hour.from_now)
      end

      it "calculates next run time for days interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         interval_value: 1,
                         interval_unit: "days",
                         next_run_at: 12.hours.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(12.hours.from_now)
      end

      it "calculates next run time for weeks interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         interval_value: 1,
                         interval_unit: "weeks",
                         next_run_at: 3.days.ago)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(4.days.from_now)
      end

      it "calculates next run time for months interval" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         interval_value: 1,
                         interval_unit: "months",
                         next_run_at: Time.current)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(1.month.from_now)
      end

      it "uses current time if next_run_at and last_run_at are nil" do
        schedule = build(:task_schedule,
                        deployed_agent: task_agent,
                        interval_value: 1,
                        interval_unit: "hours",
                        last_run_at: nil,
                        next_run_at: nil)

        calculator = described_class.new(schedule)
        next_time = calculator.next_run_time

        expect(next_time).to be_within(1.second).of(1.hour.from_now)
      end

      it "raises error for unknown interval unit" do
        # Create a valid schedule first
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
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
          schedule = build(:task_schedule, deployed_agent: task_agent)
          allow(schedule).to receive(:schedule_type).and_return("unknown")

        calculator = described_class.new(schedule)

          expect { calculator.next_run_time }.to raise_error(ArgumentError, /Unsupported schedule type/)
      end
    end
  end
end
