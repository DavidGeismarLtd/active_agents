# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Controller for viewing tracked evaluations (runtime calls from all environments)
    class EvaluationsController < ApplicationController
      # GET /monitoring/evaluations
      # List all tracked evaluations with filtering
      def index
        @evaluations = Evaluation.tracked
                                 .includes(llm_response: { prompt_version: :prompt })
                                 .order(created_at: :desc)

        # Filter by passed/failed
        if params[:passed].present?
          @evaluations = @evaluations.where(passed: params[:passed] == "true")
        end

        # Filter by evaluator_type
        if params[:evaluator_type].present?
          @evaluations = @evaluations.where(evaluator_type: params[:evaluator_type])
        end

        # Filter by evaluator_name
        if params[:evaluator_name].present?
          @evaluations = @evaluations.where("evaluator_name ILIKE ?", "%#{params[:evaluator_name]}%")
        end

        # Filter by prompt
        if params[:prompt_id].present?
          @evaluations = @evaluations.joins(llm_response: { prompt_version: :prompt })
                                     .where(prompt_tracker_prompts: { id: params[:prompt_id] })
        end

        # Filter by environment
        if params[:environment].present?
          @evaluations = @evaluations.joins(:llm_response)
                                     .where(prompt_tracker_llm_responses: { environment: params[:environment] })
        end

        # Filter by user_id
        if params[:user_id].present?
          @evaluations = @evaluations.joins(:llm_response)
                                     .where(prompt_tracker_llm_responses: { user_id: params[:user_id] })
        end

        # Filter by session_id
        if params[:session_id].present?
          @evaluations = @evaluations.joins(:llm_response)
                                     .where(prompt_tracker_llm_responses: { session_id: params[:session_id] })
        end

        # Date range filter
        if params[:start_date].present?
          @evaluations = @evaluations.where("prompt_tracker_evaluations.created_at >= ?", params[:start_date])
        end
        if params[:end_date].present?
          @evaluations = @evaluations.where("prompt_tracker_evaluations.created_at <= ?", params[:end_date])
        end

        # Pagination
        @evaluations = @evaluations.page(params[:page]).per(50)

        # Get filter options
        @prompts = Prompt.active.order(:name)
        @evaluator_types = EvaluatorRegistry.all.values.map { |meta| meta[:evaluator_class].name }.uniq.sort
        @environments = LlmResponse.tracked_calls.distinct.pluck(:environment).compact.sort
        @user_ids = LlmResponse.tracked_calls.distinct.pluck(:user_id).compact.sort
        @session_ids = LlmResponse.tracked_calls.distinct.pluck(:session_id).compact.sort

        # Calculate summary stats
        @total_evaluations = @evaluations.total_count
        @passing_count = Evaluation.tracked.where(passed: true).count
        @failing_count = Evaluation.tracked.where(passed: false).count
      end

      # GET /monitoring/evaluations/:id
      # Show evaluation details (monitoring context - runtime calls)
      def show
        @evaluation = Evaluation.tracked.includes(:human_evaluations, llm_response: { prompt_version: :prompt }).find(params[:id])
        @response = @evaluation.llm_response
        @version = @response.prompt_version
        @prompt = @version.prompt
        @monitoring_context = true  # Flag to indicate we're in monitoring context

        # Reuse the shared template
        render "prompt_tracker/evaluations/show"
      end
    end
  end
end
