# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Evaluation, type: :model do
  describe "associations" do
    it { should belong_to(:llm_response).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:evaluation_context) }

    it "validates evaluation_context is one of the allowed values" do
      evaluation = build(:evaluation, llm_response: create(:llm_response))

      # Valid values should work
      %w[tracked_call test_run manual].each do |context|
        evaluation.evaluation_context = context
        expect(evaluation).to be_valid
      end

      # Invalid values should raise an error
      expect {
        evaluation.evaluation_context = "invalid_context"
      }.to raise_error(ArgumentError, /'invalid_context' is not a valid evaluation_context/)
    end
  end

  describe "enums" do
    it "defines evaluation_context enum" do
      expect(described_class.evaluation_contexts).to eq(
        "tracked_call" => "tracked_call",
        "test_run" => "test_run",
        "manual" => "manual"
      )
    end
  end

  describe "scopes" do
    let!(:prompt) { create(:prompt) }
    let!(:version) { create(:prompt_version, prompt: prompt) }
    let!(:response) { create(:llm_response, prompt_version: version) }

    let!(:tracked_eval) do
      create(:evaluation,
             llm_response: response,
             evaluation_context: "tracked_call")
    end

    let!(:test_eval) do
      create(:evaluation,
             llm_response: response,
             evaluation_context: "test_run")
    end

    let!(:manual_eval) do
      create(:evaluation,
             llm_response: response,
             evaluation_context: "manual")
    end

    describe ".tracked" do
      it "returns only tracked_call evaluations" do
        expect(described_class.tracked).to contain_exactly(tracked_eval)
      end
    end

    describe ".from_tests" do
      it "returns only test_run evaluations" do
        expect(described_class.from_tests).to contain_exactly(test_eval)
      end
    end

    describe ".manual_only" do
      it "returns only manual evaluations" do
        expect(described_class.manual_only).to contain_exactly(manual_eval)
      end
    end
  end

  describe "evaluation_context default" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:response) { create(:llm_response, prompt_version: version) }

    it "defaults to tracked_call when not specified" do
      evaluation = described_class.create!(
        llm_response: response,
        evaluator_type: "automated",
        evaluator_id: "test_evaluator",
        score: 0.8,
        score_min: 0,
        score_max: 1
      )

      expect(evaluation.evaluation_context).to eq("tracked_call")
    end

    it "can be set to test_run" do
      evaluation = described_class.create!(
        llm_response: response,
        evaluator_type: "automated",
        evaluator_id: "test_evaluator",
        score: 0.8,
        score_min: 0,
        score_max: 1,
        evaluation_context: "test_run"
      )

      expect(evaluation.evaluation_context).to eq("test_run")
    end

    it "can be set to manual" do
      evaluation = described_class.create!(
        llm_response: response,
        evaluator_type: "human",
        evaluator_id: "john@example.com",
        score: 4.5,
        score_min: 0,
        score_max: 5,
        evaluation_context: "manual"
      )

      expect(evaluation.evaluation_context).to eq("manual")
    end
  end

  describe "enum methods" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:response) { create(:llm_response, prompt_version: version) }
    let(:evaluation) do
      create(:evaluation,
             llm_response: response,
             evaluation_context: "tracked_call")
    end

    it "provides tracked_call? predicate" do
      expect(evaluation.tracked_call?).to be true
      expect(evaluation.test_run?).to be false
      expect(evaluation.manual?).to be false
    end

    it "allows changing context" do
      evaluation.test_run!
      expect(evaluation.test_run?).to be true
      expect(evaluation.tracked_call?).to be false
    end
  end
end
