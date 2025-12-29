# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::RunEvaluatorsJob, type: :job do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt, user_prompt: "Hello {{name}}") }
  let(:llm_response) do
    create(:llm_response,
           prompt_version: version,
           response_text: "Hello John! How can I help you today?")
  end

  let(:test) do
    test = create(:test,
                  testable: version)
    create(:evaluator_config,
           configurable: test,
           evaluator_key: "keyword",
           config: {
             required_keywords: [ "Hello", "help" ]
           })
    test
  end

  let(:test_run) do
    create(:test_run,
           test: test,
           llm_response: llm_response,
           status: "running")
  end

  describe "#perform" do
    it "runs evaluators and updates test run" do
      described_class.new.perform(test_run.id)

      test_run.reload
      expect(test_run.status).to eq("passed")
      expect(test_run.passed).to be true
      expect(test_run.evaluations).to be_present
    end

    it "sets evaluator counts" do
      described_class.new.perform(test_run.id)

      test_run.reload
      expect(test_run.total_evaluators).to eq(1)
      expect(test_run.passed_evaluators).to eq(1)
      expect(test_run.failed_evaluators).to eq(0)
    end

    it "creates Evaluation records" do
      expect {
        described_class.new.perform(test_run.id)
      }.to change { PromptTracker::Evaluation.count }.by(1)

      test_run.reload
      evaluation = test_run.evaluations.first
      expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::KeywordEvaluator")
      expect(evaluation.evaluation_context).to eq("test_run")
      expect(evaluation.passed).to be true
    end

    context "when evaluators fail" do
      let(:test) do
        test = create(:prompt_test,
                      prompt_version: version)
        create(:evaluator_config,
               configurable: test,
               evaluator_key: "keyword",
               config: {
                 required_keywords: [ "goodbye", "farewell" ]
               })
        test
      end

      it "marks test as failed" do
        described_class.new.perform(test_run.id)

        test_run.reload
        expect(test_run.status).to eq("failed")
        expect(test_run.passed).to be false
        expect(test_run.failed_evaluators).to eq(1)
      end
    end

    context "when assertions fail" do
      let(:test) do
        test = create(:test,
                      testable: version)
        # Create an evaluator that will fail
        create(:evaluator_config,
               configurable: test,
               evaluator_key: "exact_match",
               config: {
                 expected_text: "Goodbye!"
               })
        test
      end

      it "marks test as failed" do
        described_class.new.perform(test_run.id)

        test_run.reload
        expect(test_run.status).to eq("failed")
        expect(test_run.passed).to be false
      end
    end

    context "when test run is already completed" do
      before { test_run.update!(status: "passed", passed: true) }

      it "skips execution" do
        expect {
          described_class.new.perform(test_run.id)
        }.not_to change { test_run.reload.updated_at }
      end
    end

    context "when LLM response is missing" do
      before { test_run.update!(llm_response: nil) }

      it "skips execution" do
        expect {
          described_class.new.perform(test_run.id)
        }.not_to change { test_run.reload.status }
      end
    end

    context "when an error occurs" do
      before do
        allow_any_instance_of(described_class).to receive(:run_evaluators).and_raise(StandardError, "Test error")
      end

      it "marks test run as error" do
        expect {
          described_class.new.perform(test_run.id)
        }.to raise_error(StandardError)

        test_run.reload
        expect(test_run.status).to eq("error")
        expect(test_run.passed).to be false
        expect(test_run.error_message).to include("StandardError: Test error")
      end
    end

    context "with LLM judge evaluator" do
      let(:test) do
        test = create(:test,
                      testable: version)
        create(:evaluator_config,
               configurable: test,
               evaluator_key: "llm_judge",
               config: {
                 judge_model: "gpt-4o",
                 custom_instructions: "Evaluate helpfulness and clarity"
               })
        test
      end

      # Mock RubyLLM responses
      let(:chat_double) { double("RubyLLM::Chat") }
      let(:schema_chat_double) { double("RubyLLM::Chat with schema") }
      let(:response_double) do
        double(
          "RubyLLM::Response",
          content: {
            overall_score: 80,
            feedback: "Good response"
          },
          raw: double("raw response")
        )
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(chat_double)
        allow(chat_double).to receive(:with_schema).and_return(schema_chat_double)
        allow(schema_chat_double).to receive(:ask).and_return(response_double)
      end

      it "runs LLM judge with RubyLLM" do
        described_class.new.perform(test_run.id)

        test_run.reload
        evaluation = test_run.evaluations.first
        expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::LlmJudgeEvaluator")
        expect(evaluation.score).to be_present
        expect(evaluation.feedback).to be_present
      end

      context "with real LLM enabled" do
        around do |example|
          original_env = ENV["PROMPT_TRACKER_USE_REAL_LLM"]
          ENV["PROMPT_TRACKER_USE_REAL_LLM"] = "true"
          example.run
          ENV["PROMPT_TRACKER_USE_REAL_LLM"] = original_env
        end

        it "calls RubyLLM.chat with the judge model" do
          described_class.new.perform(test_run.id)

          expect(RubyLLM).to have_received(:chat).with(model: "gpt-4o")
        end

        it "uses structured output with schema" do
          described_class.new.perform(test_run.id)

          expect(chat_double).to have_received(:with_schema)
        end
      end
    end
  end
end
