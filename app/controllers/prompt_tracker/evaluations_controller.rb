# frozen_string_literal: true

module PromptTracker
  # Controller for viewing evaluations
  class EvaluationsController < ApplicationController
    # GET /evaluations
    # List all evaluations with filtering
    def index
      @evaluations = Evaluation.includes(llm_response: { prompt_version: :prompt })

      # Filter by evaluator_type
      @evaluations = @evaluations.where(evaluator_type: params[:evaluator_type]) if params[:evaluator_type].present?

      # Filter by score range (0-100)
      if params[:min_score].present?
        @evaluations = @evaluations.where("score >= ?", params[:min_score].to_f)
      end
      if params[:max_score].present?
        @evaluations = @evaluations.where("score <= ?", params[:max_score].to_f)
      end

      # Sorting
      case params[:sort]
      when "oldest"
        @evaluations = @evaluations.order(created_at: :asc)
      when "highest_score"
        @evaluations = @evaluations.order(Arel.sql("(score - score_min) / NULLIF((score_max - score_min), 0) DESC"))
      when "lowest_score"
        @evaluations = @evaluations.order(Arel.sql("(score - score_min) / NULLIF((score_max - score_min), 0) ASC"))
      else # "newest" or default
        @evaluations = @evaluations.order(created_at: :desc)
      end

      # Calculate summary stats before pagination
      all_evaluations = @evaluations.to_a
      if all_evaluations.any?
        normalized_scores = all_evaluations.map do |eval|
          PromptTracker::EvaluationHelpers.normalize_score(eval.score, min: eval.score_min, max: eval.score_max) * 100
        end
        @avg_score = normalized_scores.sum / normalized_scores.length.to_f
        @high_quality_count = normalized_scores.count { |score| score >= 80 }
        @low_quality_count = normalized_scores.count { |score| score < 50 }
      else
        @avg_score = 0
        @high_quality_count = 0
        @low_quality_count = 0
      end

      # Pagination
      @evaluations = @evaluations.page(params[:page]).per(20)

      # Get filter options
      @evaluator_types = Evaluation.distinct.pluck(:evaluator_type).compact.sort
    end

    # GET /evaluations/:id
    # Show evaluation details
    def show
      @evaluation = Evaluation.includes(:human_evaluations, llm_response: { prompt_version: :prompt }).find(params[:id])
      @response = @evaluation.llm_response
      @version = @response.prompt_version
      @prompt = @version.prompt
    end
  end
end
