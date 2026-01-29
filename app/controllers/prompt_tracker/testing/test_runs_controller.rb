# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for viewing test run results.
    class TestRunsController < ApplicationController
      before_action :set_test_run, only: [ :show, :rerun ]

      # GET /testing/runs
      def index
        @test_runs = TestRun.includes(:test)
                            .order(created_at: :desc)
                            .page(params[:page])
                            .per(50)

        # Filter by status if provided
        if params[:status].present?
          @test_runs = @test_runs.where(status: params[:status])
        end

        # Filter by passed if provided
        if params[:passed].present?
          @test_runs = @test_runs.where(passed: params[:passed] == "true")
        end
      end

      # GET /testing/runs/:id
      def show
        @test = @test_run.test
        # TestRun now uses output_data for storing response information
        # Access via run.response_text, run.output_messages, etc.
      end

      # POST /testing/runs/:id/rerun
      # Re-run a test with the same configuration as the original run
      def rerun
        test = @test_run.test
        testable = test.testable

        # Extract configuration from the original test run (metadata uses string keys)
        run_mode = @test_run.metadata["run_mode"]
        custom_variables = @test_run.metadata["custom_variables"]

        # Build metadata for the new test run
        new_metadata = {
          "triggered_by" => "rerun",
          "user" => "web_ui",
          "original_test_run_id" => @test_run.id
        }

        # Add run_mode if present
        new_metadata["run_mode"] = run_mode if run_mode.present?

        # Add custom_variables if present
        new_metadata["custom_variables"] = custom_variables if custom_variables.present?

        # Create a new test run with the same configuration
        new_test_run = TestRun.create!(
          test: test,
          dataset: @test_run.dataset,
          dataset_row: @test_run.dataset_row,
          status: "running",
          metadata: new_metadata
        )

        # Enqueue the job
        RunTestJob.perform_later(new_test_run.id, use_real_llm: use_real_llm?)

        # Redirect back to the testable's show page with a success notice
        redirect_to testable_show_path(testable),
                    notice: "Test re-run queued successfully."
      end

      private

      def set_test_run
        @test_run = TestRun.find(params[:id])
      end

      # Check if real LLM API calls should be used
      def use_real_llm?
        ENV["PROMPT_TRACKER_USE_REAL_LLM"] == "true"
      end

      # Get the path to the testable's show page
      def testable_show_path(testable)
        case testable
        when PromptVersion
          testing_prompt_prompt_version_path(testable.prompt, testable)
        when PromptTracker::Openai::Assistant
          testing_openai_assistant_path(testable)
        else
          testing_runs_path
        end
      end
    end
  end
end
