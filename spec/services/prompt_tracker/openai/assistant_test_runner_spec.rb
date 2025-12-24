# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    RSpec.describe AssistantTestRunner, type: :service do
      let(:assistant) { create(:openai_assistant, assistant_id: "asst_test123") }
      let(:test) { create(:test, :for_assistant, :with_conversation_judge, testable: assistant) }
      let(:dataset) { create(:dataset, :for_assistant, testable: assistant) }
      let(:dataset_row) do
        create(:dataset_row, dataset: dataset, row_data: {
          user_prompt: "I have a severe headache",
          max_turns: 3
        })
      end

      let(:runner) { described_class.new(test, assistant) }

      describe "#initialize" do
        it "sets instance variables" do
          expect(runner.test).to eq(test)
          expect(runner.assistant).to eq(assistant)
          expect(runner.metadata).to eq({})
          expect(runner.test_run).to be_nil
        end

        it "accepts metadata" do
          runner = described_class.new(test, assistant, metadata: { ci_run: true })
          expect(runner.metadata).to eq({ ci_run: true })
        end
      end

      describe "#run!" do
        let(:mock_conversation_result) do
          {
            messages: [
              { role: "user", content: "I have a severe headache", turn: 1, timestamp: Time.current.iso8601 },
              { role: "assistant", content: "I'm sorry to hear that.", turn: 1, timestamp: Time.current.iso8601, run_id: "run_1" }
            ],
            thread_id: "thread_123",
            total_turns: 1,
            status: "completed",
            metadata: { assistant_id: "asst_test123", max_turns: 3, completed_at: Time.current.iso8601 }
          }
        end

        before do
          # Stub Turbo Stream broadcasts to avoid missing partial errors
          allow_any_instance_of(TestRun).to receive(:broadcast_update)
          allow_any_instance_of(TestRun).to receive(:broadcast_replace_to)

          # Mock ConversationRunner
          mock_runner = double("ConversationRunner")
          allow(ConversationRunner).to receive(:new).and_return(mock_runner)
          allow(mock_runner).to receive(:run!).and_return(mock_conversation_result)

          # Mock ConversationJudgeEvaluator to avoid calling LLM
          # We don't actually mock it - let it run but we'll stub the LLM call inside it
          # This way we test the full integration
        end

        it "creates a test run and executes the conversation" do
          expect {
            runner.run!(dataset_row: dataset_row)
          }.to change { TestRun.count }.by(1)

          test_run = TestRun.last
          expect(test_run.test).to eq(test)
          expect(test_run.status).to be_in(%w[passed failed])
          expect(test_run.conversation_data).to be_present
          expect(test_run.conversation_data["thread_id"]).to eq("thread_123")
        end

        it "runs evaluators and stores results" do
          runner.run!(dataset_row: dataset_row)

          test_run = TestRun.last
          expect(test_run.metadata["evaluator_results"]).to be_present
          expect(test_run.metadata["evaluator_results"]).to be_an(Array)
        end

        it "calculates pass/fail based on evaluators" do
          runner.run!(dataset_row: dataset_row)

          test_run = TestRun.last
          # Mock mode generates scores 75-95, so should pass with threshold 70
          expect(test_run.passed).to be true
        end

        it "stores execution time" do
          runner.run!(dataset_row: dataset_row)

          test_run = TestRun.last
          expect(test_run.execution_time_ms).to be > 0
        end

        it "broadcasts update via Turbo Stream" do
          expect_any_instance_of(TestRun).to receive(:broadcast_update)
          runner.run!(dataset_row: dataset_row)
        end

        it "handles errors gracefully" do
          allow(ConversationRunner).to receive(:new).and_raise(StandardError.new("API Error"))

          runner.run!(dataset_row: dataset_row)

          test_run = TestRun.last
          expect(test_run.status).to eq("error")
          expect(test_run.passed).to be false
          expect(test_run.error_message).to include("API Error")
        end

        it "raises error if dataset_row has no user_prompt" do
          # Create an invalid row by bypassing validation
          invalid_row = build(:dataset_row, dataset: dataset, row_data: { max_turns: 3 })
          invalid_row.save(validate: false)

          expect {
            runner.run!(dataset_row: invalid_row)
          }.to raise_error(ArgumentError, /must have user_prompt/)
        end
      end

      describe "#run_async!" do
        let(:mock_conversation_result) do
          {
            messages: [
              { role: "user", content: "I have a severe headache", turn: 1, timestamp: Time.current.iso8601 },
              { role: "assistant", content: "I'm sorry to hear that.", turn: 1, timestamp: Time.current.iso8601, run_id: "run_1" }
            ],
            thread_id: "thread_123",
            total_turns: 1,
            status: "completed",
            metadata: { assistant_id: "asst_test123", max_turns: 3, completed_at: Time.current.iso8601 }
          }
        end

        before do
          # Mock ConversationRunner
          mock_runner = double("ConversationRunner")
          allow(ConversationRunner).to receive(:new).and_return(mock_runner)
          allow(mock_runner).to receive(:run!).and_return(mock_conversation_result)

          # Mock background job
          allow(RunEvaluatorsJob).to receive(:perform_later)
        end

        it "creates test run and enqueues background job" do
          expect(RunEvaluatorsJob).to receive(:perform_later)

          test_run = runner.run_async!(dataset_row: dataset_row)

          expect(test_run).to be_persisted
          expect(test_run.conversation_data).to be_present
        end

        it "stores conversation data before enqueuing job" do
          test_run = runner.run_async!(dataset_row: dataset_row)

          expect(test_run.conversation_data["thread_id"]).to eq("thread_123")
          expect(test_run.execution_time_ms).to be > 0
        end
      end

      describe "#determine_pass_fail" do
        it "returns true if all evaluators passed" do
          results = [
            { passed: true, score: 85 },
            { passed: true, score: 90 }
          ]

          passed = runner.send(:determine_pass_fail, results)
          expect(passed).to be true
        end

        it "returns false if any evaluator failed" do
          results = [
            { passed: true, score: 85 },
            { passed: false, score: 60 }
          ]

          passed = runner.send(:determine_pass_fail, results)
          expect(passed).to be false
        end

        it "returns true if no evaluators" do
          results = []
          passed = runner.send(:determine_pass_fail, results)
          expect(passed).to be true
        end
      end
    end
  end
end
