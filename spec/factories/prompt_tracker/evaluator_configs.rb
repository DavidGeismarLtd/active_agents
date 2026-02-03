# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_evaluator_configs
#
#  config            :jsonb            not null
#  configurable_id   :bigint           not null
#  configurable_type :string           not null
#  created_at        :datetime         not null
#  enabled           :boolean          default(TRUE), not null
#  evaluator_type    :string           not null
#  id                :bigint           not null, primary key
#  updated_at        :datetime         not null
#
FactoryBot.define do
  factory :evaluator_config, class: "PromptTracker::EvaluatorConfig" do
    association :configurable, factory: :prompt_version
    evaluator_type { "PromptTracker::Evaluators::LengthEvaluator" }
    enabled { true }
    config do
      {
        "min_length" => 50,
        "max_length" => 500
      }
    end

    # Trait to associate with a prompt (creates a version automatically)
    trait :for_prompt do
      transient do
        prompt { nil }
      end

      configurable do
        if prompt
          prompt.prompt_versions.first || association(:prompt_version, prompt: prompt)
        else
          association(:prompt_version)
        end
      end
    end

    trait :disabled do
      enabled { false }
    end

    trait :keyword_evaluator do
      evaluator_type { "PromptTracker::Evaluators::KeywordEvaluator" }
      config do
        {
          "required_keywords" => [ "hello", "help" ],
          "forbidden_keywords" => [ "spam" ]
        }
      end
    end

    trait :format_evaluator do
      evaluator_type { "PromptTracker::Evaluators::FormatEvaluator" }
      config do
        {
          "format" => "json",
          "schema" => {
            "type" => "object",
            "required_keys" => [ "status", "message" ]
          }
        }
      end
    end

    trait :llm_judge do
      evaluator_type { "PromptTracker::Evaluators::LlmJudgeEvaluator" }
      config do
        {
          "judge_model" => "gpt-4o",
          "custom_instructions" => "Evaluate the response quality",
          "threshold_score" => 70
        }
      end
    end

    trait :exact_match do
      evaluator_type { "PromptTracker::Evaluators::ExactMatchEvaluator" }
      config do
        {
          "expected_output" => "Hello, world!"
        }
      end
    end

    trait :function_call do
      evaluator_type { "PromptTracker::Evaluators::FunctionCallEvaluator" }
      config do
        {
          "expected_functions" => [ "get_weather" ],
          "require_all" => true,
          "check_arguments" => false,
          "threshold_score" => 80
        }
      end
    end
  end
end
