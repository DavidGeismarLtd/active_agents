# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module AgentRuntime
    RSpec.describe PromptEnhancer do
      describe ".with_planning" do
        it "appends planning-phase instructions when phase=:planning" do
          out = described_class.with_planning("BASE", phase: :planning)
          expect(out).to start_with("BASE")
          expect(out).to include("PLANNING PHASE")
          expect(out).to include("create_plan")
        end

        it "appends execution-phase instructions when phase=:execution" do
          out = described_class.with_planning("BASE", phase: :execution)
          expect(out).to include("EXECUTION PHASE")
          expect(out).to include("mark_task_complete")
          expect(out).not_to include("PLANNING PHASE")
        end
      end

      describe ".with_iteration_context" do
        it "returns the prompt unchanged when max_iterations is nil" do
          out = described_class.with_iteration_context("BASE", iteration: 1, max_iterations: nil)
          expect(out).to eq("BASE")
        end

        it "returns the prompt unchanged when iteration is 0" do
          out = described_class.with_iteration_context("BASE", iteration: 0, max_iterations: 5)
          expect(out).to eq("BASE")
        end

        it "uses standard wording when there is plenty of budget" do
          out = described_class.with_iteration_context("BASE", iteration: 2, max_iterations: 5)
          expect(out).to include("3 iterations remaining")
          expect(out).not_to include("ALMOST OUT OF TIME")
          expect(out).not_to include("FINAL ITERATION")
        end

        it "uses penultimate wording when one iteration remains" do
          out = described_class.with_iteration_context("BASE", iteration: 4, max_iterations: 5)
          expect(out).to include("ALMOST OUT OF TIME")
        end

        it "uses final-iteration wording when at or beyond the limit" do
          out = described_class.with_iteration_context("BASE", iteration: 5, max_iterations: 5)
          expect(out).to include("FINAL ITERATION")
          expect(out).to include("mark_task_complete")
        end
      end
    end
  end
end
