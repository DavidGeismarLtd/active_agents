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
#  test_mode          :integer          default(0), not null  # 0=single_turn, 1=conversational
#  testable_type      :string           not null
#  testable_id        :bigint           not null
#  tags               :jsonb            not null
#  updated_at         :datetime         not null
#
FactoryBot.define do
  # New polymorphic Test factory
  factory :test, class: "PromptTracker::Test" do
    association :testable, factory: :prompt_version

    sequence(:name) { |n| "test_#{n}" }
    description { "Test description" }
    enabled { true }
    metadata { {} }
    # Default test_mode, but will be overridden by after(:build) for assistants
    test_mode { :single_turn }

    # Automatically set test_mode to conversational for assistants
    after(:build) do |test|
      if test.testable.is_a?(PromptTracker::Openai::Assistant)
        test.test_mode = :conversational
      end
    end

    # Trait for prompt version tests
    trait :for_prompt_version do
      association :testable, factory: :prompt_version
    end

    # Trait for assistant tests (must be conversational)
    trait :for_assistant do
      association :testable, factory: :openai_assistant
      test_mode { :conversational }
    end

    # Trait for single-turn tests (default)
    trait :single_turn do
      test_mode { :single_turn }
    end

    # Trait for conversational tests (requires Response API provider or Assistant)
    trait :conversational do
      test_mode { :conversational }
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
