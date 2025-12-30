# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for viewing prompt versions in the Testing section
    class PromptVersionsController < ApplicationController
    before_action :set_prompt
    before_action :set_version, only: [ :show, :compare, :activate ]

    # Make path helpers available to views
    helper_method :load_more_runs_path, :run_test_path, :datasets_path

    # GET /prompts/:prompt_id/versions/:id
    # Show version details with tests
    def show
      @tests = @version.tests.includes(:test_runs).order(created_at: :desc)

      # Calculate metrics scoped to test calls only (not production tracked calls)
      test_responses = @version.llm_responses.test_calls
      @total_calls = test_responses.count
      @avg_response_time = test_responses.average(:response_time_ms)
      @total_cost = test_responses.sum(:cost_usd)

      # Calculate average score from evaluations on test calls
      test_evaluations = @version.evaluations.joins(:llm_response).merge(LlmResponse.test_calls)
      @avg_score = test_evaluations.any? ? test_evaluations.average(:score) : nil

      # Calculate test pass/fail counts
      @tests_passing = @tests.select(&:passing?).count
      @tests_failing = @tests.reject(&:passing?).count
      @total_tests = @tests.count
    end

    # GET /prompts/:prompt_id/versions/:id/compare
    # Compare this version with another
    def compare
      # Get comparison version (from params or default to previous version)
      if params[:compare_with].present?
        @compare_version = @prompt.prompt_versions.find(params[:compare_with])
      else
        # Default to previous version
        @compare_version = @prompt.prompt_versions
                                  .where("version_number < ?", @version.version_number)
                                  .order(version_number: :desc)
                                  .first
      end

      if @compare_version
        # Calculate metrics for both versions
        @version_metrics = calculate_version_metrics(@version)
        @compare_metrics = calculate_version_metrics(@compare_version)

        # Calculate differences
        @metrics_diff = {
          calls: @version_metrics[:calls] - @compare_metrics[:calls],
          avg_response_time: @version_metrics[:avg_response_time].to_f - @compare_metrics[:avg_response_time].to_f,
          total_cost: @version_metrics[:total_cost].to_f - @compare_metrics[:total_cost].to_f,
          avg_score: (@version_metrics[:avg_score].to_f - @compare_metrics[:avg_score].to_f).round(2)
        }
      end

      # Get all versions for comparison dropdown
      @all_versions = @prompt.prompt_versions.order(version_number: :desc)
    end

    # POST /prompts/:prompt_id/versions/:id/activate
    # Activate this version and deprecate all others
    def activate
      unless @version.draft? || @version.deprecated?
        redirect_to testing_prompt_prompt_version_path(@prompt, @version), alert: "Version is already active."
        return
      end

      @version.activate!
      redirect_to testing_prompt_prompt_version_path(@prompt, @version), notice: "Version activated successfully."
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:prompt_id])
    end

    def set_version
      @version = @prompt.prompt_versions.includes(:llm_responses).find(params[:id])
    end

    def calculate_version_metrics(version)
      # Scope to test calls only
      test_responses = version.llm_responses.test_calls
      test_evaluations = version.evaluations.joins(:llm_response).merge(LlmResponse.test_calls)

      {
        calls: test_responses.count,
        avg_response_time: test_responses.average(:response_time_ms) || 0,
        total_cost: test_responses.sum(:cost_usd) || 0,
        avg_score: test_evaluations.any? ? test_evaluations.average(:score) : 0
      }
    end

    # Helper method for generating load_more_runs path
    def load_more_runs_path(test, offset:, limit:)
      load_more_runs_testing_prompt_version_test_path(@version, test, offset: offset, limit: limit)
    end

    # Helper method for generating run_test path
    def run_test_path(test)
      run_testing_prompt_version_test_path(@version, test)
    end

    # Helper method for generating datasets path
    def datasets_path
      testing_prompt_prompt_version_datasets_path(@prompt, @version)
    end
    end
  end
end
