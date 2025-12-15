# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::DocsController", type: :request do
  describe "GET /docs/tracking" do
    it "returns success" do
      get "/prompt_tracker/docs/tracking"
      expect(response).to have_http_status(:success)
    end

    it "displays documentation content" do
      get "/prompt_tracker/docs/tracking"
      expect(response.body).to include("How to Track LLM Calls")
      expect(response.body).to include("LlmCallService.track")
    end

    context "with prompt and version context" do
      let(:prompt) { create(:prompt, name: "test_prompt") }
      let(:version) do
        create(:prompt_version,
               prompt: prompt,
               status: "active",
               variables_schema: [
                 { "name" => "user_name", "type" => "string", "required" => true },
                 { "name" => "topic", "type" => "string", "required" => true }
               ])
      end

      it "shows context-specific example" do
        get "/prompt_tracker/docs/tracking", params: { prompt_id: prompt.id, version_id: version.id }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Quick Start for \"#{prompt.name}\"")
        expect(response.body).to include("user_name:")
        expect(response.body).to include("topic:")
      end

      it "includes back link to monitoring" do
        get "/prompt_tracker/docs/tracking", params: { prompt_id: prompt.id, version_id: version.id }

        expect(response.body).to include("Back to Monitoring")
      end
    end
  end
end
