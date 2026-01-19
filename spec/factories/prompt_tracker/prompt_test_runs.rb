# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_test_runs
#
#  cost_usd                 :decimal(10, 6)
#  created_at               :datetime         not null
#  error_message            :text
#  evaluator_results        :jsonb            not null
#  execution_time_ms        :integer
#  failed_evaluators        :integer          default(0), not null
#  id                       :bigint           not null, primary key
#  llm_response_id          :bigint
#  conversation_data        :jsonb
#  dataset_id               :bigint
#  dataset_row_id           :bigint
#  metadata                 :jsonb            not null
#  passed                   :boolean
#  passed_evaluators        :integer          default(0), not null
#  test_id                  :bigint           not null
#  prompt_version_id        :bigint
#  status                   :string           default("pending"), not null
#  total_evaluators         :integer          default(0), not null
#  updated_at               :datetime         not null
#
FactoryBot.define do
  # New polymorphic TestRun factory
  factory :test_run, class: "PromptTracker::TestRun" do
    association :test, factory: :test

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
    output_data do
      {
        "messages" => [
          { "role" => "user", "content" => "Hello John, how can I help you today?" },
          { "role" => "assistant", "content" => "Hi! I'm here to help. What can I do for you?" }
        ],
        "rendered_prompt" => "Hello John, how can I help you today?",
        "response_text" => "Hi! I'm here to help. What can I do for you?",
        "model" => "gpt-4",
        "provider" => "openai",
        "response_time_ms" => 1200
      }
    end

    # Trait for prompt version test runs
    trait :for_prompt_version do
      association :test, factory: :test, trait: :for_prompt_version
    end

    # Trait for assistant test runs
    trait :for_assistant do
      association :test, factory: :test, trait: :for_assistant
      output_data do
        {
          messages: [
            {
              role: "user",
              content: "I have a severe headache",
              turn: 1,
              timestamp: 1.minute.ago.iso8601
            },
            {
              role: "assistant",
              content: "I'm sorry to hear you're experiencing a severe headache. Can you describe the pain?",
              turn: 1,
              timestamp: 1.minute.ago.iso8601,
              run_id: "run_test123"
            }
          ],
          thread_id: "thread_test123",
          total_turns: 1,
          status: "completed",
          metadata: {
            assistant_id: "asst_test123",
            max_turns: 5,
            completed_at: Time.current.iso8601
          }
        }
      end
    end

    # Trait for multi-turn conversation
    trait :multi_turn_conversation do
      output_data do
        {
          "messages" => [
            {
              "role" => "user",
              "content" => "I have a severe headache",
              "turn" => 1,
              "timestamp" => 3.minutes.ago.iso8601
            },
            {
              "role" => "assistant",
              "content" => "I'm sorry to hear that. Can you describe the pain?",
              "turn" => 1,
              "timestamp" => 3.minutes.ago.iso8601,
              "run_id" => "run_1"
            },
            {
              "role" => "user",
              "content" => "It's a throbbing pain on the left side",
              "turn" => 2,
              "timestamp" => 2.minutes.ago.iso8601
            },
            {
              "role" => "assistant",
              "content" => "That sounds like it could be a migraine. Have you experienced this before?",
              "turn" => 2,
              "timestamp" => 2.minutes.ago.iso8601,
              "run_id" => "run_2"
            },
            {
              "role" => "user",
              "content" => "Yes, occasionally",
              "turn" => 3,
              "timestamp" => 1.minutes.ago.iso8601
            },
            {
              "role" => "assistant",
              "content" => "I recommend resting in a dark room and taking your usual migraine medication.",
              "turn" => 3,
              "timestamp" => 1.minute.ago.iso8601,
              "run_id" => "run_3"
            }
          ],
          "thread_id" => "thread_multi123",
          "total_turns" => 3,
          "status" => "completed",
          "metadata" => {
            "assistant_id" => "asst_test123",
            "max_turns" => 5,
            "completed_at" => Time.current.iso8601
          }
        }
      end
    end

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

    trait :running do
      status { "running" }
      passed { nil }
    end
  end
end
