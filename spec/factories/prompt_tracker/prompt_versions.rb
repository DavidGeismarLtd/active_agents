# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_versions
#
#  created_at       :datetime         not null
#  created_by       :string
#  id               :bigint           not null, primary key
#  model_config     :jsonb
#  notes            :text
#  prompt_id        :bigint           not null
#  status           :string           default("draft"), not null
#  system_prompt    :text
#  user_prompt      :text             not null
#  updated_at       :datetime         not null
#  variables_schema :jsonb
#  version_number   :integer          not null
#
# Note: PromptVersion has evaluator_configs (polymorphic association).
# These are AUTO-EVALUATORS for MONITORING - they run automatically on tracked production calls.
# This is different from PromptTest's evaluator_configs, which are for testing.
FactoryBot.define do
  factory :prompt_version, class: "PromptTracker::PromptVersion" do
    association :prompt, factory: :prompt
    user_prompt { "Hello {{name}}, how can I help you today?" }
    system_prompt { nil }
    sequence(:version_number) { |n| n }
    status { "draft" }
    variables_schema do
      [
        { "name" => "name", "type" => "string", "required" => true }
      ]
    end
    model_config { {} }
    notes { "Test version" }

    trait :active do
      status { "active" }
    end

    trait :deprecated do
      status { "deprecated" }
    end

    trait :with_model_config do
      model_config do
        {
          "provider" => "openai",
          "api" => "chat_completions",
          "model" => "gpt-4",
          "temperature" => 0.7,
          "max_tokens" => 150
        }
      end
    end

    trait :with_chat_completions do
      model_config do
        {
          "provider" => "openai",
          "api" => "chat_completions",
          "model" => "gpt-4o",
          "temperature" => 0.7
        }
      end
    end

    trait :with_responses do
      model_config do
        {
          "provider" => "openai",
          "api" => "responses",
          "model" => "gpt-4o",
          "temperature" => 0.7,
          "tools" => [ "web_search" ]
        }
      end
    end

    trait :with_assistants do
      model_config do
        {
          "provider" => "openai",
          "api" => "assistants",
          "model" => "gpt-4o",
          "temperature" => 0.7
        }
      end
    end

    trait :with_anthropic do
      model_config do
        {
          "provider" => "anthropic",
          "api" => "messages",
          "model" => "claude-3-5-sonnet-20241022",
          "temperature" => 0.7
        }
      end
    end

    trait :with_llm_responses do
      after(:create) do |version|
        create_list(:llm_response, 5, prompt_version: version)
      end
    end
  end
end
