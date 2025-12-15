# frozen_string_literal: true

module PromptTracker
  module Testing
    # Dashboard for the Testing section - pre-deployment validation
    #
    # Shows overview of:
    # - All prompts with their versions
    # - Test results per version
    # - Quick access to create new prompts
    #
    class DashboardController < ApplicationController
      def index
        # Load all prompts with their versions and test data
        # Eager load to avoid N+1 queries
        @prompts = Prompt.includes(
          prompt_versions: [
            :prompt_tests,
            { prompt_tests: :prompt_test_runs }
          ]
        ).order(created_at: :desc)

        # Test statistics for summary
        @total_tests = PromptTest.count
        @total_runs_today = PromptTestRun.where("created_at >= ?", Time.current.beginning_of_day).count

        # Pass/fail rates (last 100 runs)
        recent_runs = PromptTestRun.order(created_at: :desc).limit(100)
        @pass_rate = if recent_runs.any?
          (recent_runs.where(status: "passed").count.to_f / recent_runs.count * 100).round(1)
        else
          0
        end
      end
    end
  end
end
