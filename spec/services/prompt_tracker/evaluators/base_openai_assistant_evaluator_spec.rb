# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe BaseOpenAiAssistantEvaluator, type: :service do
      # Create a test evaluator class for testing
      class TestAssistantEvaluator < BaseOpenAiAssistantEvaluator
        def evaluate_score
          75
        end

        def self.metadata
          {
            name: "Test Assistant Evaluator",
            description: "A test evaluator for assistant conversations"
          }
        end
      end

      let(:conversation_data) do
        {
          "messages" => [
            { "role" => "user", "content" => "Hello" },
            { "role" => "assistant", "content" => "Hi there!" }
          ]
        }
      end

      let(:config) { {} }
      let(:evaluator) { TestAssistantEvaluator.new(conversation_data, config) }

      describe ".compatible_with" do
        it "returns array containing PromptTracker::Openai::Assistant" do
          expect(BaseOpenAiAssistantEvaluator.compatible_with).to eq([ PromptTracker::Openai::Assistant ])
        end
      end

      describe ".compatible_with?" do
        it "returns true for Openai::Assistant instances" do
          assistant = build(:openai_assistant)
          expect(BaseOpenAiAssistantEvaluator.compatible_with?(assistant)).to be true
        end

        it "returns false for PromptVersion instances" do
          prompt = create(:prompt)
          version = create(:prompt_version, prompt: prompt)
          expect(BaseOpenAiAssistantEvaluator.compatible_with?(version)).to be false
        end
      end

      describe "#initialize" do
        it "sets conversation_data" do
          expect(evaluator.conversation_data).to eq(conversation_data)
        end

        it "sets config" do
          config = { judge_model: "gpt-4o" }
          evaluator = TestAssistantEvaluator.new(conversation_data, config)
          expect(evaluator.config).to eq(config)
        end
      end

      describe "#evaluate" do
        let(:assistant) { create(:openai_assistant) }
        let(:test) { create(:test, testable: assistant) }
        let(:test_run) { create(:test_run, test: test) }
        let(:config) { { test_run: test_run } }

        it "creates an Evaluation record" do
          expect {
            evaluator.evaluate
          }.to change(Evaluation, :count).by(1)
        end

        it "sets the correct attributes" do
          evaluation = evaluator.evaluate

          expect(evaluation.test_run).to eq(test_run)
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::TestAssistantEvaluator")
          expect(evaluation.score).to eq(75)
          expect(evaluation.score_min).to eq(0)
          expect(evaluation.score_max).to eq(100)
          expect(evaluation.evaluation_context).to eq("tracked_call")
        end

        it "uses custom evaluation_context if provided" do
          config[:evaluation_context] = "custom_context"
          evaluation = evaluator.evaluate

          expect(evaluation.evaluation_context).to eq("custom_context")
        end
      end
    end
  end
end
