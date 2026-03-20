# frozen_string_literal: true

module PromptTracker
  # Controller for managing deployed agents
  class DeployedAgentsController < ApplicationController
    before_action :set_agent, only: [ :show, :edit, :update, :destroy, :pause, :resume, :regenerate_api_key ]

    # GET /agents
    # Dashboard showing all deployed agents
    def index
      @agents = DeployedAgent.includes(:prompt_version)
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(20)

      # Apply filters
      @agents = @agents.where(status: params[:status]) if params[:status].present?

      # Statistics
      @total_agents = DeployedAgent.count
      @active_agents = DeployedAgent.active.count
      @paused_agents = DeployedAgent.paused.count
      @error_agents = DeployedAgent.with_errors.count
    end

    # GET /agents/:slug
    # Show agent details with tabs
    def show
      @prompt = @agent.prompt_version.prompt
      @version = @agent.prompt_version

      # Get recent conversations
      @recent_conversations = @agent.agent_conversations
                                    .recent
                                    .limit(10)

      # Get recent LLM responses
      @recent_responses = @agent.llm_responses
                                .order(created_at: :desc)
                                .limit(20)

      # Statistics
      @total_conversations = @agent.agent_conversations.count
      @active_conversations = @agent.agent_conversations.active.count
      @total_requests = @agent.llm_responses.count
      @successful_requests = @agent.llm_responses.where(status: "success").count
      @failed_requests = @agent.llm_responses.where(status: "error").count
      @avg_response_time = @agent.llm_responses.average(:response_time_ms)&.round(0)
    end

    # GET /agents/new
    # Form to deploy a new agent from a prompt version
    def new
      @version = PromptVersion.find(params[:prompt_version_id])
      @prompt = @version.prompt
      @agent = DeployedAgent.new(
        prompt_version: @version,
        name: "#{@prompt.name} Agent",
        deployment_config: {}
      )
    end

    # POST /agents
    # Deploy a new agent
    def create
      @version = PromptVersion.find(params[:deployed_agent][:prompt_version_id])
      @prompt = @version.prompt
      @agent = DeployedAgent.new(agent_params)

      if @agent.save
        redirect_to deployed_agent_path(@agent.slug),
                    notice: "Agent deployed successfully! API Key: #{@agent.plain_api_key} (save this, it won't be shown again)"
      else
        flash.now[:alert] = "Failed to deploy agent: #{@agent.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
      end
    end

    # GET /agents/:slug/edit
    def edit
      @prompt = @agent.prompt_version.prompt
      @version = @agent.prompt_version
    end

    # PATCH /agents/:slug
    def update
      if @agent.update(agent_params)
        redirect_to deployed_agent_path(@agent.slug), notice: "Agent updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /agents/:slug
    def destroy
      @agent.destroy
      redirect_to deployed_agents_path, notice: "Agent deleted successfully."
    end

    # POST /agents/:slug/pause
    def pause
      @agent.pause!
      redirect_to deployed_agent_path(@agent.slug), notice: "Agent paused."
    end

    # POST /agents/:slug/resume
    def resume
      @agent.resume!
      redirect_to deployed_agent_path(@agent.slug), notice: "Agent resumed."
    end

    # POST /agents/:slug/regenerate_api_key
    def regenerate_api_key
      @agent.regenerate_api_key!
      redirect_to deployed_agent_path(@agent.slug), notice: "API key regenerated successfully!"
    end

    private

    def set_agent
      @agent = DeployedAgent.find_by!(slug: params[:slug])
    end

    def agent_params
      permitted = params.require(:deployed_agent).permit(
        :prompt_version_id,
        :name,
        deployment_config: [
          :conversation_ttl,
          :enable_web_ui,
          auth: [ :type ],
          rate_limit: [ :requests_per_minute ],
          cors: [ :allowed_origins ]
        ]
      )

      # Convert deployment_config to proper hash structure for JSONB
      if permitted[:deployment_config].present?
        config = permitted[:deployment_config].to_h

        # Parse CORS origins from comma-separated string to array
        cors_origins = config.dig(:cors, :allowed_origins)
        cors_origins_array = if cors_origins.present?
          cors_origins.split(",").map(&:strip).reject(&:blank?)
        else
          []
        end

        # Get auth type, defaulting to "api_key" only if not present
        auth_type = config.dig(:auth, :type)
        auth_type = "api_key" if auth_type.blank?

        permitted[:deployment_config] = {
          conversation_ttl: config[:conversation_ttl]&.to_i || 3600,
          enable_web_ui: config[:enable_web_ui] == "1" || config[:enable_web_ui] == true,
          auth: {
            type: auth_type
          },
          rate_limit: {
            requests_per_minute: config.dig(:rate_limit, :requests_per_minute)&.to_i
          },
          cors: {
            allowed_origins: cors_origins_array
          }
        }
      end

      permitted
    end
  end
end
