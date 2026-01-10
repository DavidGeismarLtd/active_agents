# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Evaluators::Normalizers::AssistantsApiNormalizer do
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

    context "with Assistants API message format" do
      it "extracts text from content array" do
        response = {
          "content" => [
            { "type" => "text", "text" => { "value" => "Hello from Assistant" } }
          ]
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:text]).to eq("Hello from Assistant")
      end

      it "handles multiple text blocks" do
        response = {
          "content" => [
            { "type" => "text", "text" => { "value" => "First part" } },
            { "type" => "text", "text" => { "value" => "Second part" } }
          ]
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:text]).to eq("First part\nSecond part")
      end

      it "extracts metadata" do
        response = {
          "id" => "msg_123",
          "role" => "assistant",
          "assistant_id" => "asst_abc",
          "thread_id" => "thread_xyz",
          "run_id" => "run_456",
          "content" => []
        }

        result = normalizer.normalize_single_response(response)

        expect(result[:metadata]).to include(
          id: "msg_123",
          role: "assistant",
          assistant_id: "asst_abc",
          thread_id: "thread_xyz",
          run_id: "run_456"
        )
      end
    end
  end

  describe "#normalize_conversation" do
    it "normalizes messages with content arrays" do
      raw_data = {
        "messages" => [
          {
            "role" => "user",
            "content" => [ { "type" => "text", "text" => { "value" => "Hello" } } ]
          },
          {
            "role" => "assistant",
            "content" => [ { "type" => "text", "text" => { "value" => "Hi there!" } } ]
          }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:messages].length).to eq(2)
      expect(result[:messages][0][:content]).to eq("Hello")
      expect(result[:messages][1][:content]).to eq("Hi there!")
    end

    it "extracts file search results from run_steps" do
      raw_data = {
        "messages" => [],
        "run_steps" => [
          {
            "step_details" => {
              "tool_calls" => [
                {
                  "type" => "file_search",
                  "file_search" => {
                    "results" => [
                      { "file_name" => "doc1.pdf", "score" => 0.9 },
                      { "file_name" => "doc2.pdf", "score" => 0.8 }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:file_search_results].length).to eq(1)
      expect(result[:file_search_results][0][:files]).to eq([ "doc1.pdf", "doc2.pdf" ])
      expect(result[:file_search_results][0][:scores]).to eq([ 0.9, 0.8 ])
    end

    it "calculates turn numbers" do
      raw_data = {
        "messages" => [
          { "role" => "user", "content" => "Q1" },
          { "role" => "assistant", "content" => "A1" },
          { "role" => "user", "content" => "Q2" },
          { "role" => "assistant", "content" => "A2" }
        ]
      }

      result = normalizer.normalize_conversation(raw_data)

      expect(result[:messages][0][:turn]).to eq(1)
      expect(result[:messages][1][:turn]).to eq(1)
      expect(result[:messages][2][:turn]).to eq(2)
      expect(result[:messages][3][:turn]).to eq(2)
    end
  end
end
