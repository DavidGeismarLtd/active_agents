# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe HumanEvaluation, type: :model do
    # Test data setup
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:llm_response) { create(:llm_response, prompt_version: version) }
    let(:evaluation) { create(:evaluation, llm_response: llm_response, score: 75) }

    describe "associations" do
      it { should belong_to(:evaluation).optional }
      it { should belong_to(:llm_response).optional }
      it { should belong_to(:test_run).optional }
    end

    describe "validations" do
      subject { build(:human_evaluation, evaluation: evaluation) }

      it { should validate_presence_of(:score) }
      it { should validate_presence_of(:feedback) }

      it { should validate_numericality_of(:score).is_greater_than_or_equal_to(0) }
      it { should validate_numericality_of(:score).is_less_than_or_equal_to(100) }

      it "is valid with valid attributes" do
        human_eval = build(:human_evaluation, evaluation: evaluation, score: 85, feedback: "Good evaluation")
        expect(human_eval).to be_valid
      end

      it "is invalid with score below 0" do
        human_eval = build(:human_evaluation, evaluation: evaluation, score: -1)
        expect(human_eval).not_to be_valid
        expect(human_eval.errors[:score]).to include("must be greater than or equal to 0")
      end

      it "is invalid with score above 100" do
        human_eval = build(:human_evaluation, evaluation: evaluation, score: 101)
        expect(human_eval).not_to be_valid
        expect(human_eval.errors[:score]).to include("must be less than or equal to 100")
      end

      it "is invalid without feedback" do
        human_eval = build(:human_evaluation, evaluation: evaluation, feedback: nil)
        expect(human_eval).not_to be_valid
        expect(human_eval.errors[:feedback]).to include("can't be blank")
      end
    end

    describe "scopes" do
      let!(:high_score_eval) { create(:human_evaluation, evaluation: evaluation, score: 85) }
      let!(:low_score_eval) { create(:human_evaluation, evaluation: evaluation, score: 45) }
      let!(:recent_eval) { create(:human_evaluation, evaluation: evaluation, score: 70) }

      describe ".recent" do
        it "orders by created_at descending" do
          expect(HumanEvaluation.recent.first).to eq(recent_eval)
        end
      end

      describe ".high_scores" do
        it "returns evaluations with score >= 70" do
          expect(HumanEvaluation.high_scores).to include(high_score_eval, recent_eval)
          expect(HumanEvaluation.high_scores).not_to include(low_score_eval)
        end
      end

      describe ".low_scores" do
        it "returns evaluations with score < 70" do
          expect(HumanEvaluation.low_scores).to include(low_score_eval)
          expect(HumanEvaluation.low_scores).not_to include(high_score_eval, recent_eval)
        end
      end
    end



    describe "#score_difference" do
      it "returns positive difference when human score is higher" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 90)
        expect(human_eval.score_difference).to eq(15) # 90 - 75
      end

      it "returns negative difference when human score is lower" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 60)
        expect(human_eval.score_difference).to eq(-15) # 60 - 75
      end

      it "returns zero when scores match" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 75)
        expect(human_eval.score_difference).to eq(0)
      end
    end

    describe "#agrees_with_evaluation?" do
      it "returns true when scores are within default tolerance (10 points)" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 80)
        expect(human_eval.agrees_with_evaluation?).to be true
      end

      it "returns false when scores differ by more than tolerance" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 90)
        expect(human_eval.agrees_with_evaluation?).to be false
      end

      it "accepts custom tolerance" do
        human_eval = create(:human_evaluation, evaluation: evaluation, score: 90)
        expect(human_eval.agrees_with_evaluation?(20)).to be true
        expect(human_eval.agrees_with_evaluation?(10)).to be false
      end
    end
  end
end
