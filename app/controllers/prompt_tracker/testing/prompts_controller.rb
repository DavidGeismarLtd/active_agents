# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for browsing and viewing prompts in the Testing section
    class PromptsController < ApplicationController
    # GET /prompts
    # List all prompts with search and filtering
    def index
      @prompts = Prompt.includes(:prompt_versions).order(created_at: :desc)

      # Search by name or description
      if params[:q].present?
        query = "%#{params[:q]}%"
        @prompts = @prompts.where("name LIKE ? OR description LIKE ?", query, query)
      end

      # Filter by status
      case params[:status]
      when "active"
        @prompts = @prompts.active
      when "archived"
        @prompts = @prompts.archived
      end

      # Sort
      case params[:sort]
      when "name"
        @prompts = @prompts.order(name: :asc)
      when "calls"
        @prompts = @prompts.left_joins(prompt_versions: :llm_responses)
                          .group("prompt_tracker_prompts.id")
                          .order("COUNT(prompt_tracker_llm_responses.id) DESC")
      when "cost"
        @prompts = @prompts.left_joins(prompt_versions: :llm_responses)
                          .group("prompt_tracker_prompts.id")
                          .order("SUM(prompt_tracker_llm_responses.cost_usd) DESC")
      end

      # Pagination
      @prompts = @prompts.page(params[:page]).per(20)

      # Get all categories and tags for filters
      @categories = Prompt.distinct.pluck(:category).compact.sort
      @tags = Prompt.pluck(:tags).flatten.compact.uniq.sort
    end

    # GET /prompts/:id
    # Show prompt details with all versions
    def show
      @prompt = Prompt.includes(prompt_versions: [ :llm_responses, :evaluator_configs ]).find(params[:id])
      @versions = @prompt.prompt_versions.order(version_number: :desc)
      @active_version = @prompt.active_version
      @latest_version = @prompt.latest_version
    end
    end
  end
end
