# frozen_string_literal: true

FactoryBot.define do
  factory :task_schedule, class: "PromptTracker::TaskSchedule" do
    association :deployed_agent, factory: [ :deployed_agent, :task_agent ], strategy: :create
    schedule_type { "interval" }
    enabled { true }
    timezone { "UTC" }
    run_at_time { "09:00" }

    # Interval-based schedule (default)
    interval_value { 6 }
    interval_unit { "hours" }

    trait :hourly do
      schedule_type { "interval" }
      interval_value { 1 }
      interval_unit { "hours" }
    end

    trait :daily do
      schedule_type { "interval" }
      interval_value { 1 }
      interval_unit { "days" }
    end

    trait :weekly do
      schedule_type { "interval" }
      interval_value { 1 }
      interval_unit { "weeks" }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_history do
      last_run_at { 6.hours.ago }
      run_count { 42 }
      next_run_at { 10.minutes.from_now }
    end

    trait :overdue do
      enabled { true }
      next_run_at { 1.hour.ago }
    end
  end
end
