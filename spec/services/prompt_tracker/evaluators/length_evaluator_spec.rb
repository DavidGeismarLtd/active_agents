# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe LengthEvaluator do
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
        it "defines schema for min_length and max_length as integers" do
          schema = LengthEvaluator.param_schema
          expect(schema[:min_length]).to eq({ type: :integer })
          expect(schema[:max_length]).to eq({ type: :integer })
        end
      end

      describe ".process_params" do
        it "converts string integers to integers" do
          params = { min_length: "50", max_length: "500" }
          result = LengthEvaluator.process_params(params)
          expect(result["min_length"]).to eq(50)
          expect(result["max_length"]).to eq(500)
        end
      end

      describe "#evaluate_score" do
        it "scores 100 for acceptable length" do
          response = create_response("a" * 100) # Within range (10-2000)
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 0 for too short response" do
          response = create_response("hi") # 2 chars, below min (10)
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(0)
        end

        it "scores 0 for too long response" do
          response = create_response("a" * 3000) # Above max (2000)
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(0)
        end

        it "scores 100 for length at minimum boundary" do
          response = create_response("a" * 10) # Exactly at min
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 100 for length at maximum boundary" do
          response = create_response("a" * 2000) # Exactly at max
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "uses custom config" do
          response = create_response("a" * 20)
          evaluator = LengthEvaluator.new(response, {
            min_length: 10,
            max_length: 100
          })

          expect(evaluator.evaluate_score).to eq(100) # Within custom range
        end

        it "handles empty response" do
          response = create_response("")
          evaluator = LengthEvaluator.new(response)

          expect(evaluator.evaluate_score).to eq(0) # Too short
        end
      end

      describe "#generate_feedback" do
        it "generates appropriate feedback for too short" do
          response = create_response("hi")
          evaluator = LengthEvaluator.new(response)

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/too short/i)
          expect(feedback).to match(/2 chars/)
        end

        it "generates appropriate feedback for too long" do
          response = create_response("a" * 3000)
          evaluator = LengthEvaluator.new(response)

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/too long/i)
        end

        it "generates appropriate feedback for acceptable length" do
          response = create_response("a" * 100)
          evaluator = LengthEvaluator.new(response)

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/acceptable/i)
          expect(feedback).to match(/100 chars/)
        end
      end

      describe "#evaluate" do
        it "creates evaluation record" do
          response = create_response("a" * 100)
          evaluator = LengthEvaluator.new(response)

          evaluation = evaluator.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::LengthEvaluator")
          expect(evaluation.score).to eq(100)
          expect(evaluation.score_min).to eq(0)
          expect(evaluation.score_max).to eq(100)
          expect(evaluation.feedback).not_to be_nil
        end

        it "associates evaluation with prompt_test_run when provided in config" do
          response = create_response("a" * 100)
          test_run = create(:prompt_test_run)
          evaluator = LengthEvaluator.new(response, { prompt_test_run_id: test_run.id })

          evaluation = evaluator.evaluate

          expect(evaluation.prompt_test_run_id).to eq(test_run.id)
          expect(evaluation.prompt_test_run).to eq(test_run)
        end
      end

      describe "#metadata" do
        it "includes metadata" do
          response = create_response("a" * 100)
          evaluator = LengthEvaluator.new(response)

          metadata = evaluator.metadata
          expect(metadata[:response_length]).to eq(100)
          expect(metadata[:min_length]).to eq(10)
          expect(metadata[:max_length]).to eq(2000)
        end
      end
    end
  end
end
