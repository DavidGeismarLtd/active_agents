# frozen_string_literal: true

module Agents
  # Public API controller for deployed agents.
  # Handles external requests to chat with deployed agents.
  #
  # This controller is OUTSIDE the PromptTracker engine namespace to provide
  # clean public URLs: /agents/:slug/chat instead of /prompt_tracker/agents/:slug/chat
  #
  # Authentication: Bearer token (API key)
  # Rate limiting: Per-agent configurable limits
  # CORS: Per-agent configurable origins
  #
  # @example Chat with an agent
  #   POST /agents/customer-support-bot/chat
  #   Headers: Authorization: Bearer sk_abc123...
  #   Body: { message: "Hello!", conversation_id: "conv_123" }
  #
  class DeployedAgentsController < ActionController::Base
    include ActionController::HttpAuthentication::Token::ControllerMethods

    # Skip CSRF for API requests (POST with JSON)
    skip_before_action :verify_authenticity_token, if: :json_request?

    before_action :load_agent
    before_action :check_agent_status
    before_action :authenticate_request, unless: :web_ui_request?
    before_action :check_rate_limit, unless: :web_ui_request?
    before_action :set_cors_headers

    # GET /agents/:slug/chat - Browser chat interface
    # POST /agents/:slug/chat - API endpoint
    # Body: { message: "...", conversation_id: "..." (optional), metadata: {...} }
    # Response: { response: "...", conversation_id: "...", function_calls: [...] }
    def chat
      # If GET request, render chat UI (if enabled)
      if request.get?
        return render_chat_ui
      end

      # POST request - process chat message
      result = PromptTracker::AgentRuntimeService.call(
        deployed_agent: @agent,
        message: params[:message],
        conversation_id: params[:conversation_id],
        metadata: params[:metadata]&.to_unsafe_h || {}
      )

      if result.success?
        render json: {
          response: result.response,
          conversation_id: result.conversation_id,
          function_calls: result.function_calls
        }
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error("Agent chat error: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Internal server error" }, status: :internal_server_error
    end

    # GET /agents/:slug/info
    # Returns public information about the agent
    def info
      render json: {
        name: @agent.name,
        slug: @agent.slug,
        status: @agent.status,
        model: @agent.prompt_version.model_config[:model],
        functions: @agent.function_definitions.pluck(:name, :description).map do |name, desc|
          { name: name, description: desc }
        end
      }
    end

    private

    def load_agent
      @agent = PromptTracker::DeployedAgent.find_by!(slug: params[:slug])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agent not found" }, status: :not_found
    end

    def check_agent_status
      return if @agent.accepting_requests?

      case @agent.status
      when "paused"
        render json: { error: "Agent is paused" }, status: :service_unavailable
      when "error"
        render json: { error: "Agent is experiencing errors" }, status: :service_unavailable
      else
        render json: { error: "Agent is not available" }, status: :service_unavailable
      end
    end

    def authenticate_request
      auth_type = @agent.config.dig(:auth, :type)

      # If auth type is "none", skip authentication
      return if auth_type == "none"

      # Otherwise, require API key
      authenticate_or_request_with_http_token do |token, _options|
        @agent.verify_api_key(token)
      end
    end

    def check_rate_limit
      rate_limit_config = @agent.config.dig(:rate_limit, :requests_per_minute)
      return unless rate_limit_config.present?

      # Use Redis-based rate limiting
      limiter = PromptTracker::RateLimiter.new(
        key: "agent:#{@agent.id}",
        limit: rate_limit_config,
        period: 60 # seconds
      )

      unless limiter.allow?
        response.headers["Retry-After"] = limiter.retry_after.to_s
        render json: { error: "Rate limit exceeded" }, status: :too_many_requests
      end
    end

    def set_cors_headers
      allowed_origins = @agent.config.dig(:cors, :allowed_origins) || []

      # If allowed_origins is empty or contains "*", allow all origins
      if allowed_origins.empty? || allowed_origins.include?("*")
        response.headers["Access-Control-Allow-Origin"] = request.headers["Origin"] || "*"
      elsif allowed_origins.include?(request.headers["Origin"])
        response.headers["Access-Control-Allow-Origin"] = request.headers["Origin"]
      end

      response.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
      response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      response.headers["Access-Control-Max-Age"] = "86400" # 24 hours
    end

    # Handle preflight requests
    def options
      head :ok
    end

    def render_chat_ui
      # Check if web UI is enabled
      unless @agent.config[:enable_web_ui]
        render json: { error: "Web UI is not enabled for this agent" }, status: :forbidden
        return
      end

      # Render the chat interface
      render "agents/deployed_agents/chat", layout: "agents/chat"
    end

    def web_ui_request?
      request.get? && action_name == "chat"
    end

    def json_request?
      request.format.json? || request.content_type == "application/json"
    end
  end
end
