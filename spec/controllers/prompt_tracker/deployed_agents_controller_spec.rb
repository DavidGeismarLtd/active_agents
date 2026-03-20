# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::DeployedAgentsController, type: :controller do
  routes { PromptTracker::Engine.routes }

  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt) }
  let(:agent) { create(:deployed_agent, prompt_version: version) }

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns @agents" do
      agent # create the agent
      get :index
      expect(assigns(:agents)).to include(agent)
    end

    it "filters by status" do
      active_agent = create(:deployed_agent, status: "active")
      paused_agent = create(:deployed_agent, status: "paused")

      get :index, params: { status: "active" }
      expect(assigns(:agents)).to include(active_agent)
      expect(assigns(:agents)).not_to include(paused_agent)
    end
  end

  describe "GET #show" do
    it "returns a successful response" do
      get :show, params: { slug: agent.slug }
      expect(response).to be_successful
    end

    it "assigns @agent" do
      get :show, params: { slug: agent.slug }
      expect(assigns(:agent)).to eq(agent)
    end
  end

  describe "GET #new" do
    it "returns a successful response" do
      get :new, params: { prompt_version_id: version.id }
      expect(response).to be_successful
    end

    it "assigns @agent with defaults" do
      get :new, params: { prompt_version_id: version.id }
      expect(assigns(:agent)).to be_a_new(PromptTracker::DeployedAgent)
      expect(assigns(:agent).prompt_version).to eq(version)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        deployed_agent: {
          prompt_version_id: version.id,
          name: "Test Agent",
          deployment_config: {
            conversation_ttl: 3600,
            rate_limit: { requests_per_minute: 60 },
            auth: { type: "api_key" },
            cors: { allowed_origins: "https://example.com" }
          }
        }
      }
    end

    it "creates a new agent" do
      expect {
        post :create, params: valid_params
      }.to change(PromptTracker::DeployedAgent, :count).by(1)
    end

    it "redirects to the agent show page" do
      post :create, params: valid_params
      expect(response).to redirect_to(deployed_agent_path(PromptTracker::DeployedAgent.last.slug))
    end

    it "displays the API key in the flash message" do
      post :create, params: valid_params
      expect(flash[:notice]).to include("API Key:")
    end
  end

  describe "PATCH #update" do
    let(:update_params) do
      {
        slug: agent.slug,
        deployed_agent: {
          name: "Updated Name",
          deployment_config: agent.deployment_config
        }
      }
    end

    it "updates the agent" do
      patch :update, params: update_params
      agent.reload
      expect(agent.name).to eq("Updated Name")
    end

    it "redirects to the agent show page" do
      patch :update, params: update_params
      expect(response).to redirect_to(deployed_agent_path(agent.slug))
    end
  end

  describe "DELETE #destroy" do
    it "destroys the agent" do
      agent # create the agent
      expect {
        delete :destroy, params: { slug: agent.slug }
      }.to change(PromptTracker::DeployedAgent, :count).by(-1)
    end

    it "redirects to the agents index" do
      delete :destroy, params: { slug: agent.slug }
      expect(response).to redirect_to(deployed_agents_path)
    end
  end

  describe "POST #pause" do
    it "pauses the agent" do
      post :pause, params: { slug: agent.slug }
      agent.reload
      expect(agent.status).to eq("paused")
    end

    it "redirects to the agent show page" do
      post :pause, params: { slug: agent.slug }
      expect(response).to redirect_to(deployed_agent_path(agent.slug))
    end
  end

  describe "POST #resume" do
    let(:paused_agent) { create(:deployed_agent, status: "paused") }

    it "resumes the agent" do
      post :resume, params: { slug: paused_agent.slug }
      paused_agent.reload
      expect(paused_agent.status).to eq("active")
    end

    it "redirects to the agent show page" do
      post :resume, params: { slug: paused_agent.slug }
      expect(response).to redirect_to(deployed_agent_path(paused_agent.slug))
    end
  end
end
