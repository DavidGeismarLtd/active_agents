# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe FileSearchEvaluator, type: :service do
      let(:run_steps_with_file_search) do
        [
          {
            id: "step-1",
            run_id: "run-123",
            turn: 1,
            type: "tool_calls",
            status: "completed",
            file_search_results: [
              {
                id: "call-1",
                results: [
                  { "file_id" => "file-abc", "file_name" => "policy.pdf", "score" => 0.95 },
                  { "file_id" => "file-def", "file_name" => "guidelines.txt", "score" => 0.87 }
                ]
              }
            ]
          }
        ]
      end

      let(:conversation_data) do
        {
          "messages" => [
            { "role" => "user", "content" => "What are the policies?", "turn" => 1 },
            { "role" => "assistant", "content" => "Based on the policy document...", "turn" => 1 }
          ],
          "run_steps" => run_steps_with_file_search
        }
      end

      let(:config) do
        {
          expected_files: [ "policy.pdf", "guidelines.txt" ],
          require_all: true
        }
      end

      let(:evaluator) { described_class.new(conversation_data, config) }

      describe "#initialize" do
        it "sets instance variables" do
          expect(evaluator.conversation_data).to eq(conversation_data)
          expect(evaluator.config[:expected_files]).to eq([ "policy.pdf", "guidelines.txt" ])
          expect(evaluator.config[:require_all]).to be true
        end

        it "merges config with defaults" do
          evaluator = described_class.new(conversation_data, {})
          expect(evaluator.config[:expected_files]).to eq([])
          expect(evaluator.config[:require_all]).to be true
          expect(evaluator.config[:threshold_score]).to eq(100)
        end
      end

      describe ".metadata" do
        it "returns evaluator metadata" do
          metadata = described_class.metadata

          expect(metadata[:name]).to eq("File Search")
          expect(metadata[:description]).to include("searched")
          expect(metadata[:icon]).to eq("file-search")
          expect(metadata[:category]).to eq(:assistant)
        end
      end

      describe ".param_schema" do
        it "returns parameter schema" do
          schema = described_class.param_schema

          expect(schema).to have_key(:expected_files)
          expect(schema).to have_key(:require_all)
          expect(schema).to have_key(:threshold_score)
        end
      end

      describe "#evaluate_score" do
        context "when all expected files are searched" do
          it "returns 100" do
            expect(evaluator.evaluate_score).to eq(100.0)
          end
        end

        context "when only some expected files are searched" do
          let(:config) do
            {
              expected_files: [ "policy.pdf", "guidelines.txt", "missing.doc" ],
              require_all: true
            }
          end

          it "returns percentage of matched files" do
            expect(evaluator.evaluate_score).to eq(66.67)
          end
        end

        context "when no expected files are configured" do
          let(:config) { { expected_files: [] } }

          it "returns 0" do
            expect(evaluator.evaluate_score).to eq(0)
          end
        end

        context "when no file search results exist" do
          let(:conversation_data) do
            {
              "messages" => [ { "role" => "assistant", "content" => "Hello" } ],
              "run_steps" => []
            }
          end

          it "returns 0" do
            expect(evaluator.evaluate_score).to eq(0)
          end
        end
      end

      describe "#passed?" do
        context "with require_all: true" do
          context "when all files matched" do
            it "returns true" do
              expect(evaluator.passed?).to be true
            end
          end

          context "when some files missing" do
            let(:config) do
              {
                expected_files: [ "policy.pdf", "missing.doc" ],
                require_all: true
              }
            end

            it "returns false" do
              expect(evaluator.passed?).to be false
            end
          end
        end

        context "with require_all: false" do
          let(:config) do
            {
              expected_files: [ "policy.pdf", "missing.doc" ],
              require_all: false
            }
          end

          it "returns true if at least one file matched" do
            expect(evaluator.passed?).to be true
          end
        end

        context "with no expected files" do
          let(:config) { { expected_files: [] } }

          it "returns true" do
            expect(evaluator.passed?).to be true
          end
        end
      end

      describe "#generate_feedback" do
        it "includes expected files in feedback" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("policy.pdf")
          expect(feedback).to include("guidelines.txt")
        end

        it "indicates pass/fail status" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("✓")
        end

        context "when files are missing" do
          let(:config) do
            {
              expected_files: [ "policy.pdf", "missing.doc" ],
              require_all: true
            }
          end

          it "lists missing files" do
            feedback = evaluator.generate_feedback
            expect(feedback).to include("Missing files")
            expect(feedback).to include("missing.doc")
          end
        end
      end

      describe "#metadata" do
        it "includes file search details" do
          metadata = evaluator.metadata

          expect(metadata["expected_files"]).to eq([ "policy.pdf", "guidelines.txt" ])
          expect(metadata["matched_files"]).to include("policy.pdf")
          expect(metadata["searched_files"]).to include("policy.pdf")
          expect(metadata["file_search_calls"]).to eq(1)
        end
      end

      describe "#evaluate" do
        let(:assistant) { create(:openai_assistant) }
        let(:test) { create(:test, testable: assistant) }
        let(:test_run) { create(:test_run, :for_assistant, test: test) }
        let(:evaluator_with_test_run) do
          described_class.new(conversation_data, config.merge(test_run: test_run))
        end

        it "creates an evaluation record" do
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.test_run).to eq(test_run)
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::FileSearchEvaluator")
          expect(evaluation.score).to eq(100.0)
          expect(evaluation.passed).to be true
        end

        it "records matched files in metadata" do
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.metadata["expected_files"]).to eq([ "policy.pdf", "guidelines.txt" ])
          expect(evaluation.metadata["matched_files"]).to include("policy.pdf")
        end
      end

      describe "file matching" do
        let(:run_steps_with_file_search) do
          [
            {
              id: "step-1",
              run_id: "run-123",
              turn: 1,
              type: "tool_calls",
              status: "completed",
              file_search_results: [
                {
                  id: "call-1",
                  results: [
                    { "file_name" => "Company_Policy_2024.pdf" }
                  ]
                }
              ]
            }
          ]
        end

        context "with case-insensitive matching" do
          let(:config) { { expected_files: [ "company_policy_2024.pdf" ] } }

          it "matches files case-insensitively" do
            expect(evaluator.passed?).to be true
          end
        end

        context "with partial matching" do
          let(:config) { { expected_files: [ "Policy" ] } }

          it "matches partial file names" do
            expect(evaluator.passed?).to be true
          end
        end

        context "with wildcard patterns" do
          let(:config) { { expected_files: [ "*.pdf" ] } }

          it "matches wildcard patterns" do
            expect(evaluator.passed?).to be true
          end
        end
      end
    end
  end
end
