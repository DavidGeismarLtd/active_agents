# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe KeywordEvaluator do
      let(:prompt) do
        Prompt.create!(
          name: "test_prompt",
          description: "Test",
          category: "test"
        )
      end

      let(:version) do
        prompt.prompt_versions.create!(
          user_prompt: "Test",
          status: "active",
        )
      end

      def create_response(text)
        version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: text,
          status: "success"
        )
      end

      describe ".param_schema" do
        it "defines schema for keyword arrays and case_sensitive boolean" do
          schema = KeywordEvaluator.param_schema
          expect(schema[:required_keywords]).to eq({ type: :array })
          expect(schema[:forbidden_keywords]).to eq({ type: :array })
          expect(schema[:case_sensitive]).to eq({ type: :boolean })
        end
      end

      describe ".process_params" do
        it "converts textarea strings to arrays" do
          params = { required_keywords: "hello\nworld\ntest", forbidden_keywords: "bad\nevil" }
          result = KeywordEvaluator.process_params(params)
          expect(result["required_keywords"]).to eq([ "hello", "world", "test" ])
          expect(result["forbidden_keywords"]).to eq([ "bad", "evil" ])
        end

        it "converts string boolean to boolean" do
          params = { case_sensitive: "true" }
          result = KeywordEvaluator.process_params(params)
          expect(result["case_sensitive"]).to eq(true)
        end
      end

      describe "required keywords" do
        it "scores 100 when all required keywords present" do
          response = create_response("This response contains apple and banana")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 0 when no required keywords present" do
          response = create_response("This response has nothing")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ]
          })

          expect(evaluator.evaluate_score).to eq(0)
        end

        it "scores 50 when half of required keywords present" do
          response = create_response("This response contains apple only")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ]
          })

          expect(evaluator.evaluate_score).to eq(50)
        end

        it "is case insensitive by default" do
          response = create_response("This response contains APPLE and BANANA")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "forbidden keywords" do
        it "scores 100 when no forbidden keywords present" do
          response = create_response("This is a clean response")
          evaluator = KeywordEvaluator.new(response.response_text, {
            forbidden_keywords: [ "bad", "wrong" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 0 when all forbidden keywords present" do
          response = create_response("This is bad and wrong")
          evaluator = KeywordEvaluator.new(response.response_text, {
            forbidden_keywords: [ "bad", "wrong" ]
          })

          expect(evaluator.evaluate_score).to eq(0)
        end
      end

      describe "combined required and forbidden" do
        it "combines scores correctly" do
          response = create_response("This response contains apple and banana")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad", "wrong" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "case sensitivity" do
        it "is case insensitive by default" do
          response = create_response("APPLE")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "can be case sensitive" do
          response = create_response("APPLE")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple" ],
            case_sensitive: true
          })

          expect(evaluator.evaluate_score).to eq(0)
        end
      end

      describe "no keywords configured" do
        it "defaults to 100 score" do
          response = create_response("Any text")
          evaluator = KeywordEvaluator.new(response.response_text, {})

          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "#generate_feedback" do
        it "lists missing required keywords" do
          response = create_response("This has apple")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana", "cherry" ]
          })

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/missing.*banana/i)
          expect(feedback).to match(/missing.*cherry/i)
        end

        it "lists forbidden keywords found" do
          response = create_response("This is bad and wrong")
          evaluator = KeywordEvaluator.new(response.response_text, {
            forbidden_keywords: [ "bad", "wrong" ]
          })

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/forbidden.*bad/i)
          expect(feedback).to match(/forbidden.*wrong/i)
        end

        it "provides positive feedback when all criteria met" do
          response = create_response("This has apple and banana")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad" ]
          })

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/all.*met/i)
        end
      end

      describe "#evaluate" do
        it "creates evaluation record" do
          response = create_response("This has apple and banana")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ]
          })

          evaluation = evaluator.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::KeywordEvaluator")
          expect(evaluation.score).to eq(100)
          expect(evaluation.score_min).to eq(0)
          expect(evaluation.score_max).to eq(100)
        end
      end

      describe "#metadata" do
        it "includes metadata" do
          response = create_response("This has apple")
          evaluator = KeywordEvaluator.new(response.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad" ],
            case_sensitive: false
          })

          metadata = evaluator.metadata
          expect(metadata[:required_keywords]).to eq([ "apple", "banana" ])
          expect(metadata[:forbidden_keywords]).to eq([ "bad" ])
          expect(metadata[:case_sensitive]).to be false
        end
      end

      describe "weighting" do
        it "weights required keywords at 70% and forbidden at 30%" do
          # All required present (70 points) + no forbidden (30 points) = 100
          response1 = create_response("apple banana")
          evaluator1 = KeywordEvaluator.new(response1.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad" ]
          })
          expect(evaluator1.evaluate_score).to eq(100)

          # No required present (0 points) + no forbidden (30 points) = 30
          response2 = create_response("nothing here")
          evaluator2 = KeywordEvaluator.new(response2.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad" ]
          })
          expect(evaluator2.evaluate_score).to eq(30)

          # All required present (70 points) + all forbidden (0 points) = 70
          response3 = create_response("apple banana bad")
          evaluator3 = KeywordEvaluator.new(response3.response_text, {
            required_keywords: [ "apple", "banana" ],
            forbidden_keywords: [ "bad" ]
          })
          expect(evaluator3.evaluate_score).to eq(70)
        end
      end
    end
  end
end
