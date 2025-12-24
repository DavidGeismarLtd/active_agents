# frozen_string_literal: true

module PromptTracker
  # Controller for viewing test run results.
  class PromptTestRunsController < ApplicationController
    before_action :set_test_run, only: [ :show ]

    # GET /test-runs
    def index
      @test_runs = TestRun.includes(:test, :prompt_version)
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

    # GET /test-runs/:id
    def show
      @test = @test_run.test
      @version = @test_run.prompt_version
      @llm_response = @test_run.llm_response
    end

    private

    def set_test_run
      @test_run = TestRun.find(params[:id])
    end
  end
end
