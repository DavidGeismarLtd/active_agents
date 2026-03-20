# frozen_string_literal: true

FactoryBot.define do
  factory :environment_variable, class: "PromptTracker::EnvironmentVariable" do
    sequence(:name) { |n| "Environment Variable #{n}" }
    sequence(:key) { |n| "ENV_VAR_KEY_#{n}" }
    value { "secret_value_#{SecureRandom.hex(8)}" }
    description { "Test environment variable" }

    trait :openai do
      name { "OpenAI API Key" }
      key { "OPENAI_API_KEY" }
      value { "sk-test-#{SecureRandom.hex(16)}" }
      description { "API key for OpenAI services" }
    end

    trait :stripe do
      name { "Stripe API Key" }
      key { "STRIPE_API_KEY" }
      value { "sk_test_#{SecureRandom.hex(16)}" }
      description { "API key for Stripe payments" }
    end

    trait :sendgrid do
      name { "SendGrid API Key" }
      key { "SENDGRID_API_KEY" }
      value { "SG.#{SecureRandom.hex(16)}" }
      description { "API key for SendGrid email service" }
    end
  end
end
