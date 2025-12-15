# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ResponseExtractor do
    # OpenAI Format Tests

    describe "OpenAI format" do
      it "extracts text from chat format" do
        response = {
          "choices" => [
            { "message" => { "content" => "Hello, how can I help you?" } }
          ]
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Hello, how can I help you?")
      end

      it "extracts tokens from usage" do
        response = {
          "usage" => {
            "prompt_tokens" => 10,
            "completion_tokens" => 20,
            "total_tokens" => 30
          }
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.tokens_prompt).to eq(10)
        expect(extractor.tokens_completion).to eq(20)
        expect(extractor.tokens_total).to eq(30)
      end

      it "extracts metadata" do
        response = {
          "id" => "chatcmpl-123",
          "model" => "gpt-4",
          "choices" => [
            { "finish_reason" => "stop" }
          ]
        }
        extractor = ResponseExtractor.new(response)
        metadata = extractor.metadata

        expect(metadata[:id]).to eq("chatcmpl-123")
        expect(metadata[:model]).to eq("gpt-4")
        expect(metadata[:finish_reason]).to eq("stop")
      end

      it "handles deeply nested structure" do
        response = {
          "id" => "chatcmpl-abc123",
          "object" => "chat.completion",
          "created" => 1234567890,
          "model" => "gpt-4-0125-preview",
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => "This is a test response."
              },
              "finish_reason" => "stop"
            }
          ],
          "usage" => {
            "prompt_tokens" => 25,
            "completion_tokens" => 10,
            "total_tokens" => 35
          }
        }
        extractor = ResponseExtractor.new(response)

        expect(extractor.text).to eq("This is a test response.")
        expect(extractor.tokens_prompt).to eq(25)
        expect(extractor.tokens_completion).to eq(10)
        expect(extractor.tokens_total).to eq(35)
        expect(extractor.metadata[:model]).to eq("gpt-4-0125-preview")
        expect(extractor.metadata[:finish_reason]).to eq("stop")
      end
    end

    # Anthropic Format Tests

    describe "Anthropic format" do
      it "extracts text from content array" do
        response = {
          "content" => [
            { "text" => "I'm Claude, how can I assist you?" }
          ]
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("I'm Claude, how can I assist you?")
      end

      it "extracts tokens from usage" do
        response = {
          "usage" => {
            "input_tokens" => 15,
            "output_tokens" => 25
          }
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.tokens_prompt).to eq(15)
        expect(extractor.tokens_completion).to eq(25)
        expect(extractor.tokens_total).to eq(40)
      end

      it "extracts stop_reason as finish_reason" do
        response = {
          "stop_reason" => "end_turn"
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.metadata[:finish_reason]).to eq("end_turn")
      end

      it "handles legacy completion format" do
        response = {
          "completion" => "Legacy Anthropic response"
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Legacy Anthropic response")
      end
    end

    # Google Format Tests

    describe "Google Gemini format" do
      it "extracts text from candidates" do
        response = {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Hello from Gemini!" }
                ]
              }
            }
          ]
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Hello from Gemini!")
      end
    end

    # Cohere Format Tests

    describe "Cohere format" do
      it "extracts text from generations" do
        response = {
          "generations" => [
            { "text" => "Hello from Cohere!" }
          ]
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Hello from Cohere!")
      end

      it "extracts text from simple format" do
        response = { "text" => "Simple response" }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Simple response")
      end
    end

    # Generic Format Tests

    describe "generic formats" do
      it "extracts text from response key" do
        response = { "response" => "Generic response" }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Generic response")
      end

      it "extracts text from output key" do
        response = { "output" => "Output text" }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Output text")
      end

      it "extracts text from result key" do
        response = { "result" => "Result text" }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to eq("Result text")
      end
    end

    # String Response Tests

    describe "string responses" do
      it "handles plain string response" do
        extractor = ResponseExtractor.new("Plain string response")
        expect(extractor.text).to eq("Plain string response")
      end
    end

    # Edge Cases

    describe "edge cases" do
      it "returns nil for missing text" do
        response = { "some_key" => "value" }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to be_nil
      end

      it "returns nil for nil response" do
        extractor = ResponseExtractor.new(nil)
        expect(extractor.text).to be_nil
        expect(extractor.tokens_prompt).to be_nil
        expect(extractor.tokens_completion).to be_nil
        expect(extractor.tokens_total).to be_nil
      end

      it "returns nil for empty hash" do
        extractor = ResponseExtractor.new({})
        expect(extractor.text).to be_nil
        expect(extractor.tokens_prompt).to be_nil
        expect(extractor.tokens_completion).to be_nil
      end

      it "calculates total tokens from prompt and completion" do
        response = {
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 50
          }
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.tokens_total).to eq(150)
      end

      it "returns nil total tokens if prompt or completion missing" do
        response = {
          "usage" => {
            "prompt_tokens" => 100
          }
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.tokens_total).to be_nil
      end

      it "prefers explicit total_tokens over calculation" do
        response = {
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 50,
            "total_tokens" => 200  # Different from sum
          }
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.tokens_total).to eq(200)
      end

      it "handles malformed response gracefully" do
        response = {
          "choices" => "not an array"
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to be_nil
      end

      it "handles response with nil values" do
        response = {
          "choices" => [ nil ],
          "usage" => nil
        }
        extractor = ResponseExtractor.new(response)
        expect(extractor.text).to be_nil
        expect(extractor.tokens_prompt).to be_nil
      end
    end

    # extract_all Tests

    describe "#extract_all" do
      it "extracts all data at once" do
        response = {
          "choices" => [
            { "message" => { "content" => "Hello!" } }
          ],
          "usage" => {
            "prompt_tokens" => 10,
            "completion_tokens" => 5,
            "total_tokens" => 15
          },
          "model" => "gpt-4",
          "id" => "test-123"
        }
        extractor = ResponseExtractor.new(response)
        data = extractor.extract_all

        expect(data[:text]).to eq("Hello!")
        expect(data[:tokens_prompt]).to eq(10)
        expect(data[:tokens_completion]).to eq(5)
        expect(data[:tokens_total]).to eq(15)
        expect(data[:metadata][:model]).to eq("gpt-4")
        expect(data[:metadata][:id]).to eq("test-123")
      end

      it "extracts all data with missing fields" do
        response = { "text" => "Simple" }
        extractor = ResponseExtractor.new(response)
        data = extractor.extract_all

        expect(data[:text]).to eq("Simple")
        expect(data[:tokens_prompt]).to be_nil
        expect(data[:tokens_completion]).to be_nil
        expect(data[:tokens_total]).to be_nil
        expect(data[:metadata]).to eq({})
      end
    end

    # Metadata Tests

    describe "#metadata" do
      it "extracts empty metadata for string response" do
        extractor = ResponseExtractor.new("string")
        expect(extractor.metadata).to eq({})
      end

      it "extracts empty metadata for nil response" do
        extractor = ResponseExtractor.new(nil)
        expect(extractor.metadata).to eq({})
      end

      it "does not include standard keys in provider_metadata" do
        response = {
          "choices" => [ { "message" => { "content" => "Hi" } } ],
          "model" => "gpt-4",
          "custom_field" => "custom_value"
        }
        extractor = ResponseExtractor.new(response)
        metadata = extractor.metadata

        # Should have model but not in provider_metadata
        expect(metadata[:model]).to eq("gpt-4")
        # Custom field should be in provider_metadata
        expect(metadata[:provider_metadata]["custom_field"]).to eq("custom_value")
      end
    end
  end
end
