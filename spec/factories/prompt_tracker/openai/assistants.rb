# frozen_string_literal: true

FactoryBot.define do
  factory :openai_assistant, class: "PromptTracker::Openai::Assistant" do
    sequence(:assistant_id) { |n| "asst_test_#{n}_#{SecureRandom.hex(8)}" }
    sequence(:name) { |n| "Test Assistant #{n}" }
    description { "A test assistant for automated testing" }
    metadata do
      {
        "instructions" => "You are a helpful medical assistant. Help users with their health questions.",
        "model" => "gpt-4o",
        "tools" => []
      }
    end

    # Skip the after_create callback that tries to fetch from OpenAI
    after(:build) do |assistant|
      assistant.define_singleton_method(:fetch_from_openai) { true }
    end

    trait :with_tools do
      metadata do
        {
          "instructions" => "You are a helpful assistant with access to tools.",
          "model" => "gpt-4o",
          "tools" => [
            { "type" => "code_interpreter" },
            { "type" => "file_search" }
          ]
        }
      end
    end

    trait :with_metadata do
      metadata do
        {
          "instructions" => "You are a helpful assistant.",
          "model" => "gpt-4o",
          "tools" => [],
          "purpose" => "customer_support",
          "department" => "healthcare"
        }
      end
    end

    trait :medical_assistant do
      name { "Medical Assistant" }
      description { "Provides medical advice and support" }
      metadata do
        {
          "instructions" => <<~INSTRUCTIONS.strip,
            You are a medical assistant helping patients with their health concerns.
            Always be empathetic, professional, and accurate.
            If you're unsure about something, recommend consulting a healthcare professional.
          INSTRUCTIONS
          "model" => "gpt-4o",
          "tools" => []
        }
      end
    end

    trait :customer_support do
      name { "Customer Support Assistant" }
      description { "Helps customers with their questions" }
      metadata do
        {
          "instructions" => <<~INSTRUCTIONS.strip,
            You are a customer support assistant.
            Help customers with their questions and issues.
            Be friendly, professional, and solution-oriented.
          INSTRUCTIONS
          "model" => "gpt-4o",
          "tools" => []
        }
      end
    end
  end
end
