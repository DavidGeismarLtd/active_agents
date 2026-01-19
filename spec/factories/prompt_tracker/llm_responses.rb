# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_llm_responses
#
#  ab_test_id           :bigint
#  ab_variant           :string
#  context              :jsonb
#  conversation_id      :string           # Groups related responses in a multi-turn conversation
#  cost_usd             :decimal(10, 6)
#  created_at           :datetime         not null
#  environment          :string
#  error_message        :text
#  error_type           :string
#  id                   :bigint           not null, primary key
#  is_test_run          :boolean          default(FALSE), not null
#  model                :string           not null
#  previous_response_id :string           # References the response_id of the previous turn
#  prompt_version_id    :bigint           not null
#  provider             :string           not null
#  rendered_prompt      :text             not null
#  response_id          :string           # OpenAI Response API response ID (e.g., resp_abc123)
#  response_metadata    :jsonb
#  response_text        :text
#  response_time_ms     :integer
#  session_id           :string
#  status               :string           default("pending"), not null
#  tokens_completion    :integer
#  tokens_prompt        :integer
#  tokens_total         :integer
#  tool_outputs         :jsonb            default({})  # Detailed outputs from each tool
#  tools_used           :jsonb            default([])  # Array of tool names used
#  turn_number          :integer          # Position in the conversation (1, 2, 3, ...)
#  updated_at           :datetime         not null
#  user_id              :string
#  variables_used       :jsonb
#
FactoryBot.define do
  factory :llm_response, class: "PromptTracker::LlmResponse" do
    association :prompt_version, factory: :prompt_version
    rendered_prompt { "Hello John, how can I help you today?" }
    variables_used { { "name" => "John" } }
    provider { "openai" }
    model { "gpt-4" }
    status { "success" }
    response_text { "Hi! I'm here to help. What can I do for you?" }
    response_time_ms { 1200 }
    tokens_prompt { 10 }
    tokens_completion { 12 }
    tokens_total { 22 }
    cost_usd { 0.00066 }
    environment { "test" }

    trait :pending do
      status { "pending" }
      response_text { nil }
      response_time_ms { nil }
      tokens_total { nil }
      cost_usd { nil }
    end

    trait :error do
      status { "error" }
      response_text { nil }
      error_type { "APIError" }
      error_message { "API request failed" }
      response_time_ms { 500 }
    end

    trait :timeout do
      status { "timeout" }
      response_text { nil }
      error_type { "Timeout::Error" }
      error_message { "Request timed out after 30s" }
      response_time_ms { 30000 }
    end

    trait :with_user do
      user_id { "user_#{rand(1000)}" }
      session_id { "session_#{rand(1000)}" }
    end

    trait :with_evaluations do
      after(:create) do |response|
        create_list(:evaluation, 3, llm_response: response)
      end
    end

    trait :in_ab_test do
      association :ab_test, factory: :ab_test
      ab_variant { "A" }
    end

    # Response API traits (OpenAI Responses API)
    trait :responses do
      provider { "openai" }
      response_id { "resp_#{SecureRandom.hex(12)}" }
    end

    # Legacy alias for backward compatibility
    trait :response_api do
      responses
    end

    trait :with_tools do
      responses
      tools_used { %w[web_search] }
      tool_outputs do
        {
          "web_search" => {
            "query" => "test query",
            "results" => [
              { "title" => "Test Result", "url" => "https://example.com", "snippet" => "Test snippet" }
            ]
          }
        }
      end
    end

    trait :in_conversation do
      responses
      conversation_id { "conv_#{SecureRandom.hex(8)}" }
      turn_number { 1 }
    end

    trait :multi_turn do
      responses
      transient do
        conversation_uuid { "conv_#{SecureRandom.hex(8)}" }
        turn { 1 }
        prev_response_id { nil }
      end

      conversation_id { conversation_uuid }
      turn_number { turn }
      previous_response_id { prev_response_id }
    end
  end
end
