# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::LlmResponse, type: :model do
  describe "associations" do
    it { should belong_to(:prompt_version) }
    it { should have_many(:evaluations).dependent(:destroy) }
  end

  describe "is_test_run field" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    it "defaults to false" do
      response = described_class.create!(
        prompt_version: version,
        rendered_prompt: "Test prompt",
        provider: "openai",
        model: "gpt-4",
        response_text: "Test response",
        status: "success"
      )

      expect(response.is_test_run).to be false
    end

    it "can be set to true for test runs" do
      response = described_class.create!(
        prompt_version: version,
        rendered_prompt: "Test prompt",
        provider: "openai",
        model: "gpt-4",
        response_text: "Test response",
        status: "success",
        is_test_run: true
      )

      expect(response.is_test_run).to be true
    end
  end

  describe "scopes" do
    let!(:prompt) { create(:prompt) }
    let!(:version) { create(:prompt_version, prompt: prompt) }

    let!(:production_response) do
      create(:llm_response,
             prompt_version: version,
             is_test_run: false)
    end

    let!(:test_response) do
      create(:llm_response,
             prompt_version: version,
             is_test_run: true)
    end

    describe ".tracked_calls" do
      it "returns only non-test responses" do
        expect(described_class.tracked_calls).to contain_exactly(production_response)
      end
    end

    describe ".test_calls" do
      it "returns only test responses" do
        expect(described_class.test_calls).to contain_exactly(test_response)
      end
    end
  end

  describe "callbacks" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    context "when is_test_run is false" do
      it "triggers auto-evaluation after create" do
        expect(PromptTracker::AutoEvaluationService).to receive(:evaluate)
          .with(instance_of(described_class), context: "tracked_call")

        described_class.create!(
          prompt_version: version,
          rendered_prompt: "Test prompt",
          provider: "openai",
          model: "gpt-4",
          response_text: "Test response",
          status: "success",
          is_test_run: false
        )
      end
    end

    context "when is_test_run is true" do
      it "does not trigger auto-evaluation after create" do
        expect(PromptTracker::AutoEvaluationService).not_to receive(:evaluate)

        described_class.create!(
          prompt_version: version,
          rendered_prompt: "Test prompt",
          provider: "openai",
          model: "gpt-4",
          response_text: "Test response",
          status: "success",
          is_test_run: true
        )
      end
    end
  end

  describe "#trigger_auto_evaluation" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:response) do
      described_class.new(
        prompt_version: version,
        rendered_prompt: "Test prompt",
        provider: "openai",
        model: "gpt-4",
        response_text: "Test response",
        status: "success",
        is_test_run: false
      )
    end

    it "calls AutoEvaluationService with tracked_call context" do
      expect(PromptTracker::AutoEvaluationService).to receive(:evaluate)
        .with(response, context: "tracked_call")

      response.save!
    end
  end
end
