# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::Public::TaskAgentsController, type: :controller do
  routes { PromptTracker::Engine.routes }

  let(:prompt_version) { create(:prompt_version) }
  let(:task_agent) do
    agent = create(:deployed_agent,
                   :task_agent,
                   prompt_version: prompt_version,
                   task_config: {
                     initial_prompt: "Process {{source_url}}",
                     variables: { source_url: "https://default.com" },
                     execution: { max_iterations: 5, timeout_seconds: 3600 }
                   })
    agent.update!(api_key: "test_api_key_123")
    agent
  end
  let(:conversational_agent) do
    agent = create(:deployed_agent,
                   prompt_version: prompt_version)
    agent.update!(api_key: "test_api_key_456")
    agent
  end

  describe "POST #trigger" do
    context "with valid API key" do
      before do
        task_agent # Ensure agent is created before request
        request.headers["Authorization"] = "Bearer test_api_key_123"
      end

      it "creates a task run with default variables" do
        expect {
          post :trigger, params: { slug: task_agent.slug }, format: :json
        }.to change(PromptTracker::TaskRun, :count).by(1)

        task_run = PromptTracker::TaskRun.last
        expect(task_run.trigger_type).to eq("api")
        expect(task_run.variables_used).to eq({ "source_url" => "https://default.com" })
      end

      it "merges runtime variables with defaults" do
        post :trigger,
             params: {
               slug: task_agent.slug,
               variables: { source_url: "https://override.com", new_var: "value" }
             },
             format: :json

        task_run = PromptTracker::TaskRun.last
        expect(task_run.variables_used).to eq({
          "source_url" => "https://override.com",
          "new_var" => "value"
        })
      end

      it "returns task run details" do
        post :trigger, params: { slug: task_agent.slug }, format: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json.keys).to include("task_run_id", "status", "trigger_type", "variables_used", "created_at", "run_url")
        expect(json["status"]).to eq("queued")
        expect(json["trigger_type"]).to eq("api")
      end

      it "enqueues ExecuteTaskAgentJob" do
        expect {
          post :trigger, params: { slug: task_agent.slug }, format: :json
        }.to have_enqueued_job(PromptTracker::ExecuteTaskAgentJob).with(task_agent.id, kind_of(Integer))
      end
    end

    context "with invalid API key" do
      before do
        task_agent # Ensure agent is created before request
        request.headers["Authorization"] = "Bearer wrong_key"
      end

      it "returns unauthorized" do
        post :trigger, params: { slug: task_agent.slug }, format: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Invalid API key")
      end
    end

    context "without Authorization header" do
      it "returns unauthorized" do
        post :trigger, params: { slug: task_agent.slug }, format: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Missing or invalid Authorization header")
      end
    end

    context "with non-task agent" do
      before do
        conversational_agent # Ensure agent is created before request
        request.headers["Authorization"] = "Bearer test_api_key_456"
      end

      it "returns unprocessable entity" do
        post :trigger, params: { slug: conversational_agent.slug }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Agent is not a task agent")
        expect(json["agent_type"]).to eq("conversational")
      end
    end

    context "with non-existent agent" do
      before do
        request.headers["Authorization"] = "Bearer test_api_key_123"
      end

      it "returns not found" do
        post :trigger, params: { slug: "non-existent" }, format: :json

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Agent not found")
      end
    end
  end
end
