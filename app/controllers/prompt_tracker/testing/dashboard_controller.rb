# frozen_string_literal: true

module PromptTracker
  module Testing
    # Dashboard for the Testing section - pre-deployment validation
    #
    # Shows unified index of all testables:
    # - PromptVersions (with their prompts)
    # - OpenAI Assistants
    #
    # Supports filtering by testable type
    #
    class DashboardController < ApplicationController
      def index
        # Filter by testable type (all, prompts, assistants)
        @filter = params[:filter] || "all"

        # Load prompts with their versions and test data
        if @filter.in?([ "all", "prompts" ])
          @prompts = Prompt.includes(
            prompt_versions: [
              :tests,
              { tests: :test_runs }
            ]
          ).order(created_at: :desc)
        else
          @prompts = []
        end

        # Assistants are now PromptVersions with api: "assistants"
        # No separate assistant list needed
        @assistants = []

        # Calculate statistics
        calculate_statistics
      end

      # POST /testing/sync_openai_assistants
      # Sync all assistants from OpenAI API
      def sync_openai_assistants
        result = SyncOpenaiAssistantsToPromptVersionsService.new.call

        if result[:success]
          redirect_to testing_root_path(filter: "assistants"),
                      notice: "Synced #{result[:created_count]} assistants from OpenAI."
        else
          redirect_to testing_root_path,
                      alert: "Failed to sync assistants: #{result[:errors].join(', ')}"
        end
      rescue SyncOpenaiAssistantsToPromptVersionsService::SyncError => e
        redirect_to testing_root_path,
                    alert: "Failed to sync assistants: #{e.message}"
      end

      private

      def calculate_statistics
        # Test statistics for summary
        @total_tests = Test.count
        @total_runs_today = TestRun.where("created_at >= ?", Time.current.beginning_of_day).count

        # Pass/fail rates (last 100 runs)
        recent_runs = TestRun.order(created_at: :desc).limit(100)
        @pass_rate = if recent_runs.any?
          (recent_runs.where(status: "passed").count.to_f / recent_runs.count * 100).round(1)
        else
          0
        end

        # Count by testable type
        @prompt_count = Prompt.count
        @assistant_count = 0 # Assistants are now PromptVersions
      end
    end
  end
end
