# frozen_string_literal: true

FactoryBot.define do
  factory :dataset_row, class: "PromptTracker::DatasetRow" do
    association :dataset, factory: :dataset
    source { "manual" }
    metadata { {} }

    # Build row_data based on dataset schema
    after(:build) do |row|
      if row.row_data.blank? && row.dataset&.schema.present?
        row.row_data = {}
        row.dataset.schema.each do |var_schema|
          # Generate sample data based on variable name and type
          row.row_data[var_schema["name"]] = case var_schema["name"]
          when /name/i
                                                "John Doe"
          when /email/i
                                                "test@example.com"
          when /issue/i
                                                "Sample issue description"
          when /message/i
                                                "Sample message content"
          else
                                                "Sample #{var_schema['name']}"
          end
        end
      end
    end

    trait :llm_generated do
      source { "llm_generated" }
      metadata { { "model" => "gpt-4", "temperature" => 0.7 } }
    end

    trait :imported do
      source { "imported" }
      metadata { { "import_source" => "csv", "imported_at" => Time.current.iso8601 } }
    end
  end
end
