# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    RSpec.describe Base, type: :service do
      let(:test) { create(:test) }
      let(:test_run) { create(:test_run, test: test, status: "running") }
      let(:testable) { test.testable }

      let(:runner) do
        described_class.new(
          test_run: test_run,
          test: test,
          testable: testable,
          use_real_llm: false
        )
      end

      before do
        # Stub Turbo broadcasts to avoid route helper errors in tests
        allow_any_instance_of(TestRun).to receive(:broadcast_status_change)
      end

      describe "#initialize" do
        it "sets instance variables" do
          expect(runner.test_run).to eq(test_run)
          expect(runner.test).to eq(test)
          expect(runner.testable).to eq(testable)
          expect(runner.use_real_llm).to be false
        end

        it "defaults use_real_llm to false" do
          runner = described_class.new(
            test_run: test_run,
            test: test,
            testable: testable
          )
          expect(runner.use_real_llm).to be false
        end
      end

      describe "#run" do
        it "raises NotImplementedError" do
          expect { runner.run }.to raise_error(NotImplementedError, /Subclasses must implement #run/)
        end
      end

      describe "#variables (private)" do
        context "when test_run has dataset_row" do
          # testable (PromptVersion) has variables_schema with "name" field by default
          let(:dataset) { create(:dataset, testable: testable) }
          let(:dataset_row) { create(:dataset_row, dataset: dataset, row_data: { "name" => "John" }) }
          let(:test_run) { create(:test_run, test: test, dataset_row: dataset_row, status: "running") }

          it "returns row_data from dataset_row" do
            variables = runner.send(:variables)
            expect(variables).to eq({ "name" => "John" }.with_indifferent_access)
          end
        end

        context "when test_run has custom_variables in metadata" do
          let(:test_run) do
            create(:test_run,
              test: test,
              status: "running",
              metadata: { "custom_variables" => { "baz" => "qux" } }
            )
          end

          it "returns custom_variables from metadata" do
            variables = runner.send(:variables)
            expect(variables).to eq({ "baz" => "qux" }.with_indifferent_access)
          end
        end

        context "when test_run has neither" do
          let(:test_run) { create(:test_run, test: test, status: "running", metadata: {}) }

          it "returns empty hash" do
            variables = runner.send(:variables)
            expect(variables).to eq({}.with_indifferent_access)
          end
        end
      end

      describe "#run_evaluators (private)" do
        let!(:evaluator_config) do
          create(:evaluator_config, :keyword_evaluator, configurable: test, enabled: true)
        end

        it "runs enabled evaluators and returns results" do
          mock_evaluator = instance_double(Evaluators::KeywordEvaluator)
          mock_evaluation = instance_double(Evaluation, score: 100, passed: true, feedback: "Good")

          allow(EvaluatorRegistry).to receive(:build).and_return(mock_evaluator)
          allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

          results = runner.send(:run_evaluators, "test response text")

          expect(results.length).to eq(1)
          expect(results.first[:passed]).to be true
          expect(results.first[:score]).to eq(100)
          expect(results.first[:feedback]).to eq("Good")
        end

        it "passes correct config to evaluator" do
          mock_evaluator = instance_double(Evaluators::KeywordEvaluator)
          mock_evaluation = instance_double(Evaluation, score: 100, passed: true, feedback: "Good")

          expect(EvaluatorRegistry).to receive(:build).with(
            evaluator_config.evaluator_key.to_sym,
            "test data",
            hash_including(
              evaluator_config_id: evaluator_config.id,
              evaluation_context: "test_run",
              test_run: test_run
            )
          ).and_return(mock_evaluator)
          allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

          runner.send(:run_evaluators, "test data")
        end
      end

      describe "#update_test_run_results (private)" do
        it "updates test_run with passed status" do
          runner.send(:update_test_run_results,
            passed: true,
            execution_time_ms: 1500,
            evaluator_results: [ { score: 100, passed: true } ]
          )

          test_run.reload
          expect(test_run.status).to eq("passed")
          expect(test_run.passed).to be true
          expect(test_run.execution_time_ms).to eq(1500)
          expect(test_run.metadata["evaluator_results"]).to eq([ { "score" => 100, "passed" => true } ])
          expect(test_run.metadata["completed_at"]).to be_present
        end

        it "updates test_run with failed status" do
          runner.send(:update_test_run_results,
            passed: false,
            execution_time_ms: 2000,
            evaluator_results: [ { score: 0, passed: false } ]
          )

          test_run.reload
          expect(test_run.status).to eq("failed")
          expect(test_run.passed).to be false
        end

        it "merges extra_metadata" do
          runner.send(:update_test_run_results,
            passed: true,
            execution_time_ms: 100,
            evaluator_results: [],
            extra_metadata: { model: "gpt-4o", custom_key: "value" }
          )

          test_run.reload
          expect(test_run.metadata["model"]).to eq("gpt-4o")
          expect(test_run.metadata["custom_key"]).to eq("value")
        end
      end
    end
  end
end
