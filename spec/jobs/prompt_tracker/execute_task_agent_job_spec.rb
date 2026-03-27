# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ExecuteTaskAgentJob, type: :job do
  let(:prompt_version) do
    create(:prompt_version,
           system_prompt: "You are a helpful task automation assistant.",
           model_config: {
             provider: "openai",
             model: "gpt-4",
             temperature: 0.7
           })
  end

  let(:task_agent) do
    create(:deployed_agent,
           :task_agent,
           :with_functions,
           prompt_version: prompt_version,
           task_config: {
             initial_prompt: "Process data",
             execution: {
               max_iterations: 3,
               timeout_seconds: 60
             }
           })
  end

  describe "#perform" do
    context "with existing task run" do
      it "executes the task agent with the provided task run" do
        task_run = create(:task_run, deployed_agent: task_agent)

        # Mock the runtime service
        expect(PromptTracker::TaskAgentRuntimeService).to receive(:call).with(
          task_agent: task_agent,
          task_run: task_run,
          variables: nil
        ).and_return({ success: true, output: "Task completed" })

        described_class.perform_now(task_agent.id, task_run.id)
      end

      it "passes variables to the runtime service" do
        task_run = create(:task_run, deployed_agent: task_agent)
        variables = { url: "https://example.com" }

        expect(PromptTracker::TaskAgentRuntimeService).to receive(:call).with(
          task_agent: task_agent,
          task_run: task_run,
          variables: variables
        ).and_return({ success: true, output: "Task completed" })

        described_class.perform_now(task_agent.id, task_run.id, variables: variables)
      end
    end

    context "without existing task run (scheduled execution)" do
      it "creates a new task run with scheduled trigger" do
        expect {
          # Mock the runtime service
          allow(PromptTracker::TaskAgentRuntimeService).to receive(:call).and_return({ success: true, output: "Done" })

          described_class.perform_now(task_agent.id, nil, trigger_type: "scheduled")
        }.to change(PromptTracker::TaskRun, :count).by(1)

        task_run = PromptTracker::TaskRun.last
        expect(task_run.deployed_agent).to eq(task_agent)
        expect(task_run.trigger_type).to eq("scheduled")
      end

      it "creates a new task run with manual trigger by default" do
        expect {
          allow(PromptTracker::TaskAgentRuntimeService).to receive(:call).and_return({ success: true, output: "Done" })

          described_class.perform_now(task_agent.id, nil)
        }.to change(PromptTracker::TaskRun, :count).by(1)

        task_run = PromptTracker::TaskRun.last
        expect(task_run.trigger_type).to eq("manual")
      end
    end

    context "with non-task agent" do
      it "logs error and returns without executing" do
        conversational_agent = create(:deployed_agent, :conversational)

        expect(PromptTracker::TaskAgentRuntimeService).not_to receive(:call)
        expect(Rails.logger).to receive(:error).with(/is not a task agent/)

        described_class.perform_now(conversational_agent.id, nil)
      end
    end

    context "when execution fails" do
      it "marks task run as failed and re-raises exception" do
        task_run = create(:task_run, deployed_agent: task_agent, status: "running")

        allow(PromptTracker::TaskAgentRuntimeService).to receive(:call).and_raise(StandardError, "Execution failed")

        expect {
          described_class.perform_now(task_agent.id, task_run.id)
        }.to raise_error(StandardError, "Execution failed")

        expect(task_run.reload.status).to eq("failed")
        expect(task_run.error_message).to eq("Execution failed")
      end
    end
  end
end
