# frozen_string_literal: true

module PromptTracker
  # Helper methods for the Playground views.
  # Provides provider detection and tool availability methods.
  module PlaygroundHelper
    # Returns a human-readable label for the version state.
    #
    # @param version [PromptVersion] the prompt version
    # @return [String] "Production", "Testing", or "Development"
    def version_state_label(version)
      return "Development" if version.nil?

      if version.production_state?
        "Production"
      elsif version.testing_state?
        "Testing"
      else
        "Development"
      end
    end

    # Returns Bootstrap badge CSS class for the version state.
    #
    # @param version [PromptVersion] the prompt version
    # @return [String] Bootstrap badge class
    def version_state_badge_class(version)
      return "bg-success" if version.nil?

      if version.production_state?
        "bg-danger"
      elsif version.testing_state?
        "bg-warning text-dark"
      else
        "bg-success"
      end
    end

    # Returns a description of what changes are allowed in the current state.
    #
    # @param version [PromptVersion] the prompt version
    # @return [String] description of allowed changes
    def version_state_description(version)
      return "All changes are allowed." if version.nil?

      if version.production_state?
        "This version has production responses. Any changes will create a new version."
      elsif version.testing_state?
        "This version has tests or datasets. Structural changes (provider, API, model, tools, variables, response schema) will create a new version."
      else
        "All changes are allowed."
      end
    end

    # Check if the playground UI should show prompt editing capabilities.
    # Returns true if either system_prompt or user_prompt_template is supported.
    #
    # @param playground_ui [Array<Symbol>] the playground UI capabilities array
    # @return [Boolean] true if prompt editing should be shown
    def show_prompt_editing?(playground_ui)
      playground_ui.include?(:system_prompt) || playground_ui.include?(:user_prompt_template)
    end

    # Check if the playground UI should show variables and preview section.
    # Returns true if either variables or preview is supported.
    #
    # @param playground_ui [Array<Symbol>] the playground UI capabilities array
    # @return [Boolean] true if variables/preview section should be shown
    def show_variables_preview?(playground_ui)
      playground_ui.include?(:variables) || playground_ui.include?(:preview)
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

    # Convert enabled_tools array to hash for easy lookup in views
    #
    # @param enabled_tools [Array<String>] array of enabled tool IDs
    # @return [Hash] hash with tool IDs as keys and true as values
    #
    # @example
    #   enabled_tools_hash_for(["file_search", "web_search"])
    #   # => {"file_search" => true, "web_search" => true}
    def enabled_tools_hash_for(enabled_tools)
      (enabled_tools || []).index_with { true }
    end

    # Check if a tool is enabled
    #
    # @param tool [Hash] the tool hash with :id key
    # @param enabled_tools_hash [Hash] hash of enabled tool IDs
    # @return [Boolean] true if tool is enabled
    def tool_enabled?(tool, enabled_tools_hash)
      enabled_tools_hash[tool[:id].to_s].present?
    end

    # Get CSS class for tool card based on enabled state
    #
    # @param tool [Hash] the tool hash with :id key
    # @param enabled_tools_hash [Hash] hash of enabled tool IDs
    # @return [String] 'active' if enabled, empty string otherwise
    def tool_card_class(tool, enabled_tools_hash)
      tool_enabled?(tool, enabled_tools_hash) ? "active" : ""
    end

    # Check if a tool is configurable
    #
    # @param tool [Hash] the tool hash with :configurable key
    # @return [Boolean] true if tool is configurable
    def tool_configurable?(tool)
      tool[:configurable] == true
    end

    # Extract vector stores from file search config
    # Handles both new format (array of {id, name} hashes) and legacy format (array of IDs)
    #
    # @param file_search_config [Hash] the file search configuration
    # @return [Array<Hash>] array of vector store hashes with :id and :name keys
    def extract_vector_stores(file_search_config)
      vector_stores = file_search_config["vector_stores"] || []
      vector_store_ids = file_search_config["vector_store_ids"] || []

      if vector_stores.present?
        # New format: array of {id, name} hashes
        vector_stores.map do |vs|
          {
            id: vs["id"],
            name: vs["name"] || vs["id"]
          }
        end
      else
        # Legacy format: array of IDs only
        vector_store_ids.map do |vs_id|
          {
            id: vs_id,
            name: vs_id
          }
        end
      end
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

    # Build complete model config data for playground form
    # Extracts all the data preparation logic from the view
    #
    # @param version [PromptVersion] the prompt version (can be nil)
    # @return [Hash] complete config data with all necessary information
    def playground_model_config_data(version)
      available_providers_list = enabled_providers
      default_provider_value = default_provider_for(:playground)
      default_api_value = default_api_for(:playground)

      # DEBUG LOGGING - Check both symbol and string keys
      Rails.logger.debug "========== PLAYGROUND_MODEL_CONFIG_DATA =========="
      Rails.logger.debug "Version ID: #{version&.id}"
      Rails.logger.debug "Version model_config (raw): #{version&.model_config.inspect}"
      Rails.logger.debug "Version model_config[:provider]: #{version&.model_config&.dig(:provider)}"
      Rails.logger.debug "Version model_config['provider']: #{version&.model_config&.dig('provider')}"
      Rails.logger.debug "Version model_config[:api]: #{version&.model_config&.dig(:api)}"
      Rails.logger.debug "Version model_config['api']: #{version&.model_config&.dig('api')}"
      Rails.logger.debug "Default provider: #{default_provider_value}"
      Rails.logger.debug "Default API: #{default_api_value}"

      current_provider = version&.model_config&.dig(:provider) ||
                        version&.model_config&.dig("provider") ||
                        default_provider_value&.to_s ||
                        available_providers_list.first.to_s

      current_api = version&.model_config&.dig(:api) ||
                   version&.model_config&.dig("api") ||
                   default_api_value&.to_s ||
                   default_api_for_provider(current_provider.to_sym)&.to_s

      Rails.logger.debug "Resolved current_provider: #{current_provider}"
      Rails.logger.debug "Resolved current_api: #{current_api}"

      # Build provider data JSON
      provider_data = build_provider_data_json(available_providers_list)

      # Get current models for initial render
      models = models_for_api(current_provider.to_sym, current_api.to_sym)
      current_model = version&.model_config&.dig(:model) ||
                     version&.model_config&.dig("model") ||
                     default_model_for(:playground) ||
                     models.first&.dig(:id)

      # Get current API config
      current_api_config = apis_for(current_provider.to_sym).find { |a| a[:key].to_s == current_api.to_s }

      # Check if current API supports tools
      current_available_tools = PromptTracker.configuration.tools_for_api(
        current_provider.to_sym,
        current_api.to_sym
      )
      supports_tools = current_available_tools.any?

      Rails.logger.debug "Current API config: #{current_api_config.inspect}"
      Rails.logger.debug "Supports tools: #{supports_tools}"
      Rails.logger.debug "=================================================="

      {
        available_providers: available_providers_list,
        current_provider: current_provider,
        current_api: current_api,
        current_model: current_model,
        provider_data: provider_data,
        models: models,
        current_api_config: current_api_config,
        current_available_tools: current_available_tools,
        supports_tools: supports_tools
      }
    end

    # Build provider data JSON structure for JavaScript cascading selects
    # Structure: { provider: { apis: [...], models_by_api: { api: [...models] }, tools_by_api: { api: [...tools] } } }
    #
    # @param available_providers [Array<Symbol>] list of available provider keys
    # @return [Hash] provider data structure
    def build_provider_data_json(available_providers)
      provider_data = {}

      available_providers.each do |provider_key|
        apis = apis_for(provider_key)
        models_by_api = {}
        tools_by_api = {}

        apis.each do |api|
          # Build models for this API
          api_models = models_for_api(provider_key, api[:key])
          models_by_api[api[:key].to_s] = api_models.map do |model|
            {
              id: model[:id],
              name: model[:name] || model[:id],
              category: model[:category]
            }
          end

          # Get tools for this provider/API from configuration
          tools_by_api[api[:key].to_s] = PromptTracker.configuration.tools_for_api(provider_key, api[:key])
        end

        provider_data[provider_key.to_s] = {
          name: provider_name(provider_key),
          apis: apis.map { |a|
            {
              key: a[:key].to_s,
              name: a[:name],
              default: a[:default],
              description: a[:description],
              capabilities: a[:capabilities]
            }
          },
          models_by_api: models_by_api,
          tools_by_api: tools_by_api
        }
      end

      provider_data
    end
  end
end
