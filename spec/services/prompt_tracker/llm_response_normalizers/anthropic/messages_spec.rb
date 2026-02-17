# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module LlmResponseNormalizers
    module Anthropic
      RSpec.describe Messages, type: :service do
        describe ".normalize" do
          context "with text response" do
            let(:raw_response) do
              {
                "id" => "msg_01XFDUDYJgAACzvnptvVoYEL",
                "type" => "message",
                "role" => "assistant",
                "content" => [
                  { "type" => "text", "text" => "Hello! How can I help you today?" }
                ],
                "model" => "claude-3-5-sonnet-20241022",
                "stop_reason" => "end_turn",
                "usage" => { "input_tokens" => 12, "output_tokens" => 8 }
              }
            end

            it "extracts text from content blocks" do
              result = described_class.normalize(raw_response)

              expect(result.text).to eq("Hello! How can I help you today?")
            end

            it "normalizes usage tokens" do
              result = described_class.normalize(raw_response)

              expect(result.usage[:prompt_tokens]).to eq(12)
              expect(result.usage[:completion_tokens]).to eq(8)
              expect(result.usage[:total_tokens]).to eq(20)
            end

            it "extracts model" do
              result = described_class.normalize(raw_response)

              expect(result.model).to eq("claude-3-5-sonnet-20241022")
            end

            it "extracts api_metadata" do
              result = described_class.normalize(raw_response)

              expect(result.api_metadata[:message_id]).to eq("msg_01XFDUDYJgAACzvnptvVoYEL")
              expect(result.api_metadata[:stop_reason]).to eq("end_turn")
            end

            it "stores raw_response" do
              result = described_class.normalize(raw_response)

              expect(result.raw_response).to eq(raw_response)
            end
          end

          context "with multiple text blocks" do
            let(:raw_response) do
              {
                "id" => "msg_123",
                "content" => [
                  { "type" => "text", "text" => "First part." },
                  { "type" => "text", "text" => "Second part." }
                ],
                "model" => "claude-3-5-sonnet-20241022",
                "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
              }
            end

            it "concatenates text blocks with newline" do
              result = described_class.normalize(raw_response)

              expect(result.text).to eq("First part.\nSecond part.")
            end
          end

          context "with tool use" do
            let(:raw_response) do
              {
                "id" => "msg_456",
                "content" => [
                  { "type" => "text", "text" => "I'll check the weather for you." },
                  {
                    "type" => "tool_use",
                    "id" => "toolu_01A09q90qw90lq917835lgs4",
                    "name" => "get_weather",
                    "input" => { "location" => "Berlin", "unit" => "celsius" }
                  }
                ],
                "model" => "claude-3-5-sonnet-20241022",
                "stop_reason" => "tool_use",
                "usage" => { "input_tokens" => 20, "output_tokens" => 15 }
              }
            end

            it "extracts tool calls" do
              result = described_class.normalize(raw_response)

              expect(result.tool_calls.length).to eq(1)
              expect(result.tool_calls[0][:id]).to eq("toolu_01A09q90qw90lq917835lgs4")
              expect(result.tool_calls[0][:type]).to eq("function")
              expect(result.tool_calls[0][:function_name]).to eq("get_weather")
              expect(result.tool_calls[0][:arguments]).to eq({ "location" => "Berlin", "unit" => "celsius" })
            end

            it "still extracts text alongside tool calls" do
              result = described_class.normalize(raw_response)

              expect(result.text).to eq("I'll check the weather for you.")
            end
          end

          context "with empty content" do
            let(:raw_response) do
              {
                "id" => "msg_789",
                "content" => [],
                "model" => "claude-3-5-sonnet-20241022",
                "usage" => { "input_tokens" => 5, "output_tokens" => 0 }
              }
            end

            it "returns empty text" do
              result = described_class.normalize(raw_response)

              expect(result.text).to eq("")
            end
          end

          context "returns expected defaults for non-Anthropic features" do
            let(:raw_response) do
              {
                "id" => "msg_123",
                "content" => [ { "type" => "text", "text" => "Hi" } ],
                "model" => "claude-3-5-sonnet-20241022",
                "usage" => { "input_tokens" => 1, "output_tokens" => 1 }
              }
            end

            it "returns empty arrays for unsupported features" do
              result = described_class.normalize(raw_response)

              expect(result.file_search_results).to eq([])
              expect(result.web_search_results).to eq([])
              expect(result.code_interpreter_results).to eq([])
            end
          end
        end
      end
    end
  end
end
