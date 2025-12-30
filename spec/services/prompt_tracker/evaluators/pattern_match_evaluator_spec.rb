# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe PatternMatchEvaluator do
      let(:prompt) { create(:prompt) }
      let(:version) { create(:prompt_version, prompt: prompt) }

      def create_response(text)
        create(:llm_response, prompt_version: version, response_text: text)
      end

      describe ".param_schema" do
        it "defines schema for pattern match parameters" do
          schema = PatternMatchEvaluator.param_schema
          expect(schema[:patterns]).to eq({ type: :array })
          expect(schema[:match_all]).to eq({ type: :boolean })
        end
      end

      describe ".process_params" do
        it "converts textarea strings to array of patterns" do
          params = { patterns: "/hello/i\n/world/\ntest" }
          result = PatternMatchEvaluator.process_params(params)
          expect(result["patterns"]).to eq([ "/hello/i", "/world/", "test" ])
        end

        it "converts match_all string to boolean" do
          params = { match_all: "true" }
          result = PatternMatchEvaluator.process_params(params)
          expect(result["match_all"]).to eq(true)
        end
      end

      describe "#evaluate_score" do
        it "returns 100 when all patterns match (match_all: true)" do
          response = create_response("Hello world test")
          evaluator = PatternMatchEvaluator.new(response.response_text, {
            patterns: [ "/hello/i", "/world/" ],
            match_all: true
          })
          expect(evaluator.evaluate_score).to eq(100)
        end

        it "returns 0 when not all patterns match (match_all: true)" do
          response = create_response("Hello test")
          evaluator = PatternMatchEvaluator.new(response.response_text, {
            patterns: [ "/hello/i", "/world/" ],
            match_all: true
          })
          expect(evaluator.evaluate_score).to eq(0)
        end

        it "returns 100 when any pattern matches (match_all: false)" do
          response = create_response("Hello test")
          evaluator = PatternMatchEvaluator.new(response.response_text, {
            patterns: [ "/hello/i", "/world/" ],
            match_all: false
          })
          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "#passed?" do
        it "passes when all patterns match (match_all: true)" do
          response = create_response("Hello world")
          evaluator = PatternMatchEvaluator.new(response.response_text, {
            patterns: [ "/hello/i", "/world/" ],
            match_all: true
          })
          expect(evaluator.passed?).to be true
        end

        it "fails when not all patterns match (match_all: true)" do
          response = create_response("Hello")
          evaluator = PatternMatchEvaluator.new(response.response_text, {
            patterns: [ "/hello/i", "/world/" ],
            match_all: true
          })
          expect(evaluator.passed?).to be false
        end
      end
    end
  end
end
