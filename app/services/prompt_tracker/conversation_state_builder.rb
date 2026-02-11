# frozen_string_literal: true

module PromptTracker
  # Builds conversation state from a user message and LLM response.
  # Maintains message history, response IDs, and timestamps.
  #
  # Usage:
  #   new_state = ConversationStateBuilder.call(
  #     previous_state: { messages: [], previous_response_id: nil, started_at: nil },
  #     user_message: "Hello!",
  #     response: { text: "Hi there!", tool_calls: [], response_id: "resp_123" }
  #   )
  #
  # Returns a hash with:
  #   - messages: Array of { role:, content:, tools_used:, created_at: } hashes
  #   - previous_response_id: String for Response API multi-turn support
  #   - started_at: ISO8601 timestamp of conversation start
  class ConversationStateBuilder
    def self.call(previous_state:, user_message:, response:)
      new(previous_state: previous_state, user_message: user_message, response: response).call
    end

    def initialize(previous_state:, user_message:, response:)
      @previous_state = previous_state || {}
      @user_message = user_message
      @response = response
    end

    def call
      messages = (@previous_state[:messages] || []).dup

      messages << build_user_message
      messages << build_assistant_message

      {
        messages: messages,
        previous_response_id: @response[:response_id],
        started_at: @previous_state[:started_at] || Time.current.iso8601
      }
    end

    private

    def build_user_message
      {
        role: "user",
        content: @user_message,
        created_at: Time.current.iso8601
      }
    end

    def build_assistant_message
      {
        role: "assistant",
        content: @response[:text],
        tools_used: extract_tools_used,
        created_at: Time.current.iso8601
      }
    end

    def extract_tools_used
      return [] unless @response[:tool_calls].present?

      @response[:tool_calls].map do |tool_call|
        { type: tool_call[:type] }
      end
    end
  end
end
