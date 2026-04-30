# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe PlanningService do
    let(:agent_version) { create(:agent_version, :with_chat_completions) }
    let(:deployed_agent) { create(:deployed_agent, :task_agent, agent_version: agent_version) }
    let(:task_run) { create(:task_run, :running, deployed_agent: deployed_agent) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    describe ".create_plan" do
      it "persists the plan to task_run.metadata and broadcasts" do
        result = described_class.create_plan(task_run, { "goal" => "G", "steps" => %w[a b] })

        expect(result[:success]).to be true
        task_run.reload
        expect(task_run.metadata["plan"]).to be_present
        expect(task_run.metadata.dig("plan", "goal")).to eq("G")
        expect(task_run.metadata.dig("plan", "steps").size).to eq(2)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      end

      it "rejects when a plan already exists" do
        described_class.create_plan(task_run, { "goal" => "G", "steps" => [ "a" ] })

        result = described_class.create_plan(task_run, { "goal" => "Other", "steps" => [ "b" ] })

        expect(result[:success]).to be false
        expect(result[:error]).to match(/already exists/)
      end
    end

    describe ".update_step" do
      before do
        described_class.create_plan(task_run, { "goal" => "G", "steps" => %w[a b] })
      end

      it "updates the step status and broadcasts" do
        result = described_class.update_step(task_run, { "step_id" => "step_1", "status" => "in_progress" })

        expect(result[:success]).to be true
        task_run.reload
        expect(task_run.metadata.dig("plan", "steps", 0, "status")).to eq("in_progress")
      end

      it "returns failure for an unknown step_id" do
        result = described_class.update_step(task_run, { "step_id" => "nope", "status" => "completed" })
        expect(result[:success]).to be false
      end
    end

    describe ".add_step" do
      before do
        described_class.create_plan(task_run, { "goal" => "G", "steps" => %w[a b] })
      end

      it "inserts a new step after the given id and persists" do
        described_class.add_step(task_run, { "description" => "new", "after_step_id" => "step_1" })

        task_run.reload
        descriptions = task_run.metadata.dig("plan", "steps").map { |s| s["description"] }
        expect(descriptions).to eq(%w[a new b])
      end
    end

    describe ".mark_task_complete" do
      before do
        described_class.create_plan(task_run, { "goal" => "G", "steps" => [ "a" ] })
      end

      it "marks the plan completed and writes output_summary" do
        result = described_class.mark_task_complete(task_run, { "summary" => "all done" })

        expect(result[:success]).to be true
        task_run.reload
        expect(task_run.metadata.dig("plan", "status")).to eq("completed")
        expect(task_run.output_summary).to eq("all done")
      end
    end

    describe ".force_failure!" do
      before do
        described_class.create_plan(task_run, { "goal" => "G", "steps" => %w[a b] })
        described_class.update_step(task_run, { "step_id" => "step_1", "status" => "in_progress" })
      end

      it "marks the plan failed with the supplied reason" do
        described_class.force_failure!(task_run, "timeout reached")

        task_run.reload
        expect(task_run.metadata.dig("plan", "status")).to eq("failed")
        expect(task_run.metadata.dig("plan", "completion_summary")).to include("timeout reached")
        # The step that was in_progress should be auto-failed.
        expect(task_run.metadata.dig("plan", "steps", 0, "status")).to eq("failed")
      end
    end
  end
end
