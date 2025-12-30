# frozen_string_literal: true

FactoryBot.define do
  factory :dataset, class: "PromptTracker::Dataset" do
    association :testable, factory: :prompt_version
    sequence(:name) { |n| "Dataset #{n}" }
    description { "A test dataset for validating prompts" }
    created_by { "test_user" }
    metadata { {} }

    # Schema is automatically copied from testable on create
    # But we can override it if needed
    transient do
      custom_schema { nil }
    end

    after(:build) do |dataset, evaluator|
      if evaluator.custom_schema
        dataset.schema = evaluator.custom_schema
      elsif dataset.schema.blank? && dataset.testable
        # Schema is set by the model's copy_schema_from_testable callback
        # But for factories, we can set it manually
        if dataset.testable.is_a?(PromptTracker::PromptVersion)
          dataset.schema = dataset.testable.variables_schema if dataset.testable.variables_schema.present?
        elsif dataset.testable.is_a?(PromptTracker::Openai::Assistant)
          dataset.schema = dataset.testable.variables_schema
        end
      end
    end

    # Trait for prompt version datasets
    trait :for_prompt_version do
      association :testable, factory: :prompt_version
    end

    # Trait for assistant datasets
    trait :for_assistant do
      association :testable, factory: :openai_assistant
      # Schema is automatically set from testable.variables_schema in after(:build) above
    end

    trait :with_rows do
      after(:create) do |dataset|
        create_list(:dataset_row, 3, dataset: dataset)
      end
    end

    trait :with_assistant_rows do
      after(:create) do |dataset|
        create(:dataset_row, dataset: dataset, row_data: {
          interlocutor_simulation_prompt: "You are a patient experiencing a severe headache. You're worried it might be a migraine. Be concerned and ask for advice.",
          max_turns: 3
        })
        create(:dataset_row, dataset: dataset, row_data: {
          interlocutor_simulation_prompt: "You are a person feeling anxious about an upcoming medical procedure. You want reassurance and information. Be nervous but cooperative.",
          max_turns: 5
        })
        create(:dataset_row, dataset: dataset, row_data: {
          interlocutor_simulation_prompt: "You are a patient who can't sleep at night due to stress. You're looking for non-medication solutions. Be tired and seeking practical advice.",
          max_turns: 4
        })
      end
    end

    trait :invalid_schema do
      after(:build) do |dataset|
        dataset.schema = [ { "name" => "wrong_var", "type" => "string" } ]
      end
    end
  end
end
