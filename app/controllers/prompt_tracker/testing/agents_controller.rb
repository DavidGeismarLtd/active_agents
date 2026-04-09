# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for browsing and viewing agents in the Testing section
    class AgentsController < ApplicationController
    # GET /agents
    # List all agents with search and filtering
    def index
      @agents = Agent.includes(:agent_versions).order(created_at: :desc)

      # Search by name or description
      if params[:q].present?
        query = "%#{params[:q]}%"
        @agents = @agents.where("name LIKE ? OR description LIKE ?", query, query)
      end

      # Filter by status
      case params[:status]
      when "active"
        @agents = @agents.active
      when "archived"
        @agents = @agents.archived
      end

      # Sort
      case params[:sort]
      when "name"
        @agents = @agents.order(name: :asc)
      when "calls"
        @agents = @agents.left_joins(agent_versions: :llm_responses)
                          .group("prompt_tracker_agents.id")
                          .order("COUNT(prompt_tracker_llm_responses.id) DESC")
      when "cost"
        @agents = @agents.left_joins(agent_versions: :llm_responses)
                          .group("prompt_tracker_agents.id")
                          .order("SUM(prompt_tracker_llm_responses.cost_usd) DESC")
      end

      # Pagination
      @agents = pt_paginate(@agents, per_page: 20)

      # Get all categories and tags for filters
      @categories = Agent.distinct.pluck(:category).compact.sort
      @tags = Agent.pluck(:tags).flatten.compact.uniq.sort
    end

    # GET /agents/:id
    # Show agent details with all versions
    def show
      @agent = Agent.includes(agent_versions: [ :llm_responses, :evaluator_configs ]).find(params[:id])
      @versions = @agent.agent_versions.order(version_number: :desc)
      @active_version = @agent.active_version
      @latest_version = @agent.latest_version
    end
    end
  end
end
