# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_evaluations
#
#  created_at         :datetime         not null
#  evaluation_context :string           default("tracked_call")
#  evaluator_id       :string
#  evaluator_type     :string           not null
#  feedback           :text
#  id                 :bigint           not null, primary key
#  llm_response_id    :bigint           not null
#  metadata           :jsonb
#  passed             :boolean
#  score              :decimal(10, 2)   not null
#  score_max          :decimal(10, 2)   default(5.0)
#  score_min          :decimal(10, 2)   default(0.0)
#  updated_at         :datetime         not null
#
FactoryBot.define do
  factory :evaluation, class: "PromptTracker::Evaluation" do
    association :llm_response, factory: :llm_response
    test_run { nil }  # Optional association
    score { 4.5 }
    score_min { 0 }
    score_max { 5 }
    passed { true }
    evaluator_type { "PromptTracker::Evaluators::LengthEvaluator" }
    evaluator_id { "length_evaluator" }
    feedback { nil }
    metadata do
      {
        "min_length" => 10,
        "max_length" => 100,
        "response_length" => 45
      }
    end

    trait :keyword do
      evaluator_type { "PromptTracker::Evaluators::KeywordEvaluator" }
      evaluator_id { "keyword_evaluator" }
      score { 85 }
      score_min { 0 }
      score_max { 100 }
      passed { true }
    end

    trait :llm_judge do
      evaluator_type { "PromptTracker::Evaluators::LlmJudgeEvaluator" }
      evaluator_id { "gpt-4" }
      feedback { "The response is accurate and well-structured." }
      passed { true }
      score { 85 }
      score_min { 0 }
      score_max { 100 }
      metadata do
        {
          "judge_model" => "gpt-4o",
          "custom_instructions" => "Evaluate the quality and appropriateness of the response",
          "judge_prompt" => "Evaluate this response..."
        }
      end
    end

    trait :passing do
      score { 4.5 }
      score_min { 0 }
      score_max { 5 }
      passed { true }
    end

    trait :failing do
      score { 2.0 }
      score_min { 0 }
      score_max { 5 }
      passed { false }
    end

    # Use this trait when creating evaluations for test runs (no llm_response)
    trait :for_test_run do
      llm_response { nil }
      evaluation_context { "test_run" }
    end
  end
end
