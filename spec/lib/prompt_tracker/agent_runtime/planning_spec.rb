# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module AgentRuntime
    RSpec.describe Planning do
      describe ".create_plan" do
        it "builds a plan with sequentially numbered steps" do
          result = described_class.create_plan(nil, { "goal" => "G", "steps" => %w[a b c] })

          expect(result["success"]).to be true
          expect(result["plan"]["status"]).to eq("in_progress")
          expect(result["plan"]["steps"].map { |s| s["id"] }).to eq(%w[step_1 step_2 step_3])
          expect(result["plan"]["steps"].first["status"]).to eq("pending")
        end

        it "rejects when a plan already exists" do
          existing = { "goal" => "x", "steps" => [] }
          result = described_class.create_plan(existing, { "goal" => "G", "steps" => [ "a" ] })

          expect(result["success"]).to be false
          expect(result["error"]).to match(/already exists/)
        end

        it "requires goal and steps" do
          expect(described_class.create_plan(nil, { "steps" => [ "a" ] })["success"]).to be false
          expect(described_class.create_plan(nil, { "goal" => "g" })["success"]).to be false
          expect(described_class.create_plan(nil, { "goal" => "g", "steps" => [] })["success"]).to be false
        end

        it "accepts symbol keys" do
          result = described_class.create_plan(nil, { goal: "G", steps: [ "a" ] })
          expect(result["success"]).to be true
        end
      end

      describe ".update_step" do
        let(:plan) do
          described_class.create_plan(nil, { "goal" => "G", "steps" => %w[a b] })["plan"]
        end

        it "updates status and timestamps" do
          result = described_class.update_step(plan, { "step_id" => "step_1", "status" => "in_progress" })

          expect(result["success"]).to be true
          expect(plan["steps"].first["status"]).to eq("in_progress")
          expect(plan["steps"].first["started_at"]).not_to be_nil
        end

        it "sets completed_at when terminal status" do
          described_class.update_step(plan, { "step_id" => "step_1", "status" => "completed" })
          expect(plan["steps"].first["completed_at"]).not_to be_nil
        end

        it "rejects unknown step_id" do
          result = described_class.update_step(plan, { "step_id" => "nope", "status" => "completed" })
          expect(result["success"]).to be false
        end

        it "rejects invalid status" do
          result = described_class.update_step(plan, { "step_id" => "step_1", "status" => "bogus" })
          expect(result["success"]).to be false
        end
      end

      describe ".add_step" do
        let(:plan) do
          described_class.create_plan(nil, { "goal" => "G", "steps" => %w[a b] })["plan"]
        end

        it "inserts after a given step_id and reorders" do
          described_class.add_step(plan, { "description" => "new", "after_step_id" => "step_1" })

          expect(plan["steps"].map { |s| s["description"] }).to eq(%w[a new b])
          expect(plan["steps"].map { |s| s["order"] }).to eq([ 1, 2, 3 ])
        end
      end

      describe ".mark_task_complete" do
        let(:plan) do
          described_class.create_plan(nil, { "goal" => "G", "steps" => [ "a" ] })["plan"]
        end

        it "sets plan status to completed and stores summary" do
          result = described_class.mark_task_complete(plan, { "summary" => "done" })

          expect(result["success"]).to be true
          expect(plan["status"]).to eq("completed")
          expect(plan["completion_summary"]).to eq("done")
        end

        it "requires a summary" do
          expect(described_class.mark_task_complete(plan, {})["success"]).to be false
        end
      end

      describe ".force_failure" do
        let(:plan) do
          plan = described_class.create_plan(nil, { "goal" => "G", "steps" => %w[a b] })["plan"]
          described_class.update_step(plan, { "step_id" => "step_1", "status" => "in_progress" })
          plan
        end

        it "marks in-progress steps as failed and the plan as failed" do
          described_class.force_failure(plan, "timeout")

          expect(plan["status"]).to eq("failed")
          expect(plan["steps"].first["status"]).to eq("failed")
          expect(plan["completion_summary"]).to include("timeout")
          expect(plan["completion_summary"]).to include("1 step")
        end
      end
    end
  end
end
