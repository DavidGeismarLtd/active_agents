# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskRunsController, type: :controller do
  routes { PromptTracker::Engine.routes }

  let(:task_agent) { create(:deployed_agent, :task_agent) }
  let(:task_run) { create(:task_run, deployed_agent: task_agent) }

  describe "GET #index" do
    it "returns a successful response" do
      get :index, params: { deployed_agent_slug: task_agent.slug }
      expect(response).to be_successful
    end

    it "assigns @task_runs" do
      task_run # create the task run
      get :index, params: { deployed_agent_slug: task_agent.slug }
      expect(assigns(:task_runs)).to include(task_run)
    end

    it "filters by status" do
      completed_run = create(:task_run, deployed_agent: task_agent, status: "completed")
      failed_run = create(:task_run, deployed_agent: task_agent, status: "failed")

      get :index, params: { deployed_agent_slug: task_agent.slug, status: "completed" }
      expect(assigns(:task_runs)).to include(completed_run)
      expect(assigns(:task_runs)).not_to include(failed_run)
    end

    it "filters by trigger_type" do
      manual_run = create(:task_run, deployed_agent: task_agent, trigger_type: "manual")
      scheduled_run = create(:task_run, deployed_agent: task_agent, trigger_type: "scheduled")

      get :index, params: { deployed_agent_slug: task_agent.slug, trigger_type: "manual" }
      expect(assigns(:task_runs)).to include(manual_run)
      expect(assigns(:task_runs)).not_to include(scheduled_run)
    end
  end

  describe "GET #show" do
    it "returns a successful response" do
      get :show, params: { deployed_agent_slug: task_agent.slug, id: task_run.id }
      expect(response).to be_successful
    end

    it "assigns @task_run" do
      get :show, params: { deployed_agent_slug: task_agent.slug, id: task_run.id }
      expect(assigns(:task_run)).to eq(task_run)
    end

    it "builds timeline from LLM responses and function executions" do
      llm_response = create(:llm_response,
                            deployed_agent: task_agent,
                            task_run: task_run,
                            context: { "iteration" => 1 })
      function_execution = create(:function_execution,
                                  deployed_agent: task_agent,
                                  task_run: task_run)

      get :show, params: { deployed_agent_slug: task_agent.slug, id: task_run.id }
      timeline = assigns(:timeline)

      # Timeline is an array of iterations
      expect(timeline).to be_an(Array)
      expect(timeline.length).to eq(1)  # All events grouped into one iteration

      # Each iteration has events
      iteration = timeline.first
      expect(iteration[:events].length).to eq(2)
      expect(iteration[:events].map { |e| e[:type] }).to contain_exactly(:llm_response, :function_execution)
    end
  end
end
