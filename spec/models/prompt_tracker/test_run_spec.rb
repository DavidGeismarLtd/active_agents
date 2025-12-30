# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe TestRun, type: :model do
    # Setup
    let(:prompt) do
      Prompt.create!(
        name: "test_prompt",
        description: "Test prompt for test runs",
        category: "testing"
      )
    end

    let(:version) do
      prompt.prompt_versions.create!(
        user_prompt: "Hello {{name}}",
        version_number: 1,
        status: "active",
        variables_schema: [
          { "name" => "name", "type" => "string", "required" => true }
        ]
      )
    end

    let(:prompt_test) do
      version.tests.create!(
        name: "greeting_test",
        description: "Test greeting functionality"
      )
    end

    let(:llm_response) do
      version.llm_responses.create!(
        rendered_prompt: "Hello Alice",
        response_text: "Hi Alice! How can I help you today?",
        variables_used: { "name" => "Alice" },
        provider: "openai",
        model: "gpt-4",
        status: "success",
        response_time_ms: 1200,
        tokens_total: 15,
        cost_usd: 0.0003
      )
    end

    let(:valid_attributes) do
      {
        test: prompt_test,
        llm_response: llm_response,
        status: "passed",
        passed: true,
        assertion_results: [],
        passed_evaluators: 2,
        failed_evaluators: 0,
        total_evaluators: 2,
        execution_time_ms: 1500,
        cost_usd: 0.0003,
        metadata: { "test_run" => true }
      }
    end

    # Validation Tests

    describe "validations" do
      it "is valid with valid attributes" do
        test_run = TestRun.new(valid_attributes)
        expect(test_run).to be_valid
      end

      it "requires status" do
        test_run = TestRun.new(valid_attributes.merge(status: nil))
        expect(test_run).not_to be_valid
        expect(test_run.errors[:status]).to include("can't be blank")
      end

      it "validates status inclusion" do
        %w[pending running passed failed error skipped].each do |status|
          test_run = TestRun.new(valid_attributes.merge(status: status))
          expect(test_run).to be_valid, "Status '#{status}' should be valid"
        end

        test_run = TestRun.new(valid_attributes.merge(status: "invalid"))
        expect(test_run).not_to be_valid
        expect(test_run.errors[:status]).to include("is not included in the list")
      end
    end

    # Association Tests

    describe "associations" do
      it "belongs to test" do
        test_run = TestRun.create!(valid_attributes)
        expect(test_run.test).to eq(prompt_test)
      end

      it "belongs to prompt_version" do
        test_run = TestRun.create!(valid_attributes)
        expect(test_run.prompt_version).to eq(version)
      end

      it "belongs to llm_response (optional)" do
        test_run = TestRun.create!(valid_attributes)
        expect(test_run.llm_response).to eq(llm_response)
      end

      it "allows nil llm_response" do
        test_run = TestRun.new(valid_attributes.merge(llm_response: nil))
        expect(test_run).to be_valid
      end

      it "touches prompt_test on create" do
        expect do
          TestRun.create!(valid_attributes)
        end.to change { prompt_test.reload.updated_at }
      end
    end

    # Scope Tests

    describe "scopes" do
      let!(:passed_run) do
        TestRun.create!(valid_attributes.merge(status: "passed", passed: true))
      end

      let!(:failed_run) do
        TestRun.create!(valid_attributes.merge(
          status: "failed",
          passed: false,
          failed_evaluators: 1,
          passed_evaluators: 1
        ))
      end

      let!(:pending_run) do
        TestRun.create!(valid_attributes.merge(status: "pending", passed: nil))
      end

      let!(:running_run) do
        TestRun.create!(valid_attributes.merge(status: "running", passed: nil))
      end

      let!(:error_run) do
        TestRun.create!(valid_attributes.merge(
          status: "error",
          passed: false,
          error_message: "Test execution failed"
        ))
      end

      describe ".passed" do
        it "returns only passed runs" do
          expect(TestRun.passed).to include(passed_run)
          expect(TestRun.passed).not_to include(failed_run)
        end
      end

      describe ".failed" do
        it "returns only failed runs" do
          expect(TestRun.failed).to include(failed_run)
          expect(TestRun.failed).not_to include(passed_run)
        end
      end

      describe ".pending" do
        it "returns only pending runs" do
          expect(TestRun.pending).to include(pending_run)
          expect(TestRun.pending).not_to include(passed_run)
        end
      end

      describe ".running" do
        it "returns only running runs" do
          expect(TestRun.running).to include(running_run)
          expect(TestRun.running).not_to include(passed_run)
        end
      end

      describe ".completed" do
        it "returns completed runs (passed, failed, error)" do
          completed = TestRun.completed
          expect(completed).to include(passed_run)
          expect(completed).to include(failed_run)
          expect(completed).to include(error_run)
          expect(completed).not_to include(pending_run)
          expect(completed).not_to include(running_run)
        end
      end

      describe ".recent" do
        it "orders by created_at descending" do
          recent = TestRun.recent
          expect(recent.first.created_at).to be >= recent.last.created_at
        end
      end
    end

    # Status Helper Tests

    describe "status helpers" do
      it "#pending? returns true when status is pending" do
        test_run = TestRun.create!(valid_attributes.merge(status: "pending"))
        expect(test_run.pending?).to be true

        test_run.update!(status: "passed")
        expect(test_run.pending?).to be false
      end

      it "#running? returns true when status is running" do
        test_run = TestRun.create!(valid_attributes.merge(status: "running"))
        expect(test_run.running?).to be true

        test_run.update!(status: "passed")
        expect(test_run.running?).to be false
      end

      it "#completed? returns true for passed, failed, error, skipped" do
        %w[passed failed error skipped].each do |status|
          test_run = TestRun.create!(valid_attributes.merge(status: status))
          expect(test_run.completed?).to be(true), "Status '#{status}' should be completed"
        end

        %w[pending running].each do |status|
          test_run = TestRun.create!(valid_attributes.merge(status: status))
          expect(test_run.completed?).to be(false), "Status '#{status}' should not be completed"
        end
      end

      it "#error? returns true when status is error" do
        test_run = TestRun.create!(valid_attributes.merge(status: "error"))
        expect(test_run.error?).to be true

        test_run.update!(status: "passed")
        expect(test_run.error?).to be false
      end

      it "#skipped? returns true when status is skipped" do
        test_run = TestRun.create!(valid_attributes.merge(status: "skipped"))
        expect(test_run.skipped?).to be true

        test_run.update!(status: "passed")
        expect(test_run.skipped?).to be false
      end
    end

    # Evaluator Pass Rate Tests

    describe "#evaluator_pass_rate" do
      it "returns percentage of passed evaluators" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 3,
          failed_evaluators: 1,
          total_evaluators: 4
        ))

        expect(test_run.evaluator_pass_rate).to eq(75.0)
      end

      it "returns 0 when total_evaluators is zero" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 0,
          failed_evaluators: 0,
          total_evaluators: 0
        ))

        expect(test_run.evaluator_pass_rate).to eq(0.0)
      end

      it "rounds to 2 decimal places" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 2,
          failed_evaluators: 1,
          total_evaluators: 3
        ))

        expect(test_run.evaluator_pass_rate).to eq(66.67)
      end
    end

    # Evaluator Details Tests

    describe "#failed_evaluations" do
      it "returns only failed evaluations" do
        test_run = TestRun.create!(valid_attributes)

        # Create evaluations
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "length", score: 4.5, passed: true)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "keyword", score: 2.0, passed: false)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "format", score: 1.5, passed: false)

        failed = test_run.failed_evaluations
        expect(failed.count).to eq(2)
        expect(failed.pluck(:evaluator_id)).to match_array(%w[keyword format])
      end

      it "returns empty relation when all evaluators passed" do
        test_run = TestRun.create!(valid_attributes)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "length", score: 4.5, passed: true)

        expect(test_run.failed_evaluations.count).to eq(0)
      end

      it "handles no evaluations" do
        test_run = TestRun.create!(valid_attributes)
        expect(test_run.failed_evaluations.count).to eq(0)
      end
    end

    describe "#passed_evaluations" do
      it "returns only passed evaluations" do
        test_run = TestRun.create!(valid_attributes)

        # Create evaluations
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "length", score: 4.5, passed: true)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "keyword", score: 5.0, passed: true)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "format", score: 1.5, passed: false)

        passed = test_run.passed_evaluations
        expect(passed.count).to eq(2)
        expect(passed.pluck(:evaluator_id)).to match_array(%w[length keyword])
      end

      it "returns empty relation when all evaluators failed" do
        test_run = TestRun.create!(valid_attributes)
        create(:evaluation, llm_response: llm_response, test_run: test_run, evaluator_id: "length", score: 1.5, passed: false)

        expect(test_run.passed_evaluations.count).to eq(0)
      end

      it "handles no evaluations" do
        test_run = TestRun.create!(valid_attributes)
        expect(test_run.passed_evaluations.count).to eq(0)
      end
    end

    describe "#all_evaluators_passed?" do
      it "returns true when all evaluators passed" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 3,
          failed_evaluators: 0,
          total_evaluators: 3
        ))

        expect(test_run.all_evaluators_passed?).to be true
      end

      it "returns false when some evaluators failed" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 2,
          failed_evaluators: 1,
          total_evaluators: 3
        ))

        expect(test_run.all_evaluators_passed?).to be false
      end

      it "returns false when no evaluators ran" do
        test_run = TestRun.create!(valid_attributes.merge(
          passed_evaluators: 0,
          failed_evaluators: 0,
          total_evaluators: 0
        ))

        expect(test_run.all_evaluators_passed?).to be false
      end
    end

    # Callbacks Tests

    describe "callbacks" do
      it "broadcasts creation after create" do
        # We're just testing that the callback is defined and doesn't raise errors
        # Full Turbo Streams testing would require more complex setup
        expect do
          TestRun.create!(valid_attributes)
        end.not_to raise_error
      end

      it "broadcasts changes after update" do
        test_run = TestRun.create!(valid_attributes)

        expect do
          test_run.update!(status: "failed", passed: false)
        end.not_to raise_error
      end
    end
  end
end
