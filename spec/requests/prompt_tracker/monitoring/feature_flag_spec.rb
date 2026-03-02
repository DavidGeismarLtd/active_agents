# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Monitoring Feature Flag", type: :request do
  describe "when monitoring is enabled" do
    before do
      PromptTracker.configuration.features = { monitoring: true }
    end

    it "allows access to monitoring dashboard" do
      get "/prompt_tracker/monitoring"
      expect(response).to have_http_status(:success)
    end

    it "allows access to monitoring responses" do
      get "/prompt_tracker/monitoring/responses"
      expect(response).to have_http_status(:success)
    end
  end

  describe "when monitoring is disabled" do
    before do
      PromptTracker.configuration.features = { monitoring: false }
    end

    after do
      # Reset to default for other tests
      PromptTracker.configuration.features = { monitoring: true }
    end

    it "redirects monitoring dashboard to testing" do
      get "/prompt_tracker/monitoring"
      expect(response).to redirect_to("/prompt_tracker/testing")
      expect(flash[:alert]).to eq("Monitoring is disabled.")
    end

    it "redirects monitoring responses to testing" do
      get "/prompt_tracker/monitoring/responses"
      expect(response).to redirect_to("/prompt_tracker/testing")
      expect(flash[:alert]).to eq("Monitoring is disabled.")
    end

    it "redirects monitoring evaluations to testing" do
      get "/prompt_tracker/monitoring/evaluations"
      expect(response).to redirect_to("/prompt_tracker/testing")
    end
  end
end
