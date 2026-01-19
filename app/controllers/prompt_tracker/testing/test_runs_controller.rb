# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for viewing test run results.
    class TestRunsController < ApplicationController
      before_action :set_test_run, only: [ :show ]

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

      private

      def set_test_run
        @test_run = TestRun.find(params[:id])
      end
    end
  end
end
