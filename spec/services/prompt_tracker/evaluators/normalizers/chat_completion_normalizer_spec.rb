# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Evaluators::Normalizers::ChatCompletionNormalizer do
  subject(:normalizer) { described_class.new }

  describe "#normalize_single_response" do
    context "with string input" do
      it "wraps string in standard format" do
        result = normalizer.normalize_single_response("Hello world")

        expect(result).to eq({
          text: "Hello world",
          tool_calls: [],
          metadata: {}
        })
      end
    end

    context "with hash input" do
      it "extracts text from content field" do
        result = normalizer.normalize_single_response({ content: "Hello" })

        expect(result[:text]).to eq("Hello")
      end

      it "extracts text from nested choices structure" do
        response = {
          "choices" => [
            { "message" => { "content" => "Hello from GPT" } }
          ]
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:text]).to eq("Hello from GPT")
      end

      it "extracts tool calls" do
        response = {
          "choices" => [
            {
              "message" => {
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "type" => "function",
                    "function" => {
                      "name" => "get_weather",
                      "arguments" => '{"location": "Paris"}'
                    }
                  }
                ]
              }
            }
          ]
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:tool_calls]).to eq([
          {
            id: "call_123",
            type: "function",
            function_name: "get_weather",
            arguments: { "location" => "Paris" }
          }
        ])
      end

      it "extracts metadata" do
        response = {
          "model" => "gpt-4o",
          "choices" => [
            { "finish_reason" => "stop", "message" => { "content" => "Hi" } }
          ],
          "usage" => { "total_tokens" => 100 }
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:metadata]).to include(
          model: "gpt-4o",
          finish_reason: "stop",
          usage: { "total_tokens" => 100 }
        )
      end
    end
  end

  describe "#normalize_conversation" do
    it "normalizes messages array" do
      raw_data = {
        "messages" => [
          { "role" => "user", "content" => "Hello" },
          { "role" => "assistant", "content" => "Hi there!" }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:messages].length).to eq(2)
      expect(result[:messages][0][:role]).to eq("user")
      expect(result[:messages][0][:content]).to eq("Hello")
      expect(result[:messages][1][:role]).to eq("assistant")
      expect(result[:messages][1][:content]).to eq("Hi there!")
    end

    it "calculates turn numbers" do
      raw_data = {
        "messages" => [
          { "role" => "user", "content" => "First question" },
          { "role" => "assistant", "content" => "First answer" },
          { "role" => "user", "content" => "Second question" },
          { "role" => "assistant", "content" => "Second answer" }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:messages][0][:turn]).to eq(1)
      expect(result[:messages][1][:turn]).to eq(1)
      expect(result[:messages][2][:turn]).to eq(2)
      expect(result[:messages][3][:turn]).to eq(2)
    end

    it "extracts tool usage from messages" do
      raw_data = {
        "messages" => [
          {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              {
                "id" => "call_abc",
                "function" => { "name" => "search", "arguments" => '{"q": "test"}' }
              }
            ]
          }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:tool_usage].length).to eq(1)
      expect(result[:tool_usage][0][:function_name]).to eq("search")
    end

    it "returns empty file_search_results" do
      result = normalizer.normalize_conversation({ "messages" => [] })

      expect(result[:file_search_results]).to eq([])
    end
  end
end
