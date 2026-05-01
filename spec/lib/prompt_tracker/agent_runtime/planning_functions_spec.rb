# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module AgentRuntime
    RSpec.describe PlanningFunctions do
      describe ".planning_phase_functions" do
        it "exposes only create_plan" do
          functions = described_class.planning_phase_functions
          expect(functions.size).to eq(1)
          expect(functions.first["name"]).to eq("create_plan")
        end

        it "create_plan requires goal and steps" do
          schema = described_class.planning_phase_functions.first
          expect(schema.dig("parameters", "required")).to contain_exactly("goal", "steps")
        end
      end

      describe ".execution_phase_functions" do
        it "exposes get_plan, update_step, add_step, mark_task_complete (NOT create_plan)" do
          names = described_class.execution_phase_functions.map { |f| f["name"] }
          expect(names).to contain_exactly("get_plan", "update_step", "add_step", "mark_task_complete")
        end
      end

      describe ".planning_function?" do
        it "returns true for any planning function name" do
          %w[create_plan get_plan update_step add_step mark_task_complete].each do |name|
            expect(described_class.planning_function?(name)).to be true
          end
        end

        it "returns false for unrelated names" do
          expect(described_class.planning_function?("fetch_news")).to be false
          expect(described_class.planning_function?("filesystem__read_file")).to be false
        end
      end
    end
  end
end
