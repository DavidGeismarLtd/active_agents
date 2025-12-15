# frozen_string_literal: true

module PromptTracker
  module Monitoring
    # Dashboard for the Monitoring section - runtime tracking
    #
    # Shows overview of:
    # - Recent runtime LLM calls (across all environments)
    # - Auto-evaluation results
    # - Quality metrics
    # - Alerts for failing evaluations
    #
    class DashboardController < ApplicationController
      def index
        # Only show tracked calls (not test runs)
        @recent_responses = LlmResponse.tracked_calls
                                       .includes(:prompt_version, :prompt, :human_evaluations, evaluations: [])
                                       .order(created_at: :desc)

        # Apply filters
        if params[:prompt_id].present?
          @recent_responses = @recent_responses.joins(prompt_version: :prompt)
                                               .where(prompt_tracker_prompts: { id: params[:prompt_id] })
        end

        if params[:environment].present?
          @recent_responses = @recent_responses.where(environment: params[:environment])
        end

        if params[:status].present?
          @recent_responses = @recent_responses.where(status: params[:status])
        end

        if params[:evaluator_type].present?
          @recent_responses = @recent_responses.joins(:evaluations)
                                               .where(prompt_tracker_evaluations: { evaluator_type: params[:evaluator_type] })
                                               .distinct
        end

        # Limit results
        @recent_responses = @recent_responses.limit(50)

        # Get filter options
        @prompts = Prompt.active.order(:name)
        @environments = LlmResponse.tracked_calls.distinct.pluck(:environment).compact.sort
        @statuses = LlmResponse::STATUSES
        @evaluator_types = EvaluatorRegistry.all.values.map { |meta| meta[:evaluator_class].name }.uniq.sort

        # Statistics (last 24 hours)
        since_yesterday = Time.current - 24.hours
        @calls_today = LlmResponse.tracked_calls
                                  .where("created_at >= ?", since_yesterday)
                                  .count

        @evaluations_today = Evaluation.tracked
                                       .where("created_at >= ?", since_yesterday)
                                       .count

        # Quality metrics
        recent_evals = Evaluation.tracked
                                 .where("created_at >= ?", since_yesterday)

        @avg_score = if recent_evals.any?
          recent_evals.average(:score).to_f.round(2)
        else
          0
        end

        # Alerts: evaluations that did not pass
        @failing_evaluations = Evaluation.tracked
                                         .joins(:llm_response)
                                         .where("prompt_tracker_evaluations.created_at >= ?", since_yesterday)
                                         .where(passed: false)
                                         .order(created_at: :desc)
                                         .limit(10)
      end
    end
  end
end
