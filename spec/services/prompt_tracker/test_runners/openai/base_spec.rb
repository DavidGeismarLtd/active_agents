# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Openai
      RSpec.describe Base, type: :service do
        let(:test) { create(:test, :for_assistant) }
        let(:test_run) { create(:test_run, :for_assistant, test: test) }
        let(:testable) { test.testable }

        let(:runner) do
          described_class.new(
            test_run: test_run,
            test: test,
            testable: testable,
            use_real_llm: false
          )
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

        describe "#variables" do
          context "with dataset_row" do
            let(:dataset) { create(:dataset, :conversational, testable: testable) }
            let(:dataset_row) do
              # Conversational dataset includes interlocutor_simulation_prompt in schema
              create(:dataset_row, dataset: dataset)
            end
            let(:test_run) do
              create(:test_run, :for_assistant, test: test, dataset_row: dataset_row)
            end

            it "returns variables from dataset_row" do
              vars = runner.send(:variables)
              # Conversational dataset rows include interlocutor_simulation_prompt
              expect(vars).to be_a(HashWithIndifferentAccess)
              expect(vars[:interlocutor_simulation_prompt]).to be_present
            end
          end

          context "with custom_variables in metadata" do
            let(:test_run) do
              create(:test_run, :for_assistant, test: test, metadata: {
                "custom_variables" => { "name" => "Jane", "city" => "NYC" }
              })
            end

            it "returns variables from metadata" do
              vars = runner.send(:variables)
              expect(vars[:name]).to eq("Jane")
              expect(vars[:city]).to eq("NYC")
            end
          end

          context "with neither dataset_row nor custom_variables" do
            it "returns empty hash" do
              vars = runner.send(:variables)
              expect(vars).to eq({}.with_indifferent_access)
            end
          end
        end

        describe "#run_evaluators" do
          let(:evaluator_config) do
            # Use ConversationJudgeEvaluator which is compatible with Assistant
            create(:evaluator_config, configurable: test, evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator")
          end

          before do
            evaluator_config
          end

          it "runs enabled evaluators and returns results" do
            # Mock the evaluator - evaluators return Evaluation model instances
            mock_evaluator = instance_double(Evaluators::ConversationJudgeEvaluator)
            mock_evaluation = instance_double(Evaluation, score: 100, passed: true, feedback: "Good conversation")

            allow(EvaluatorRegistry).to receive(:build).and_return(mock_evaluator)
            allow(mock_evaluator).to receive(:evaluate).and_return(mock_evaluation)

            results = runner.send(:run_evaluators, { messages: [] })

            expect(results.length).to eq(1)
            expect(results.first[:passed]).to be true
            expect(results.first[:score]).to eq(100)
          end
        end

        describe "#update_test_run_results" do
          it "updates test run with results" do
            runner.send(:update_test_run_results,
              passed: true,
              execution_time_ms: 1500,
              evaluator_results: [ { passed: true, score: 100 } ]
            )

            test_run.reload
            expect(test_run.status).to eq("passed")
            expect(test_run.passed).to be true
            expect(test_run.execution_time_ms).to eq(1500)
            expect(test_run.metadata["evaluator_results"]).to be_present
            expect(test_run.metadata["completed_at"]).to be_present
          end

          it "merges extra_metadata" do
            runner.send(:update_test_run_results,
              passed: false,
              execution_time_ms: 2000,
              evaluator_results: [],
              extra_metadata: { model: "gpt-4o", total_turns: 3 }
            )

            test_run.reload
            expect(test_run.metadata["model"]).to eq("gpt-4o")
            expect(test_run.metadata["total_turns"]).to eq(3)
          end
        end
      end
    end
  end
end
