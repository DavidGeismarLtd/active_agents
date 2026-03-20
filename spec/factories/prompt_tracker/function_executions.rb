# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_function_executions
#
#  arguments              :jsonb            not null
#  created_at             :datetime         not null
#  error_message          :text
#  executed_at            :datetime         not null
#  execution_time_ms      :integer
#  function_definition_id :bigint           not null
#  id                     :bigint           not null, primary key
#  result                 :jsonb
#  success                :boolean          default(TRUE), not null
#  updated_at             :datetime         not null
#
FactoryBot.define do
  factory :function_execution, class: "PromptTracker::FunctionExecution" do
    association :function_definition, factory: :function_definition

    success { true }
    execution_time_ms { rand(100..2000) }
    executed_at { Time.current }

    arguments do
      {
        "operation" => "add",
        "a" => 5,
        "b" => 3
      }
    end

    result do
      {
        "result" => 8
      }
    end

    trait :failed do
      success { false }
      result { nil }
      error_message { "Invalid arguments provided" }
    end
  end
end
