# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskSchedulesController, type: :controller do
  routes { PromptTracker::Engine.routes }

  let(:task_agent) { create(:deployed_agent, :task_agent) }
  let(:conversational_agent) { create(:deployed_agent) }

  describe "GET #new" do
    it "returns a successful response for task agents" do
      get :new, params: { deployed_agent_slug: task_agent.slug }
      expect(response).to be_successful
    end

    it "redirects for conversational agents" do
      get :new, params: { deployed_agent_slug: conversational_agent.slug }
      expect(response).to redirect_to(deployed_agent_path(conversational_agent.slug))
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        deployed_agent_slug: task_agent.slug,
        task_schedule: {
          schedule_type: "cron",
          cron_expression: "0 9 * * *",
          timezone: "UTC",
          enabled: true
        }
      }
    end

    it "creates a new schedule" do
      expect {
        post :create, params: valid_params
      }.to change(PromptTracker::TaskSchedule, :count).by(1)
    end

    it "redirects to the agent show page" do
      post :create, params: valid_params
      expect(response).to redirect_to(deployed_agent_path(task_agent.slug))
    end

    it "does not create schedule for conversational agents" do
      expect {
        post :create, params: valid_params.merge(deployed_agent_slug: conversational_agent.slug)
      }.not_to change(PromptTracker::TaskSchedule, :count)
    end
  end

  describe "GET #edit" do
    let(:schedule) { create(:task_schedule, deployed_agent: task_agent) }

    it "returns a successful response" do
      get :edit, params: { deployed_agent_slug: task_agent.slug, id: schedule.id }
      expect(response).to be_successful
    end
  end

  describe "PATCH #update" do
    let(:schedule) { create(:task_schedule, deployed_agent: task_agent, enabled: true) }

    it "updates the schedule" do
      patch :update, params: {
        deployed_agent_slug: task_agent.slug,
        id: schedule.id,
        task_schedule: { enabled: false }
      }
      schedule.reload
      expect(schedule.enabled).to be false
    end

    it "redirects to the agent show page" do
      patch :update, params: {
        deployed_agent_slug: task_agent.slug,
        id: schedule.id,
        task_schedule: { enabled: false }
      }
      expect(response).to redirect_to(deployed_agent_path(task_agent.slug))
    end
  end

  describe "DELETE #destroy" do
    let!(:schedule) { create(:task_schedule, deployed_agent: task_agent) }

    it "destroys the schedule" do
      expect {
        delete :destroy, params: { deployed_agent_slug: task_agent.slug, id: schedule.id }
      }.to change(PromptTracker::TaskSchedule, :count).by(-1)
    end

    it "redirects to the agent show page" do
      delete :destroy, params: { deployed_agent_slug: task_agent.slug, id: schedule.id }
      expect(response).to redirect_to(deployed_agent_path(task_agent.slug))
    end
  end

  describe "POST #toggle" do
    let(:schedule) { create(:task_schedule, deployed_agent: task_agent, enabled: true) }

    it "toggles the enabled status" do
      post :toggle, params: { deployed_agent_slug: task_agent.slug, id: schedule.id }
      schedule.reload
      expect(schedule.enabled).to be false
    end

    it "redirects to the agent show page" do
      post :toggle, params: { deployed_agent_slug: task_agent.slug, id: schedule.id }
      expect(response).to redirect_to(deployed_agent_path(task_agent.slug))
    end
  end
end
