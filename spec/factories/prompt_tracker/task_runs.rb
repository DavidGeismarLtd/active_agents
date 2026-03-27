# frozen_string_literal: true

FactoryBot.define do
  factory :task_run, class: "PromptTracker::TaskRun" do
    association :deployed_agent, factory: [ :deployed_agent, :task_agent ], strategy: :create
    status { "queued" }
    trigger_type { "manual" }

    variables_used do
      {
        source_url: "https://example.com/api/data"
      }
    end

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
      iterations_count { 1 }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
      iterations_count { 3 }
      llm_calls_count { 3 }
      function_calls_count { 5 }
      total_cost_usd { 0.05 }
      output_summary { "Successfully processed 23 items" }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
      iterations_count { 2 }
      llm_calls_count { 2 }
      function_calls_count { 1 }
      total_cost_usd { 0.02 }
      error_message { "Failed to fetch data: Connection timeout" }
    end

    trait :scheduled do
      trigger_type { "scheduled" }
    end

    trait :api_triggered do
      trigger_type { "api" }
    end

    trait :with_llm_responses do
      after(:create) do |task_run|
        create_list(:llm_response, 3, task_run: task_run, deployed_agent: task_run.deployed_agent)
      end
    end

    trait :with_function_executions do
      after(:create) do |task_run|
        create_list(:function_execution, 5, task_run: task_run, deployed_agent: task_run.deployed_agent)
      end
    end
  end
end
