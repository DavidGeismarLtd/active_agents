# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe ExactMatchEvaluator do
      let(:prompt) { create(:prompt) }
      let(:version) { create(:prompt_version, prompt: prompt) }

      def create_response(text)
        create(:llm_response, prompt_version: version, response_text: text)
      end

      describe ".param_schema" do
        it "defines schema for exact match parameters" do
          schema = ExactMatchEvaluator.param_schema
          expect(schema[:expected_text]).to eq({ type: :string })
          expect(schema[:case_sensitive]).to eq({ type: :boolean })
          expect(schema[:trim_whitespace]).to eq({ type: :boolean })
        end
      end

      describe ".process_params" do
        it "converts booleans correctly" do
          params = { expected_text: "Hello", case_sensitive: "true", trim_whitespace: "false" }
          result = ExactMatchEvaluator.process_params(params)
          expect(result["expected_text"]).to eq("Hello")
          expect(result["case_sensitive"]).to eq(true)
          expect(result["trim_whitespace"]).to eq(false)
        end
      end

      describe "#evaluate_score" do
        it "returns 100 for exact match" do
          response = create_response("Hello World")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "Hello World",
            case_sensitive: true,
            trim_whitespace: false
          })
          expect(evaluator.evaluate_score).to eq(100)
        end

        it "returns 0 for non-match" do
          response = create_response("Hello World")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "Goodbye World",
            case_sensitive: true,
            trim_whitespace: false
          })
          expect(evaluator.evaluate_score).to eq(0)
        end

        it "handles case-insensitive matching" do
          response = create_response("hello world")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "HELLO WORLD",
            case_sensitive: false,
            trim_whitespace: false
          })
          expect(evaluator.evaluate_score).to eq(100)
        end

        it "handles whitespace trimming" do
          response = create_response("  Hello World  ")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "Hello World",
            case_sensitive: true,
            trim_whitespace: true
          })
          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "#passed?" do
        it "passes for exact match" do
          response = create_response("Hello World")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "Hello World"
          })
          expect(evaluator.passed?).to be true
        end

        it "fails for non-match" do
          response = create_response("Hello World")
          evaluator = ExactMatchEvaluator.new(response.response_text, {
            expected_text: "Goodbye"
          })
          expect(evaluator.passed?).to be false
        end
      end
    end
  end
end
