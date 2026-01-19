# frozen_string_literal: true

module PromptTracker
  # Helper methods for the Playground views.
  # Provides provider detection and tool availability methods.
  module PlaygroundHelper
    # Check if the current API is a Response API
    #
    # @return [Boolean] true if using responses API
    def response_api_provider?
      current_api.to_s == "responses"
    end

    # Check if the current provider/API supports multi-turn conversations
    #
    # @return [Boolean] true if API supports conversations
    def supports_conversation?
      %w[responses assistants].include?(current_api.to_s)
    end

    # Get available tools for the current provider and API.
    # Reads from configuration based on API capabilities.
    #
    # @param provider [Symbol, String] the provider key (defaults to current)
    # @param api [Symbol, String] the API key (defaults to current)
    # @return [Array<Hash>] list of available tools with id, name, description, icon
    def available_tools_for_provider(provider: nil, api: nil)
      provider ||= current_provider
      api ||= current_api

      PromptTracker.configuration.tools_for_api(provider.to_sym, api.to_sym)
    end

    # Get the current provider from version config or default
    #
    # @return [String] the current provider name
    def current_provider
      @version&.model_config&.dig("provider") ||
        default_provider_for(:playground)&.to_s ||
        "openai"
    end

    # Get the current API from version config or default
    #
    # @return [String] the current API name
    def current_api
      @version&.model_config&.dig("api") ||
        default_api_for(:playground)&.to_s ||
        default_api_for_provider(current_provider.to_sym)&.to_s ||
        "chat_completions"
    end

    # Get the current model from version config or default
    #
    # @return [String] the current model name
    def current_model
      @version&.model_config&.dig("model") ||
        default_model_for(:playground) ||
        "gpt-4o"
    end

    # Check if the provider/API supports tools
    #
    # @param provider [String] the provider name
    # @param api [String] the API name
    # @return [Boolean] true if API supports tools
    def provider_supports_tools?(provider: nil, api: nil)
      provider ||= current_provider
      api ||= current_api

      available_tools_for_provider(provider: provider, api: api).any?
    end

    # Get enabled tools from version config
    #
    # @return [Array<String>] list of enabled tool IDs
    def enabled_tools
      @version&.model_config&.dig("tools") || []
    end

    # Build conversation state from session
    #
    # @param session [ActionDispatch::Request::Session] the session object
    # @return [Hash] conversation state with messages and metadata
    def conversation_state_from_session(session)
      session[:playground_conversation] || {
        messages: [],
        previous_response_id: nil,
        started_at: nil
      }
    end
  end
end
