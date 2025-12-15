# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::EvaluationsController", type: :request do
  let(:prompt) { create(:prompt, :with_active_version) }
  let(:version) { prompt.active_version }
  let(:llm_response) { create(:llm_response, prompt_version: version) }
  let!(:evaluation) { create(:evaluation, llm_response: llm_response) }

  describe "GET /evaluations" do
    it "returns success" do
      get "/prompt_tracker/evaluations"
      expect(response).to have_http_status(:success)
    end

    it "filters by evaluator_type" do
      keyword_eval = create(:evaluation, llm_response: llm_response, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")
      length_eval = create(:evaluation, llm_response: llm_response, evaluator_type: "PromptTracker::Evaluators::LengthEvaluator")

      get "/prompt_tracker/evaluations", params: { evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator" }
      expect(response).to have_http_status(:success)
    end

    it "sorts by newest (default)" do
      get "/prompt_tracker/evaluations"
      expect(response).to have_http_status(:success)
    end

    it "sorts by oldest" do
      get "/prompt_tracker/evaluations", params: { sort: "oldest" }
      expect(response).to have_http_status(:success)
    end

    it "sorts by highest_score" do
      get "/prompt_tracker/evaluations", params: { sort: "highest_score" }
      expect(response).to have_http_status(:success)
    end

    it "sorts by lowest_score" do
      get "/prompt_tracker/evaluations", params: { sort: "lowest_score" }
      expect(response).to have_http_status(:success)
    end

    it "calculates summary stats" do
      create(:evaluation, llm_response: llm_response, score: 4.0, score_min: 0, score_max: 5)
      create(:evaluation, llm_response: llm_response, score: 5.0, score_min: 0, score_max: 5)

      get "/prompt_tracker/evaluations"
      expect(response).to have_http_status(:success)
    end

    it "paginates evaluations" do
      create_list(:evaluation, 25, llm_response: llm_response)

      get "/prompt_tracker/evaluations"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /evaluations/:id" do
    it "shows evaluation details" do
      get "/prompt_tracker/evaluations/#{evaluation.id}"
      expect(response).to have_http_status(:success)
    end

    it "includes response and prompt details" do
      get "/prompt_tracker/evaluations/#{evaluation.id}"
      expect(response).to have_http_status(:success)
      # Verify evaluation details are shown
      expect(response.body).to include("Evaluation ##{evaluation.id}")
      expect(response.body).to include("Response ##{llm_response.id}")
    end

    it "returns 404 for non-existent evaluation" do
      get "/prompt_tracker/evaluations/999999"
      expect(response).to have_http_status(:not_found)
    end
  end
end
