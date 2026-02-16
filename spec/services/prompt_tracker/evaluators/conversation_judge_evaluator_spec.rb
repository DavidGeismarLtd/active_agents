# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe ConversationJudgeEvaluator, type: :service do
      let(:conversation_data) do
        {
          "messages" => [
            { "role" => "user", "content" => "Hello", "turn" => 1 },
            { "role" => "assistant", "content" => "Hi there!", "turn" => 2 },
            { "role" => "user", "content" => "How are you?", "turn" => 3 },
            { "role" => "assistant", "content" => "I'm doing well, thanks!", "turn" => 4 }
          ]
        }
      end

      let(:config) do
        {
          judge_model: "gpt-4o",
          evaluation_prompt: "Evaluate this assistant message for empathy and accuracy.",
          threshold_score: 70
        }
      end

      let(:evaluator) { described_class.new(conversation_data, config) }

      describe "#initialize" do
        it "sets instance variables" do
          # conversation_data is normalized by the base class
          expect(evaluator.conversation_data[:messages].length).to eq(4)
          expect(evaluator.conversation_data[:messages].first[:content]).to eq("Hello")
          expect(evaluator.config[:judge_model]).to eq("gpt-4o")
          expect(evaluator.config[:evaluation_prompt]).to include("empathy")
          expect(evaluator.config[:threshold_score]).to eq(70)
        end

        it "merges config with defaults" do
          evaluator = described_class.new(conversation_data, {})
          expect(evaluator.config[:judge_model]).to eq("gpt-4o")
          expect(evaluator.config[:threshold_score]).to eq(70)
        end
      end

      describe ".metadata" do
        it "returns evaluator metadata" do
          metadata = described_class.metadata

          expect(metadata[:name]).to eq("Conversation Judge")
          expect(metadata[:description]).to include("LLM")
          expect(metadata[:icon]).to eq("comments")
          expect(metadata[:category]).to eq(:conversation)
        end
      end

      describe ".param_schema" do
        it "returns parameter schema" do
          schema = described_class.param_schema

          expect(schema).to have_key(:judge_model)
          expect(schema).to have_key(:evaluation_prompt)
          expect(schema).to have_key(:threshold_score)
        end
      end

      describe "#evaluate" do
        let(:prompt_version) { create(:prompt_version, :with_assistants) }
        let(:test) { create(:test, testable: prompt_version) }
        let(:test_run) { create(:test_run, :for_assistant, test: test) }
        let(:evaluator_with_test_run) do
          described_class.new(conversation_data, config.merge(test_run: test_run))
        end

        it "creates an evaluation with average score" do
          # Mock mode is enabled by default (ENV["PROMPT_TRACKER_USE_REAL_LLM"] != "true")
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.test_run).to eq(test_run)
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::ConversationJudgeEvaluator")
          expect(evaluation.score).to be_between(0, 100)
          expect(evaluation.metadata["message_scores"]).to be_present
          expect(evaluation.metadata["total_messages"]).to eq(2) # 2 assistant messages in conversation_data
        end

        it "calculates average score from message scores" do
          # Mock the score_message method to return predictable scores
          allow(evaluator_with_test_run).to receive(:score_message).and_return(
            { message_index: 0, turn: 2, score: 80, feedback: "Good", content_preview: "..." },
            { message_index: 1, turn: 4, score: 90, feedback: "Great", content_preview: "..." }
          )

          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.score.to_f).to eq(85.0) # (80 + 90) / 2
          expect(evaluation.metadata["message_scores"].length).to eq(2)
        end

        it "marks as passed when score >= threshold" do
          allow(evaluator_with_test_run).to receive(:score_message).and_return(
            { message_index: 0, turn: 2, score: 85, feedback: "Good", content_preview: "..." },
            { message_index: 1, turn: 4, score: 90, feedback: "Great", content_preview: "..." }
          )

          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.score.to_f).to eq(87.5) # (85 + 90) / 2 = 87.5
          expect(evaluation.passed).to be true
        end

        it "marks as failed when score < threshold" do
          allow(evaluator_with_test_run).to receive(:score_message).and_return(
            { message_index: 0, turn: 2, score: 50, feedback: "Poor", content_preview: "..." },
            { message_index: 1, turn: 4, score: 60, feedback: "Below average", content_preview: "..." }
          )

          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.score.to_f).to eq(55.0) # (50 + 60) / 2 = 55.0
          expect(evaluation.passed).to be false
        end

        it "handles nil conversation_data by normalizing to empty response" do
          # nil is normalized to a single empty assistant message
          evaluator = described_class.new(nil, config)
          # Should evaluate without error (normalization handles nil)
          expect { evaluator.evaluate_score }.not_to raise_error
        end

        it "raises error if conversation_data has no messages" do
          evaluator = described_class.new({ "messages" => [] }, config)

          expect { evaluator.evaluate }.to raise_error(ArgumentError, /must have messages array/)
        end

        it "raises error if no assistant messages found" do
          evaluator = described_class.new({
            "messages" => [
              { "role" => "user", "content" => "Hello", "turn" => 1 }
            ]
          }, config)

          expect { evaluator.evaluate }.to raise_error(ArgumentError, /No assistant messages found/)
        end
      end

      describe "#parse_score_from_response" do
        it "extracts score from 'Score: XX' format" do
          response = "Score: 85\nFeedback: Great response!"
          score = evaluator.send(:parse_score_from_response, response)
          expect(score).to eq(85.0)
        end

        it "handles decimal scores" do
          response = "Score: 87.5\nFeedback: Very good"
          score = evaluator.send(:parse_score_from_response, response)
          expect(score).to eq(87.5)
        end

        it "is case insensitive" do
          response = "score: 90\nFeedback: Excellent"
          score = evaluator.send(:parse_score_from_response, response)
          expect(score).to eq(90.0)
        end

        it "clamps scores to 0-100 range" do
          response = "Score: 150\nFeedback: Too high"
          score = evaluator.send(:parse_score_from_response, response)
          expect(score).to eq(100.0)
        end

        it "returns 50 if no valid score found" do
          response = "This is just feedback without a score"
          score = evaluator.send(:parse_score_from_response, response)
          expect(score).to eq(50.0)
        end
      end

      describe "#generate_feedback" do
        it "generates summary feedback" do
          # Mock message_scores_data to return predictable data
          allow(evaluator).to receive(:message_scores_data).and_return([
            { turn: 1, score: 80 },
            { turn: 2, score: 90 },
            { turn: 3, score: 85 }
          ])
          allow(evaluator).to receive(:evaluate_score).and_return(85.0)

          feedback = evaluator.send(:generate_feedback)

          expect(feedback).to include("85")
          expect(feedback).to include("80")
          expect(feedback).to include("90")
          expect(feedback).to include("85")
        end
      end
    end
  end
end
