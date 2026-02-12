# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_datasets
#
#  id                 :bigint           not null, primary key
#  name               :string           not null
#  description        :text
#  schema             :jsonb            not null
#  created_by         :string
#  metadata           :jsonb            not null
#  dataset_type       :integer          default(0), not null  # 0=single_turn, 1=conversational
#  testable_type      :string
#  testable_id        :bigint
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
FactoryBot.define do
  factory :dataset, class: "PromptTracker::Dataset" do
    association :testable, factory: :prompt_version
    sequence(:name) { |n| "Dataset #{n}" }
    description { "A test dataset for validating prompts" }
    created_by { "test_user" }
    metadata { {} }
    dataset_type { :single_turn }

    # Schema is automatically copied from testable on create
    # But we can override it if needed
    transient do
      custom_schema { nil }
    end

    after(:build) do |dataset, evaluator|
      # Auto-detect dataset_type based on api type if not explicitly set
      # Assistants API uses conversational datasets by default
      if dataset.testable&.api_type == :openai_assistants && dataset.single_turn?
        dataset.dataset_type = :conversational
      end

      if evaluator.custom_schema
        dataset.schema = evaluator.custom_schema
      elsif dataset.schema.blank? && dataset.testable
        # Use required_schema which accounts for dataset_type
        dataset.schema = dataset.required_schema
      end
    end

    # Trait for prompt version datasets (single-turn by default)
    trait :for_prompt_version do
      association :testable, factory: :prompt_version
      dataset_type { :single_turn }
    end

    # Trait for assistant datasets (conversational by default)
    # Uses a prompt_version with assistants api config
    trait :for_assistant do
      association :testable, factory: [ :prompt_version, :with_assistants ]
      dataset_type { :conversational }
    end

    # Trait for single-turn datasets
    trait :single_turn do
      dataset_type { :single_turn }
    end

    # Trait for conversational datasets
    trait :conversational do
      dataset_type { :conversational }
    end

    trait :with_rows do
      after(:create) do |dataset|
        create_list(:dataset_row, 3, dataset: dataset)
      end
    end

    # Trait with conversational rows (requires conversational dataset_type)
    trait :with_conversational_rows do
      dataset_type { :conversational }
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

    # Legacy alias for backward compatibility
    trait :with_assistant_rows do
      with_conversational_rows
    end

    trait :invalid_schema do
      after(:build) do |dataset|
        dataset.schema = [ { "name" => "wrong_var", "type" => "string" } ]
      end
    end
  end
end
