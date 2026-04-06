# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PromptTracker AssistantChatbot execute_action", type: :request do
  it "passes page context into execute_function so suggestions are page-aware" do
    result = PromptTracker::AssistantChatbotService::Result.new(
      success?: true,
      response: "ok",
      links: [],
      suggestions: [ "Create tests for this agent version" ],
      pending_action: nil,
      error: nil
    )

    expect(PromptTracker::AssistantChatbotService).to receive(:execute_function).with(
      hash_including(
        function_name: "create_dataset",
        context: hash_including(
          page_type: :agent_version_detail,
          agent_id: "15",
          agent_version_id: "20"
        )
      )
    ).and_return(result)

    post "/prompt_tracker/assistant/execute_action",
         params: {
           session_id: "session",
           function_name: "create_dataset",
           arguments: { agent_version_id: 20, name: "Dataset", dataset_type: "single" }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_REFERER" => "http://localhost:3000/prompt_tracker/testing/agents/15/versions/20"
         }

    expect(response).to have_http_status(:ok)
  end
end
