# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Controller for viewing prompt versions in monitoring context
    # Shows tracked calls and evaluations for a specific version
    class PromptVersionsController < ApplicationController
      # GET /monitoring/prompts/:prompt_id/versions/:id
      # Show prompt version with all tracked calls and evaluations
      def show
        @prompt = Prompt.find(params[:prompt_id])
        @version = @prompt.prompt_versions.find(params[:id])

        # Get all tracked calls for this version
        @tracked_calls = LlmResponse.tracked_calls
                                    .where(prompt_version_id: @version.id)
                                    .includes(:evaluations, :human_evaluations)
                                    .order(created_at: :desc)

        # Apply filters
        if params[:environment].present?
          @tracked_calls = @tracked_calls.where(environment: params[:environment])
        end

        if params[:status].present?
          @tracked_calls = @tracked_calls.where(status: params[:status])
        end

        if params[:user_id].present?
          @tracked_calls = @tracked_calls.where(user_id: params[:user_id])
        end

        # Pagination
        @tracked_calls = @tracked_calls.page(params[:page]).per(20)

        # Statistics
        all_calls = LlmResponse.tracked_calls.where(prompt_version_id: @version.id)
        @total_calls = all_calls.count
        @successful_calls = all_calls.where(status: "success").count
        @failed_calls = all_calls.where(status: "error").count

        # Evaluation statistics
        all_evaluations = Evaluation.tracked.joins(:llm_response)
                                    .where(prompt_tracker_llm_responses: { prompt_version_id: @version.id })
        @total_evaluations = all_evaluations.count
        @passed_evaluations = all_evaluations.where(passed: true).count
        @failed_evaluations = all_evaluations.where(passed: false).count

        # Average score
        @avg_score = all_evaluations.average(:score)&.round(1) || 0

        # Get unique environments, users, and sessions for filters
        @environments = all_calls.distinct.pluck(:environment).compact.sort
        @user_ids = all_calls.distinct.pluck(:user_id).compact.sort
        @statuses = all_calls.distinct.pluck(:status).compact.sort

        # Get evaluator configs for this version
        @evaluator_configs = @version.evaluator_configs.enabled.order(created_at: :asc)

        # Check if there are test evaluators available to copy
        @has_test_evaluators = @version.tests.joins(:evaluator_configs).exists?
      end
    end
  end
end
