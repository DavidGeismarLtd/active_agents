# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe HumanEvaluationsController, type: :controller do
    routes { PromptTracker::Engine.routes }

    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:llm_response) { create(:llm_response, prompt_version: version) }
    let(:evaluation) { create(:evaluation, llm_response: llm_response, score: 75) }

    describe "POST #create" do
      context "with valid parameters" do
        let(:valid_params) do
          {
            evaluation_id: evaluation.id,
            human_evaluation: {
              score: 85,
              feedback: "Great automated evaluation, very accurate!"
            }
          }
        end

        it "creates a new human evaluation" do
          expect {
            post :create, params: valid_params
          }.to change(HumanEvaluation, :count).by(1)
        end

        it "associates the human evaluation with the evaluation" do
          post :create, params: valid_params
          expect(evaluation.human_evaluations.last.score).to eq(85)
          expect(evaluation.human_evaluations.last.feedback).to eq("Great automated evaluation, very accurate!")
        end

        it "redirects to the evaluation page with success notice" do
          post :create, params: valid_params
          expect(response).to redirect_to(evaluation_path(evaluation))
          expect(flash[:notice]).to match(/Human evaluation added successfully/)
        end
      end

      context "with invalid parameters" do
        let(:invalid_params) do
          {
            evaluation_id: evaluation.id,
            human_evaluation: {
              score: 150, # Invalid: above 100
              feedback: "Test feedback"
            }
          }
        end

        it "does not create a new human evaluation" do
          expect {
            post :create, params: invalid_params
          }.not_to change(HumanEvaluation, :count)
        end

        it "redirects to the evaluation page with error alert" do
          post :create, params: invalid_params
          expect(response).to redirect_to(evaluation_path(evaluation))
          expect(flash[:alert]).to match(/Error creating human evaluation/)
        end
      end

      context "with missing feedback" do
        let(:missing_feedback_params) do
          {
            evaluation_id: evaluation.id,
            human_evaluation: {
              score: 85,
              feedback: ""
            }
          }
        end

        it "does not create a new human evaluation" do
          expect {
            post :create, params: missing_feedback_params
          }.not_to change(HumanEvaluation, :count)
        end

        it "redirects with error message" do
          post :create, params: missing_feedback_params
          expect(response).to redirect_to(evaluation_path(evaluation))
          expect(flash[:alert]).to match(/Error creating human evaluation/)
        end
      end
    end
  end
end
