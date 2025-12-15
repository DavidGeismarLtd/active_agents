# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe BaseEvaluator, type: :service do
      # Create a test evaluator class for testing
      class TestEvaluator < BaseEvaluator
        def self.param_schema
          {
            min_value: { type: :integer },
            max_value: { type: :integer },
            enabled: { type: :boolean },
            keywords: { type: :array },
            config_json: { type: :json },
            name: { type: :string },
            format: { type: :symbol }
          }
        end

        def evaluate_score
          50
        end
      end

      let(:prompt) { create(:prompt) }
      let(:version) { create(:prompt_version, prompt: prompt) }
      let(:llm_response) { create(:llm_response, prompt_version: version) }

      describe ".param_schema" do
        it "returns empty hash by default" do
          expect(BaseEvaluator.param_schema).to eq({})
        end

        it "can be overridden by subclasses" do
          expect(TestEvaluator.param_schema).to be_a(Hash)
          expect(TestEvaluator.param_schema).to have_key(:min_value)
        end
      end

      describe ".process_params" do
        context "with integer type" do
          it "converts string to integer" do
            result = TestEvaluator.process_params({ min_value: "42", max_value: "100" })
            expect(result["min_value"]).to eq(42)
            expect(result["max_value"]).to eq(100)
          end
        end

        context "with boolean type" do
          it "converts 'true' string to boolean true" do
            result = TestEvaluator.process_params({ enabled: "true" })
            expect(result["enabled"]).to eq(true)
          end

          it "converts 'false' string to boolean false" do
            result = TestEvaluator.process_params({ enabled: "false" })
            expect(result["enabled"]).to eq(false)
          end

          it "converts '1' to boolean true" do
            result = TestEvaluator.process_params({ enabled: "1" })
            expect(result["enabled"]).to eq(true)
          end

          it "converts '0' to boolean false" do
            result = TestEvaluator.process_params({ enabled: "0" })
            expect(result["enabled"]).to eq(false)
          end

          it "handles actual boolean values" do
            result = TestEvaluator.process_params({ enabled: true })
            expect(result["enabled"]).to eq(true)
          end
        end

        context "with array type" do
          it "converts textarea string (newline-separated) to array" do
            result = TestEvaluator.process_params({ keywords: "hello\nworld\ntest" })
            expect(result["keywords"]).to eq([ "hello", "world", "test" ])
          end

          it "strips whitespace from array elements" do
            result = TestEvaluator.process_params({ keywords: "  hello  \n  world  \n  test  " })
            expect(result["keywords"]).to eq([ "hello", "world", "test" ])
          end

          it "rejects blank lines" do
            result = TestEvaluator.process_params({ keywords: "hello\n\nworld\n  \ntest" })
            expect(result["keywords"]).to eq([ "hello", "world", "test" ])
          end

          it "keeps array as-is if already an array" do
            result = TestEvaluator.process_params({ keywords: [ "hello", "world" ] })
            expect(result["keywords"]).to eq([ "hello", "world" ])
          end

          it "rejects blank elements from arrays" do
            result = TestEvaluator.process_params({ keywords: [ "hello", "", "world", "  " ] })
            expect(result["keywords"]).to eq([ "hello", "world" ])
          end
        end

        context "with json type" do
          it "parses JSON string" do
            json_string = '{"key": "value", "number": 42}'
            result = TestEvaluator.process_params({ config_json: json_string })
            expect(result["config_json"]).to eq({ "key" => "value", "number" => 42 })
          end

          it "handles invalid JSON gracefully" do
            result = TestEvaluator.process_params({ config_json: "not valid json" })
            expect(result["config_json"]).to be_nil
          end

          it "keeps hash as-is if already a hash" do
            hash = { "key" => "value" }
            result = TestEvaluator.process_params({ config_json: hash })
            expect(result["config_json"]).to eq(hash)
          end
        end

        context "with string type" do
          it "converts value to string" do
            result = TestEvaluator.process_params({ name: 123 })
            expect(result["name"]).to eq("123")
          end
        end

        context "with symbol type" do
          it "converts value to symbol" do
            result = TestEvaluator.process_params({ format: "json" })
            expect(result["format"]).to eq(:json)
          end
        end

        context "with unknown parameters" do
          it "keeps unknown parameters as-is" do
            result = TestEvaluator.process_params({ unknown_param: "value" })
            expect(result["unknown_param"]).to eq("value")
          end
        end

        context "with blank params" do
          it "returns empty hash for nil" do
            expect(TestEvaluator.process_params(nil)).to eq({})
          end

          it "returns empty hash for empty hash" do
            expect(TestEvaluator.process_params({})).to eq({})
          end
        end
      end
    end
  end
end
