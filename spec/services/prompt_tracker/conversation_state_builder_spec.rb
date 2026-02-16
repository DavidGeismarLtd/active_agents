# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ConversationStateBuilder do
  describe ".call" do
    let(:user_message) { "Hello, how are you?" }
    let(:response) do
      {
        text: "I'm doing great, thank you for asking!",
        tool_calls: [],
        response_id: "resp_abc123"
      }
    end

    context "with empty previous state" do
      let(:previous_state) { { messages: [], previous_response_id: nil, started_at: nil } }

      it "creates a new conversation with user and assistant messages" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(result[:messages].size).to eq(2)
        expect(result[:messages][0][:role]).to eq("user")
        expect(result[:messages][0][:content]).to eq(user_message)
        expect(result[:messages][1][:role]).to eq("assistant")
        expect(result[:messages][1][:content]).to eq(response[:text])
      end

      it "sets the previous_response_id from the response" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(result[:previous_response_id]).to eq("resp_abc123")
      end

      it "sets started_at timestamp" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        # Verify it's a valid ISO8601 timestamp string
        expect(result[:started_at]).to be_present
        expect { Time.parse(result[:started_at]) }.not_to raise_error
      end
    end

    context "with existing conversation" do
      let(:existing_started_at) { 1.hour.ago.iso8601 }
      let(:previous_state) do
        {
          messages: [
            { role: "user", content: "First message", created_at: 5.minutes.ago.iso8601 },
            { role: "assistant", content: "First response", created_at: 5.minutes.ago.iso8601 }
          ],
          previous_response_id: "resp_old123",
          started_at: existing_started_at
        }
      end

      it "appends new messages to existing conversation" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(result[:messages].size).to eq(4)
        expect(result[:messages][2][:role]).to eq("user")
        expect(result[:messages][3][:role]).to eq("assistant")
      end

      it "preserves the original started_at timestamp" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(result[:started_at]).to eq(existing_started_at)
      end

      it "updates previous_response_id with new response ID" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(result[:previous_response_id]).to eq("resp_abc123")
      end

      it "does not mutate the original previous_state messages" do
        original_count = previous_state[:messages].size
        described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response
        )

        expect(previous_state[:messages].size).to eq(original_count)
      end
    end

    context "when response includes tool calls" do
      let(:previous_state) { { messages: [] } }
      let(:response_with_tools) do
        {
          text: "I found the information you requested.",
          tool_calls: [
            { type: "web_search", name: "search" },
            { type: "file_search", name: "file_lookup" }
          ],
          response_id: "resp_tools123"
        }
      end

      it "extracts tool types into the assistant message" do
        result = described_class.call(
          previous_state: previous_state,
          user_message: user_message,
          response: response_with_tools
        )

        assistant_message = result[:messages].last
        expect(assistant_message[:tools_used]).to eq([
          { type: "web_search" },
          { type: "file_search" }
        ])
      end
    end

    context "with nil previous state" do
      it "handles nil gracefully" do
        result = described_class.call(
          previous_state: nil,
          user_message: user_message,
          response: response
        )

        expect(result[:messages].size).to eq(2)
        expect(result[:started_at]).to be_present
      end
    end
  end
end
