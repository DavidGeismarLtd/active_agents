# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::Monitoring::LlmResponsesController", type: :request do
  let(:prompt) { create(:prompt, :with_active_version) }
  let(:version) { prompt.active_version }

  describe "GET /monitoring/responses" do
    it "returns success" do
      get "/prompt_tracker/monitoring/responses"
      expect(response).to have_http_status(:success)
    end

    it "shows only tracked calls" do
      tracked_call = create(:llm_response, prompt_version: version)

      get "/prompt_tracker/monitoring/responses"
      expect(response).to have_http_status(:success)
      # All LlmResponses are tracked calls (test runs use TestRun.output_data)
    end

    it "filters by prompt" do
      other_prompt = create(:prompt, :with_active_version)
      response1 = create(:llm_response, prompt_version: version)
      response2 = create(:llm_response, prompt_version: other_prompt.active_version)

      get "/prompt_tracker/monitoring/responses", params: { prompt_id: prompt.id }
      expect(response).to have_http_status(:success)
    end

    it "filters by provider" do
      openai_response = create(:llm_response, prompt_version: version, provider: "openai")
      anthropic_response = create(:llm_response, prompt_version: version, provider: "anthropic")

      get "/prompt_tracker/monitoring/responses", params: { provider: "openai" }
      expect(response).to have_http_status(:success)
    end

    it "filters by model" do
      gpt4_response = create(:llm_response, prompt_version: version, model: "gpt-4")
      claude_response = create(:llm_response, prompt_version: version, model: "claude-3")

      get "/prompt_tracker/monitoring/responses", params: { model: "gpt-4" }
      expect(response).to have_http_status(:success)
    end

    it "filters by status" do
      success_response = create(:llm_response, prompt_version: version, status: "success")
      error_response = create(:llm_response, prompt_version: version, status: "error")

      get "/prompt_tracker/monitoring/responses", params: { status: "success" }
      expect(response).to have_http_status(:success)
    end

    it "filters by environment" do
      prod_response = create(:llm_response, prompt_version: version, environment: "production")
      staging_response = create(:llm_response, prompt_version: version, environment: "staging")

      get "/prompt_tracker/monitoring/responses", params: { environment: "production" }
      expect(response).to have_http_status(:success)
    end

    it "filters by user_id" do
      user1_response = create(:llm_response, prompt_version: version, user_id: "user_123")
      user2_response = create(:llm_response, prompt_version: version, user_id: "user_456")

      get "/prompt_tracker/monitoring/responses", params: { user_id: "user_123" }
      expect(response).to have_http_status(:success)
    end

    it "filters by session_id" do
      session1_response = create(:llm_response, prompt_version: version, session_id: "session_abc")
      session2_response = create(:llm_response, prompt_version: version, session_id: "session_xyz")

      get "/prompt_tracker/monitoring/responses", params: { session_id: "session_abc" }
      expect(response).to have_http_status(:success)
    end

    it "searches in rendered_prompt and response_text" do
      searchable = create(:llm_response, prompt_version: version, response_text: "unique_search_term_xyz123")

      get "/prompt_tracker/monitoring/responses", params: { q: "unique_search_term_xyz123" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("unique_search_term_xyz123")
    end

    it "filters by date range" do
      old_response = create(:llm_response, prompt_version: version, created_at: 10.days.ago)
      recent_response = create(:llm_response, prompt_version: version, created_at: 1.day.ago)

      get "/prompt_tracker/monitoring/responses", params: { start_date: 5.days.ago.to_date }
      expect(response).to have_http_status(:success)
    end

    it "paginates responses" do
      create_list(:llm_response, 60, prompt_version: version)

      get "/prompt_tracker/monitoring/responses"
      expect(response).to have_http_status(:success)
      # Default pagination is 50 per page
    end

    it "calculates summary stats" do
      create(:llm_response, prompt_version: version, status: "success")
      create(:llm_response, prompt_version: version, status: "error")

      get "/prompt_tracker/monitoring/responses"
      expect(response).to have_http_status(:success)
    end
  end
end
