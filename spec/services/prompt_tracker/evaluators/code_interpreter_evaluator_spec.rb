# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe CodeInterpreterEvaluator, type: :service do
      let(:code_interpreter_results) do
        [
          {
            id: "ci-123",
            status: "completed",
            code: "import pandas as pd\ndf = pd.read_csv('data.csv')\nprint(df.describe())",
            language: "python",
            output: "       value\ncount  100.0\nmean    42.5\nstd     12.3",
            files_created: [],
            error: nil
          }
        ]
      end

      let(:conversation_data) do
        {
          messages: [
            { role: "user", content: "Analyze this data file", turn: 1 },
            { role: "assistant", content: "I've analyzed the data. Here are the statistics...", turn: 1 }
          ],
          code_interpreter_results: code_interpreter_results
        }
      end

      let(:config) do
        {
          require_code_execution: true,
          require_successful_execution: true
        }
      end

      let(:evaluator) { described_class.new(conversation_data, config) }

      describe "#initialize" do
        it "sets instance variables" do
          # conversation_data is normalized by the base class
          expect(evaluator.conversation_data[:code_interpreter_results]).to be_present
          expect(evaluator.config[:require_code_execution]).to be true
        end

        it "merges config with defaults" do
          evaluator = described_class.new(conversation_data, {})
          expect(evaluator.config[:require_code_execution]).to be true
          expect(evaluator.config[:require_successful_execution]).to be true
          expect(evaluator.config[:output_patterns]).to eq([])
          expect(evaluator.config[:threshold_score]).to eq(80)
        end
      end

      describe ".metadata" do
        it "returns evaluator metadata" do
          metadata = described_class.metadata

          expect(metadata[:name]).to eq("Code Interpreter")
          expect(metadata[:description]).to include("code")
          expect(metadata[:icon]).to eq("code")
          expect(metadata[:category]).to eq(:tool_use)
        end
      end

      describe ".param_schema" do
        it "returns parameter schema" do
          schema = described_class.param_schema

          expect(schema).to have_key(:require_code_execution)
          expect(schema).to have_key(:expected_language)
          expect(schema).to have_key(:output_patterns)
          expect(schema).to have_key(:expect_files_created)
          expect(schema).to have_key(:threshold_score)
        end
      end

      describe "#evaluate_score" do
        context "when code was executed successfully" do
          it "returns 100" do
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "when code interpreter was not used" do
          let(:conversation_data) do
            { messages: [ { role: "assistant", content: "Hello" } ], code_interpreter_results: [] }
          end

          it "returns 0" do
            expect(evaluator.evaluate_score).to eq(0)
          end
        end

        context "when code execution is not required and not used" do
          let(:config) { { require_code_execution: false } }
          let(:conversation_data) do
            { messages: [ { role: "assistant", content: "Hello" } ], code_interpreter_results: [] }
          end

          it "returns 100" do
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "when execution failed" do
          let(:code_interpreter_results) do
            [ { id: "ci-123", status: "failed", code: "print(x)", error: "NameError: x is not defined" } ]
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end
      end

      describe "#passed?" do
        context "when all requirements met" do
          it "returns true" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when code not executed but required" do
          let(:conversation_data) do
            { messages: [], code_interpreter_results: [] }
          end

          it "returns false" do
            expect(evaluator.passed?).to be false
          end
        end
      end

      describe "#generate_feedback" do
        it "includes execution count" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("Executions: 1")
        end

        it "includes language" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("python")
        end

        it "indicates pass/fail status" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("✓")
        end

        context "when code interpreter not used" do
          let(:conversation_data) { { messages: [], code_interpreter_results: [] } }

          it "indicates failure" do
            feedback = evaluator.generate_feedback
            expect(feedback).to include("✗")
            expect(feedback).to include("not used")
          end
        end
      end

      describe "#metadata" do
        it "includes code interpreter details" do
          metadata = evaluator.metadata

          expect(metadata["execution_count"]).to eq(1)
          expect(metadata["successful_count"]).to eq(1)
          expect(metadata["languages"]).to include("python")
          expect(metadata["total_code_lines"]).to eq(3)
        end
      end

      describe "language matching" do
        context "when expected language matches" do
          let(:config) do
            { require_code_execution: true, expected_language: "python" }
          end

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when expected language does not match" do
          let(:config) do
            { require_code_execution: true, expected_language: "javascript" }
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        context "with case-insensitive matching" do
          let(:config) do
            { require_code_execution: true, expected_language: "PYTHON" }
          end

          it "matches case-insensitively" do
            expect(evaluator.passed?).to be true
          end
        end
      end

      describe "output pattern matching" do
        context "when output matches patterns" do
          let(:config) do
            { require_code_execution: true, output_patterns: [ "mean", "std" ] }
          end

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when output does not match all patterns with require_all" do
          let(:config) do
            { require_code_execution: true, output_patterns: [ "mean", "median" ], require_all_patterns: true }
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        context "with regex patterns" do
          let(:config) do
            { require_code_execution: true, output_patterns: [ "\\d+\\.\\d+" ] }
          end

          it "matches regex patterns" do
            expect(evaluator.send(:matched_patterns)).to include("\\d+\\.\\d+")
          end
        end
      end

      describe "files created" do
        context "when files expected but not created" do
          let(:config) do
            { require_code_execution: true, expect_files_created: true }
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        context "when files created as expected" do
          let(:code_interpreter_results) do
            [ { id: "ci-123", status: "completed", code: "plt.savefig('chart.png')",
                language: "python", output: "Saved", files_created: [ "file_xyz" ] } ]
          end
          let(:config) do
            { require_code_execution: true, expect_files_created: true }
          end

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end
      end

      describe "min code lines" do
        context "when code meets minimum" do
          let(:config) do
            { require_code_execution: true, min_code_lines: 3 }
          end

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when code does not meet minimum" do
          let(:config) do
            { require_code_execution: true, min_code_lines: 10 }
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
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
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::CodeInterpreterEvaluator")
          expect(evaluation.score).to eq(100)
          expect(evaluation.passed).to be true
        end

        it "records details in metadata" do
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.metadata["execution_count"]).to eq(1)
          expect(evaluation.metadata["languages"]).to include("python")
        end
      end
    end
  end
end
