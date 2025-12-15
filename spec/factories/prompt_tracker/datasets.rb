# frozen_string_literal: true

FactoryBot.define do
  factory :dataset, class: "PromptTracker::Dataset" do
    association :prompt_version, factory: :prompt_version
    sequence(:name) { |n| "Dataset #{n}" }
    description { "A test dataset for validating prompts" }
    created_by { "test_user" }
    metadata { {} }

    # Schema is automatically copied from prompt_version on create
    # But we can override it if needed
    transient do
      custom_schema { nil }
    end

    after(:build) do |dataset, evaluator|
      if evaluator.custom_schema
        dataset.schema = evaluator.custom_schema
      elsif dataset.schema.blank? && dataset.prompt_version&.variables_schema.present?
        dataset.schema = dataset.prompt_version.variables_schema
      end
    end

    trait :with_rows do
      after(:create) do |dataset|
        create_list(:dataset_row, 3, dataset: dataset)
      end
    end

    trait :invalid_schema do
      after(:build) do |dataset|
        dataset.schema = [ { "name" => "wrong_var", "type" => "string" } ]
      end
    end
  end
end
