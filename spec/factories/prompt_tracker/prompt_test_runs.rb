# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_test_runs
#
#  assertion_results        :jsonb            not null
#  cost_usd                 :decimal(10, 6)
#  created_at               :datetime         not null
#  error_message            :text
#  evaluator_results        :jsonb            not null
#  execution_time_ms        :integer
#  failed_evaluators        :integer          default(0), not null
#  id                       :bigint           not null, primary key
#  llm_response_id          :bigint
#  metadata                 :jsonb            not null
#  passed                   :boolean
#  passed_evaluators        :integer          default(0), not null
#  prompt_test_id           :bigint           not null
#  prompt_test_suite_run_id :bigint
#  prompt_version_id        :bigint           not null
#  status                   :string           default("pending"), not null
#  total_evaluators         :integer          default(0), not null
#  updated_at               :datetime         not null
#
FactoryBot.define do
  factory :prompt_test_run, class: "PromptTracker::PromptTestRun" do
    association :prompt_test, factory: :prompt_test
    association :prompt_version, factory: :prompt_version
    llm_response { nil }

    status { "passed" }
    passed { true }
    error_message { nil }
    evaluator_results do
      [
        {
          evaluator_key: "length",
          score: 100,
          threshold: 100,
          passed: true,
          feedback: "Length is within acceptable range"
        }
      ]
    end
    passed_evaluators { 1 }
    failed_evaluators { 0 }
    total_evaluators { 1 }
    execution_time_ms { 1500 }
    cost_usd { 0.002 }
    metadata { {} }

    trait :failed do
      status { "failed" }
      passed { false }
      failed_evaluators { 1 }
      passed_evaluators { 0 }
    end

    trait :error do
      status { "error" }
      passed { false }
      error_message { "Test execution failed" }
    end
  end
end
