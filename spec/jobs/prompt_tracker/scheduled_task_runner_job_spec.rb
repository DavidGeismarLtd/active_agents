# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ScheduledTaskRunnerJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:task_agent) { create(:deployed_agent, :task_agent) }

  describe "#perform" do
    context "with no due schedules" do
      it "does nothing" do
        # Create a schedule that's not due yet
        create(:task_schedule,
               deployed_agent: task_agent,
               enabled: true,
               next_run_at: 1.hour.from_now)

        expect(PromptTracker::ExecuteTaskAgentJob).not_to receive(:perform_later)

        described_class.perform_now
      end
    end

    context "with due schedules" do
      it "enqueues ExecuteTaskAgentJob for each due schedule" do
        # Create 2 due schedules
        schedule1 = create(:task_schedule,
                          deployed_agent: task_agent,
                          enabled: true,
                          next_run_at: 5.minutes.ago,
                          schedule_type: "interval",
                          interval_value: 1,
                          interval_unit: "hours")

        task_agent2 = create(:deployed_agent, :task_agent)
        schedule2 = create(:task_schedule,
                          deployed_agent: task_agent2,
                          enabled: true,
                          next_run_at: 10.minutes.ago,
                          schedule_type: "interval",
                          interval_value: 30,
                          interval_unit: "minutes")

        expect(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later).with(
          task_agent.id,
          nil,
          trigger_type: "scheduled"
        )

        expect(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later).with(
          task_agent2.id,
          nil,
          trigger_type: "scheduled"
        )

        described_class.perform_now
      end

      it "updates last_run_at and next_run_at for each schedule" do
        schedule = create(:task_schedule,
                         deployed_agent: task_agent,
                         enabled: true,
                         next_run_at: 5.minutes.ago,
                         last_run_at: nil, # No previous run
                         schedule_type: "interval",
                         interval_value: 1,
                         interval_unit: "hours")

        allow(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later)

        travel_to Time.current do
          described_class.perform_now

          schedule.reload
          expect(schedule.last_run_at).to be_within(1.second).of(Time.current)
            # Next run should be 1 hour from the schedule's previous next_run_at (which was 5 minutes ago)
            expect(schedule.next_run_at).to be_within(1.second).of(55.minutes.from_now)
        end
      end
    end

    context "with disabled schedules" do
      it "skips disabled schedules" do
        create(:task_schedule,
               deployed_agent: task_agent,
               enabled: false,
               next_run_at: 5.minutes.ago)

        expect(PromptTracker::ExecuteTaskAgentJob).not_to receive(:perform_later)

        described_class.perform_now
      end
    end

    context "when processing a schedule fails" do
      it "continues processing other schedules" do
        # Create 2 due schedules
        schedule1 = create(:task_schedule,
                          deployed_agent: task_agent,
                          enabled: true,
                          next_run_at: 5.minutes.ago,
                          schedule_type: "interval",
                          interval_value: 1,
                          interval_unit: "hours")

        task_agent2 = create(:deployed_agent, :task_agent)
        schedule2 = create(:task_schedule,
                          deployed_agent: task_agent2,
                          enabled: true,
                          next_run_at: 10.minutes.ago,
                          schedule_type: "interval",
                          interval_value: 30,
                          interval_unit: "minutes")

        # Make the first one fail
        allow(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later).with(
          task_agent.id,
          nil,
          trigger_type: "scheduled"
        ).and_raise(StandardError, "Job enqueue failed")

        # Second one should still be processed
        expect(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later).with(
          task_agent2.id,
          nil,
          trigger_type: "scheduled"
        )

        # Should not raise error
        expect { described_class.perform_now }.not_to raise_error
      end
    end

      context "when next_run_at calculation fails" do
        it "sets next_run_at to 1 hour from now as fallback" do
          schedule = create(:task_schedule,
                           deployed_agent: task_agent,
                           enabled: true,
                           next_run_at: 5.minutes.ago,
                           interval_value: 1,
                           interval_unit: "hours")

          allow(PromptTracker::ExecuteTaskAgentJob).to receive(:perform_later)
          allow_any_instance_of(PromptTracker::TaskScheduleCalculator)
            .to receive(:next_run_time)
            .and_raise(StandardError, "calc failed")

          travel_to Time.current do
            described_class.perform_now

            schedule.reload
            expect(schedule.next_run_at).to be_within(1.second).of(1.hour.from_now)
          end
        end
      end
  end
end
