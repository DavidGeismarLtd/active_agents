# frozen_string_literal: true

FactoryBot.define do
  factory :agent_conversation, class: "PromptTracker::AgentConversation" do
    association :deployed_agent, factory: :deployed_agent
    sequence(:conversation_id) { |n| "conv_#{SecureRandom.uuid}" }
    messages { [] }
    metadata { {} }
    last_message_at { nil }
    # expires_at is auto-set in before_validation callback based on deployed_agent.config

    trait :with_messages do
      messages do
        [
          {
            "role" => "user",
            "content" => "Hello, I need help with my account",
            "timestamp" => 5.minutes.ago.iso8601
          },
          {
            "role" => "assistant",
            "content" => "I'd be happy to help you with your account. What specific issue are you experiencing?",
            "timestamp" => 4.minutes.ago.iso8601
          },
          {
            "role" => "user",
            "content" => "I can't log in",
            "timestamp" => 3.minutes.ago.iso8601
          }
        ]
      end
      last_message_at { 3.minutes.ago }
    end

    trait :with_tool_calls do
      messages do
        [
          {
            "role" => "user",
            "content" => "What's the weather in Paris?",
            "timestamp" => 2.minutes.ago.iso8601
          },
          {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              {
                "id" => "call_123",
                "type" => "function",
                "function" => {
                  "name" => "get_weather",
                  "arguments" => { city: "Paris" }.to_json
                }
              }
            ],
            "timestamp" => 1.minute.ago.iso8601
          },
          {
            "role" => "tool",
            "tool_call_id" => "call_123",
            "name" => "get_weather",
            "content" => { temperature: 18, conditions: "cloudy" }.to_json,
            "timestamp" => 1.minute.ago.iso8601
          },
          {
            "role" => "assistant",
            "content" => "The weather in Paris is currently 18°C and cloudy.",
            "timestamp" => 1.minute.ago.iso8601
          }
        ]
      end
      last_message_at { 1.minute.ago }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :with_metadata do
      metadata do
        {
          "user_id" => "user_123",
          "session_id" => "session_456",
          "ip_address" => "192.168.1.1",
          "user_agent" => "Mozilla/5.0"
        }
      end
    end
  end
end
