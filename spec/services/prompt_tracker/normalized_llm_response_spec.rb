# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::NormalizedLlmResponse do
  describe "#initialize" do
    it "creates a response with required fields" do
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o"
      )

      expect(response.text).to eq("Hello!")
      expect(response.model).to eq("gpt-4o")
      expect(response.usage).to eq({ prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
    end

    it "defaults optional fields to empty arrays/hashes" do
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o"
      )

      expect(response.tool_calls).to eq([])
      expect(response.file_search_results).to eq([])
      expect(response.web_search_results).to eq([])
      expect(response.code_interpreter_results).to eq([])
      expect(response.api_metadata).to eq({})
      expect(response.raw_response).to be_nil
    end

    it "handles nil usage with default values" do
      response = described_class.new(
        text: "Hello!",
        usage: nil,
        model: "gpt-4o"
      )

      expect(response.usage).to eq({ prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 })
    end

    it "stores tool_calls as provided (no normalization)" do
      tool_calls = [
        { id: "call_123", type: "function", function_name: "get_weather", arguments: { city: "Paris" } }
      ]
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o",
        tool_calls: tool_calls
      )

      expect(response.tool_calls).to eq(tool_calls)
    end

    it "stores api_metadata with symbol keys" do
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o",
        api_metadata: { "thread_id" => "thread_123", "run_id" => "run_456" }
      )

      expect(response.api_metadata).to eq({ thread_id: "thread_123", run_id: "run_456" })
    end

    it "stores raw_response" do
      raw = { id: "resp_123", choices: [] }
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o",
        raw_response: raw
      )

      expect(response.raw_response).to eq(raw)
    end
  end

  describe "#to_h" do
    it "returns all fields as a hash" do
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o",
        tool_calls: [ { id: "call_1", type: "function", function_name: "test", arguments: {} } ],
        api_metadata: { thread_id: "thread_123" },
        raw_response: { original: true }
      )

      hash = response.to_h

      expect(hash[:text]).to eq("Hello!")
      expect(hash[:model]).to eq("gpt-4o")
      expect(hash[:usage]).to eq({ prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
      expect(hash[:tool_calls].length).to eq(1)
      expect(hash[:api_metadata]).to eq({ thread_id: "thread_123" })
      expect(hash[:raw_response]).to eq({ original: true })
    end
  end

  describe "#[]" do
    it "allows hash-like access" do
      response = described_class.new(
        text: "Hello!",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        model: "gpt-4o"
      )

      expect(response[:text]).to eq("Hello!")
      expect(response["model"]).to eq("gpt-4o")
    end
  end

  describe "convenience methods" do
    it "provides thread_id from api_metadata" do
      response = described_class.new(
        text: "Hello!",
        usage: {},
        model: "gpt-4o",
        api_metadata: { thread_id: "thread_123" }
      )

      expect(response.thread_id).to eq("thread_123")
    end

    it "provides run_id from api_metadata" do
      response = described_class.new(
        text: "Hello!",
        usage: {},
        model: "gpt-4o",
        api_metadata: { run_id: "run_456" }
      )

      expect(response.run_id).to eq("run_456")
    end

    it "provides response_id from api_metadata" do
      response = described_class.new(
        text: "Hello!",
        usage: {},
        model: "gpt-4o",
        api_metadata: { response_id: "resp_789" }
      )

      expect(response.response_id).to eq("resp_789")
    end
  end
end
