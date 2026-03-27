# frozen_string_literal: true

FactoryBot.define do
  factory :deployed_agent, class: "PromptTracker::DeployedAgent" do
    association :prompt_version, factory: :prompt_version, strategy: :create
    sequence(:name) { |n| "Deployed Agent #{n}" }
    status { "active" }
    created_by { "test@example.com" }

    deployment_config do
      {
        auth: { type: "api_key" },
        rate_limit: { requests_per_minute: 60 },
        conversation_ttl: 3600,
        allowed_origins: []
      }
    end

    # Slug is auto-generated from name in before_validation callback
    # deployed_at is auto-set in before_validation callback
    # api_key_digest is auto-generated in after_create callback

    trait :paused do
      status { "paused" }
      paused_at { 1.hour.ago }
    end

    trait :with_error do
      status { "error" }
      error_message { "Failed to process request: Connection timeout" }
    end

    trait :with_functions do
      after(:create) do |agent|
        functions = create_list(:function_definition, 3)
        agent.function_definitions << functions
      end
    end

    trait :with_conversations do
      after(:create) do |agent|
        create_list(:agent_conversation, 5, deployed_agent: agent)
      end
    end

    trait :with_high_traffic do
      request_count { 10_000 }
      last_request_at { 5.minutes.ago }
    end

    trait :with_custom_config do
      deployment_config do
        {
          auth: { type: "api_key" },
          rate_limit: { requests_per_minute: 1000 },
          conversation_ttl: 7200,
          allowed_origins: [ "https://example.com", "https://app.example.com" ]
        }
      end
    end

    # Task agent traits
    trait :task_agent do
      agent_type { "task" }
      deployment_config { {} } # Task agents don't use deployment_config

      task_config do
        {
          initial_prompt: "Fetch data from {{source_url}} and process it",
          variables: {
            source_url: "https://example.com/api/data"
          },
          execution: {
            max_iterations: 5,
            timeout_seconds: 3600,
            retry_on_failure: false
          },
          completion_criteria: {
            type: "auto"
          }
        }
      end
    end

    trait :with_task_runs do
      after(:create) do |agent|
        create_list(:task_run, 3, deployed_agent: agent)
      end
    end

    trait :with_schedule do
      after(:create) do |agent|
        create(:task_schedule, deployed_agent: agent)
      end
    end
  end
end
