# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_tests
#
#  created_at         :datetime         not null
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  id                 :bigint           not null, primary key
#  metadata           :jsonb            not null
#  name               :string           not null
#  testable_type      :string           not null
#  testable_id        :bigint           not null
#  tags               :jsonb            not null
#  updated_at         :datetime         not null
#
# Note: test_mode is now derived from the testable's api_type, not stored as a column
#
FactoryBot.define do
  # New polymorphic Test factory
  factory :test, class: "PromptTracker::Test" do
    association :testable, factory: :prompt_version

    sequence(:name) { |n| "test_#{n}" }
    description { "Test description" }
    enabled { true }
    metadata { {} }

    # Trait for prompt version tests
    trait :for_prompt_version do
      association :testable, factory: :prompt_version
    end

    # Trait for assistant tests
    trait :for_assistant do
      association :testable, factory: :openai_assistant
    end

    # Trait with evaluator configs
    trait :with_evaluators do
      after(:create) do |test|
        create(:evaluator_config, configurable: test, evaluator_key: "length")
        create(:evaluator_config, configurable: test, evaluator_key: "keyword")
      end
    end

    # Trait with conversation judge evaluator (for assistant/conversational tests)
    trait :with_conversation_judge do
      after(:create) do |test|
        create(:evaluator_config,
               configurable: test,
               evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
               config: {
                 judge_model: "gpt-4o",
                 evaluation_prompt: "Evaluate this assistant message for quality.",
                 threshold_score: 70
               })
      end
    end
  end
end
