# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ConversationMessage do
  describe "#initialize" do
    it "creates a message with required fields" do
      message = described_class.new(
        role: "assistant",
        content: "Hello!",
        turn: 1
      )

      expect(message.role).to eq("assistant")
      expect(message.content).to eq("Hello!")
      expect(message.turn).to eq(1)
    end

    it "sets default values for optional fields" do
      message = described_class.new(
        role: "user",
        content: "Hi",
        turn: 1
      )

      expect(message.usage).to eq({})
      expect(message.tool_calls).to eq([])
      expect(message.file_search_results).to eq([])
      expect(message.web_search_results).to eq([])
      expect(message.code_interpreter_results).to eq([])
      expect(message.api_metadata).to eq({})
    end

    it "accepts all optional fields" do
      message = described_class.new(
        role: "assistant",
        content: "Result",
        turn: 2,
        usage: { prompt_tokens: 10, completion_tokens: 5 },
        tool_calls: [ { id: "call_1", function_name: "search" } ],
        file_search_results: [ { file: "doc.pdf", content: "..." } ],
        web_search_results: [ { url: "http://example.com" } ],
        code_interpreter_results: [ { output: "42" } ],
        api_metadata: { model: "gpt-4o" }
      )

      expect(message.usage).to eq({ prompt_tokens: 10, completion_tokens: 5 })
      expect(message.tool_calls).to eq([ { id: "call_1", function_name: "search" } ])
      expect(message.file_search_results).to eq([ { file: "doc.pdf", content: "..." } ])
      expect(message.web_search_results).to eq([ { url: "http://example.com" } ])
      expect(message.code_interpreter_results).to eq([ { output: "42" } ])
      expect(message.api_metadata).to eq({ model: "gpt-4o" })
    end

    it "handles nil values for optional fields" do
      message = described_class.new(
        role: "assistant",
        content: "Test",
        turn: 1,
        usage: nil,
        tool_calls: nil,
        file_search_results: nil
      )

      expect(message.usage).to eq({})
      expect(message.tool_calls).to eq([])
      expect(message.file_search_results).to eq([])
    end
  end

  describe "#to_h" do
    it "returns a hash with string keys" do
      message = described_class.new(
        role: "assistant",
        content: "Hello!",
        turn: 1,
        usage: { prompt_tokens: 10 },
        tool_calls: [ { id: "call_1" } ]
      )

      result = message.to_h

      expect(result).to eq({
        "role" => "assistant",
        "content" => "Hello!",
        "turn" => 1,
        "usage" => { prompt_tokens: 10 },
        "tool_calls" => [ { id: "call_1" } ],
        "file_search_results" => [],
        "web_search_results" => [],
        "code_interpreter_results" => [],
        "api_metadata" => {}
      })
    end
  end

  describe "#assistant?" do
    it "returns true for assistant role" do
      message = described_class.new(role: "assistant", content: "Hi", turn: 1)
      expect(message.assistant?).to be true
    end

    it "returns false for user role" do
      message = described_class.new(role: "user", content: "Hi", turn: 1)
      expect(message.assistant?).to be false
    end
  end

  describe "#user?" do
    it "returns true for user role" do
      message = described_class.new(role: "user", content: "Hi", turn: 1)
      expect(message.user?).to be true
    end

    it "returns false for assistant role" do
      message = described_class.new(role: "assistant", content: "Hi", turn: 1)
      expect(message.user?).to be false
    end
  end

  describe "#has_tool_calls?" do
    it "returns true when tool_calls is present" do
      message = described_class.new(
        role: "assistant",
        content: "Searching...",
        turn: 1,
        tool_calls: [ { id: "call_1", function_name: "search" } ]
      )
      expect(message.has_tool_calls?).to be true
    end

    it "returns false when tool_calls is empty" do
      message = described_class.new(role: "assistant", content: "Hi", turn: 1)
      expect(message.has_tool_calls?).to be false
    end
  end

  describe "#has_file_search_results?" do
    it "returns true when file_search_results is present" do
      message = described_class.new(
        role: "assistant",
        content: "Found docs",
        turn: 1,
        file_search_results: [ { file: "doc.pdf" } ]
      )
      expect(message.has_file_search_results?).to be true
    end

    it "returns false when file_search_results is empty" do
      message = described_class.new(role: "assistant", content: "Hi", turn: 1)
      expect(message.has_file_search_results?).to be false
    end
  end
end
