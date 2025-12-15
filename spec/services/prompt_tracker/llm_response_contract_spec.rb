# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe LlmResponseContract do
    describe ".normalize" do
      context "with string response" do
        it "normalizes to hash with text" do
          result = described_class.normalize("Hello, world!")

          expect(result).to eq({
            text: "Hello, world!",
            tokens_prompt: nil,
            tokens_completion: nil,
            tokens_total: nil,
            metadata: {}
          })
        end
      end

      context "with hash response (symbol keys)" do
        it "normalizes hash with all fields" do
          response = {
            text: "Hello!",
            tokens_prompt: 10,
            tokens_completion: 5,
            tokens_total: 15,
            metadata: { model: "gpt-4" }
          }

          result = described_class.normalize(response)

          expect(result).to eq({
            text: "Hello!",
            tokens_prompt: 10,
            tokens_completion: 5,
            tokens_total: 15,
            metadata: { model: "gpt-4" }
          })
        end

        it "normalizes hash with only text" do
          response = { text: "Hello!" }

          result = described_class.normalize(response)

          expect(result).to eq({
            text: "Hello!",
            tokens_prompt: nil,
            tokens_completion: nil,
            tokens_total: nil,
            metadata: {}
          })
        end

        it "auto-calculates tokens_total if not provided" do
          response = {
            text: "Hello!",
            tokens_prompt: 10,
            tokens_completion: 5
          }

          result = described_class.normalize(response)

          expect(result[:tokens_total]).to eq(15)
        end

        it "uses provided tokens_total even if components present" do
          response = {
            text: "Hello!",
            tokens_prompt: 10,
            tokens_completion: 5,
            tokens_total: 20  # Different from sum
          }

          result = described_class.normalize(response)

          expect(result[:tokens_total]).to eq(20)
        end
      end

      context "with hash response (string keys)" do
        it "normalizes hash with string keys" do
          response = {
            "text" => "Hello!",
            "tokens_prompt" => 10,
            "tokens_completion" => 5,
            "metadata" => { "model" => "gpt-4" }
          }

          result = described_class.normalize(response)

          expect(result).to eq({
            text: "Hello!",
            tokens_prompt: 10,
            tokens_completion: 5,
            tokens_total: 15,
            metadata: { "model" => "gpt-4" }
          })
        end
      end

      context "with invalid response" do
        it "raises error for non-string, non-hash" do
          expect {
            described_class.normalize(123)
          }.to raise_error(
            LlmResponseContract::InvalidResponseError,
            /Block must return String or Hash with :text key. Got: Integer/
          )
        end

        it "raises error for hash without text key" do
          expect {
            described_class.normalize({ tokens_prompt: 10 })
          }.to raise_error(
            LlmResponseContract::InvalidResponseError,
            /Hash response must include :text or 'text' key/
          )
        end

        it "raises error for nil" do
          expect {
            described_class.normalize(nil)
          }.to raise_error(
            LlmResponseContract::InvalidResponseError,
            /Block must return String or Hash with :text key. Got: NilClass/
          )
        end

        it "raises error for array" do
          expect {
            described_class.normalize([ "Hello!" ])
          }.to raise_error(
            LlmResponseContract::InvalidResponseError,
            /Block must return String or Hash with :text key. Got: Array/
          )
        end
      end
    end
  end
end
