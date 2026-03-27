# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task Agent System - Phase 1", type: :model do
  describe "DeployedAgent with task type" do
    it "creates a task agent with proper configuration" do
      agent = create(:deployed_agent, :task_agent)

      expect(agent.agent_type).to eq("task")
      expect(agent.agent_type_task?).to be true
      expect(agent.task_config).to be_present
      expect(agent.task_config[:initial_prompt]).to be_present
      expect(agent.task_configuration).to be_a(Hash)
      expect(agent.task_configuration[:execution][:max_iterations]).to eq(5)
    end

    it "validates task_config presence for task agents" do
      agent = build(:deployed_agent, agent_type: "task", task_config: {})

      expect(agent).not_to be_valid
      expect(agent.errors[:task_config]).to include("must include initial_prompt for task agents")
    end

    it "has task-specific associations" do
      agent = create(:deployed_agent, :task_agent)

      expect(agent).to respond_to(:task_runs)
      expect(agent).to respond_to(:task_schedule)
    end

    it "uses task_config instead of deployment_config" do
      agent = create(:deployed_agent, :task_agent)

      expect(agent.config).to eq(agent.task_config.deep_symbolize_keys)
    end
  end

  describe "TaskRun lifecycle" do
    let(:agent) { create(:deployed_agent, :task_agent) }
    let(:task_run) { create(:task_run, deployed_agent: agent) }

    it "starts in queued status" do
      expect(task_run.status).to eq("queued")
      expect(task_run.status_queued?).to be true
    end

    it "transitions through lifecycle states" do
      # Start
      task_run.start!
      expect(task_run.status).to eq("running")
      expect(task_run.started_at).to be_present

      # Increment iteration
      task_run.increment_iteration!
      expect(task_run.iterations_count).to eq(1)

      # Complete
      task_run.complete!(output: "Successfully processed 23 items")
      expect(task_run.status).to eq("completed")
      expect(task_run.output_summary).to eq("Successfully processed 23 items")
      expect(task_run.completed_at).to be_present
      expect(task_run.finished?).to be true
      expect(task_run.successful?).to be true
    end

    it "handles failure state" do
      task_run.start!
      task_run.fail!(error: "Connection timeout")

      expect(task_run.status).to eq("failed")
      expect(task_run.error_message).to eq("Connection timeout")
      expect(task_run.finished?).to be true
      expect(task_run.successful?).to be false
    end

    it "calculates duration" do
      task_run.start!
      sleep 0.1
      task_run.complete!(output: "Done")

      expect(task_run.duration).to be > 0
    end

    it "updates stats from associated records" do
      task_run.start!

      # Create associated records
      create_list(:llm_response, 3, task_run: task_run, deployed_agent: agent, cost_usd: 0.01)
      create_list(:function_execution, 5, task_run: task_run, deployed_agent: agent)

      task_run.update_stats!

      expect(task_run.llm_calls_count).to eq(3)
      expect(task_run.function_calls_count).to eq(5)
      expect(task_run.total_cost_usd).to eq(0.03)
    end
  end

  describe "TaskSchedule" do
    let(:agent) { create(:deployed_agent, :task_agent) }

    it "creates an interval-based schedule" do
      schedule = create(:task_schedule, deployed_agent: agent, interval_value: 6, interval_unit: "hours")

      expect(schedule.schedule_type).to eq("interval")
      expect(schedule.interval_value).to eq(6)
      expect(schedule.interval_unit).to eq("hours")
      expect(schedule.enabled?).to be true
      expect(schedule.next_run_at).to be_present
    end

    it "creates a cron-based schedule" do
      schedule = create(:task_schedule, :cron_based, deployed_agent: agent)

      expect(schedule.schedule_type).to eq("cron")
      expect(schedule.cron_expression).to eq("0 9 * * *")
      expect(schedule.next_run_at).to be_present
    end

    it "can be enabled and disabled" do
      schedule = create(:task_schedule, deployed_agent: agent)

      schedule.disable!
      expect(schedule.enabled?).to be false

      schedule.enable!
      expect(schedule.enabled?).to be true
    end

    it "records run history" do
      schedule = create(:task_schedule, deployed_agent: agent)
      initial_run_count = schedule.run_count

      schedule.record_run!

      expect(schedule.run_count).to eq(initial_run_count + 1)
      expect(schedule.last_run_at).to be_present
      expect(schedule.next_run_at).to be_present
    end

    it "detects overdue schedules" do
      schedule = create(:task_schedule, :overdue, deployed_agent: agent)

      expect(schedule.overdue?).to be true
    end
  end

  describe "Scopes" do
    before do
      create(:deployed_agent, :task_agent)
      create(:deployed_agent, :task_agent)
      create(:deployed_agent) # conversational
    end

    it "filters task agents" do
      expect(PromptTracker::DeployedAgent.task_agents.count).to eq(2)
      expect(PromptTracker::DeployedAgent.conversational_agents.count).to eq(1)
    end
  end

  describe "Factories" do
    it "creates task agent with functions" do
      agent = create(:deployed_agent, :task_agent, :with_functions)

      expect(agent.function_definitions.count).to eq(3)
    end

    it "creates task agent with task runs" do
      agent = create(:deployed_agent, :task_agent, :with_task_runs)

      expect(agent.task_runs.count).to eq(3)
    end

    it "creates task agent with schedule" do
      agent = create(:deployed_agent, :task_agent, :with_schedule)

      expect(agent.task_schedule).to be_present
    end
  end
end
