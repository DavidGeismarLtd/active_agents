# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Controller for viewing tracked LLM responses (runtime calls from all environments)
    class LlmResponsesController < ApplicationController
      # GET /monitoring/responses
      # List all tracked LLM responses with filtering
      def index
        @responses = LlmResponse.tracked_calls
                                .includes(:evaluations, :human_evaluations, prompt_version: :prompt)
                                .order(created_at: :desc)

        # Filter by prompt
        if params[:prompt_id].present?
          @responses = @responses.joins(prompt_version: :prompt)
                                 .where(prompt_tracker_prompts: { id: params[:prompt_id] })
        end

        # Filter by provider
        if params[:provider].present?
          @responses = @responses.where(provider: params[:provider])
        end

        # Filter by model
        if params[:model].present?
          @responses = @responses.where(model: params[:model])
        end

        # Filter by status
        if params[:status].present?
          @responses = @responses.where(status: params[:status])
        end

        # Filter by environment
        if params[:environment].present?
          @responses = @responses.where(environment: params[:environment])
        end

        # Filter by user_id
        if params[:user_id].present?
          @responses = @responses.where(user_id: params[:user_id])
        end

        # Filter by session_id
        if params[:session_id].present?
          @responses = @responses.where(session_id: params[:session_id])
        end

        # Filter by evaluator type (responses that have evaluations of this type)
        if params[:evaluator_type].present?
          @responses = @responses.joins(:evaluations)
                                 .where(prompt_tracker_evaluations: { evaluator_type: params[:evaluator_type] })
                                 .distinct
        end

        # Search in rendered_prompt or response_text
        if params[:q].present?
          query = "%#{params[:q]}%"
          @responses = @responses.where("rendered_prompt LIKE ? OR response_text LIKE ?", query, query)
        end

        # Date range filter
        if params[:start_date].present?
          @responses = @responses.where("created_at >= ?", params[:start_date])
        end
        if params[:end_date].present?
          @responses = @responses.where("created_at <= ?", params[:end_date])
        end

        # Pagination
        @responses = @responses.page(params[:page]).per(50)

        # Get filter options
        @prompts = Prompt.active.order(:name)
        @providers = LlmResponse.tracked_calls.distinct.pluck(:provider).compact.sort
        @models = LlmResponse.tracked_calls.distinct.pluck(:model).compact.sort
        @statuses = LlmResponse::STATUSES
        @environments = LlmResponse.tracked_calls.distinct.pluck(:environment).compact.sort
        @user_ids = LlmResponse.tracked_calls.distinct.pluck(:user_id).compact.sort
        @session_ids = LlmResponse.tracked_calls.distinct.pluck(:session_id).compact.sort
        @evaluator_types = EvaluatorRegistry.all.values.map { |meta| meta[:evaluator_class].name }.uniq.sort

        # Calculate summary stats
        @total_responses = @responses.total_count
        @successful_count = LlmResponse.tracked_calls.where(status: "success").count
        @failed_count = LlmResponse.tracked_calls.where(status: %w[error timeout]).count
      end
    end
  end
end
