# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker::AssistantChatbotController suggestions", type: :request do
  let(:agent) { create(:agent, :with_active_version) }
  let(:version) { agent.active_version }

  def post_suggestions(referrer:)
    post "/prompt_tracker/assistant/suggestions", headers: { "HTTP_REFERER" => referrer }
  end

  it "returns agent-version suggestions for agent version pages" do
    create(:test, testable: version, enabled: true)

    post_suggestions(referrer: "http://localhost:3000/prompt_tracker/testing/agents/#{agent.id}/versions/#{version.id}")

    expect(response).to have_http_status(:success)

    json = JSON.parse(response.body)
    expect(json["suggestions"]).to eq([
      "Create a dataset for this agent version",
      "Create tests for this agent version",
      "Run tests for this agent version",
        "Deploy this agent version"
    ])
  end

  it "does not suggest running tests when the version has no tests" do
    post_suggestions(referrer: "http://localhost:3000/prompt_tracker/testing/agents/#{agent.id}/versions/#{version.id}")

    expect(response).to have_http_status(:success)

    json = JSON.parse(response.body)
    expect(json["suggestions"]).to eq([
      "Create a dataset for this agent version",
      "Create tests for this agent version",
        "Deploy this agent version"
    ])
  end
end
