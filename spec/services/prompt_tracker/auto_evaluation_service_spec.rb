# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AutoEvaluationService do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt) }
  let(:llm_response) { create(:llm_response, prompt_version: version) }

  describe ".evaluate" do
    it "creates a new instance and calls evaluate" do
      service = instance_double(described_class)
      allow(described_class).to receive(:new).with(llm_response, context: "tracked_call").and_return(service)
      allow(service).to receive(:evaluate)

      described_class.evaluate(llm_response)

      expect(service).to have_received(:evaluate)
    end
  end

  describe "#evaluate" do
    context "when prompt has no evaluator configs" do
      it "does not run any evaluations" do
        expect {
          described_class.evaluate(llm_response)
        }.not_to change(PromptTracker::Evaluation, :count)
      end
    end

    context "when prompt has evaluator configs" do
      let!(:config1) { create(:evaluator_config, configurable: version, evaluator_key: "length") }
      let!(:config2) { create(:evaluator_config, configurable: version, evaluator_key: "keyword") }

      it "runs all enabled evaluators" do
        # Note: Each evaluator may create multiple evaluations, so we just verify some were created
        expect {
          described_class.evaluate(llm_response)
        }.to change(PromptTracker::Evaluation, :count).by_at_least(2)
      end

      it "runs evaluators in creation order" do
        service = described_class.new(llm_response)
        expect(service).to receive(:run_evaluation).with(config1).ordered.and_call_original
        expect(service).to receive(:run_evaluation).with(config2).ordered.and_call_original

        service.evaluate
      end
    end

    context "when evaluator config is disabled" do
      let!(:disabled_config) { create(:evaluator_config, :disabled, configurable: version) }

      it "does not run disabled evaluators" do
        expect {
          described_class.evaluate(llm_response)
        }.not_to change(PromptTracker::Evaluation, :count)
      end
    end

    context "when evaluation fails" do
      let!(:config) { create(:evaluator_config, configurable: version) }

      it "logs error and continues with other evaluators" do
        allow_any_instance_of(PromptTracker::EvaluatorConfig).to receive(:build_evaluator).and_raise(StandardError, "Test error")
        allow(Rails.logger).to receive(:error)

        expect {
          described_class.evaluate(llm_response)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Auto-evaluation failed/).at_least(:once)
      end
    end
  end
end
