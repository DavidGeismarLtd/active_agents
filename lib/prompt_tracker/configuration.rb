# frozen_string_literal: true

module PromptTracker
  # Configuration for PromptTracker.
  #
  # @example Configure in an initializer
  #   PromptTracker.configure do |config|
  #     config.prompts_path = Rails.root.join("app", "prompts")
  #     config.basic_auth_username = "admin"
  #     config.basic_auth_password = "secret"
  #     config.providers = {
  #       openai: {
  #         api_key: ENV["OPENAI_API_KEY"],
  #         name: "OpenAI",
  #         apis: {
  #           chat_completions: { name: "Chat Completions", default: true },
  #           responses: { name: "Responses" }
  #         },
  #         models: [
  #           { id: "gpt-4o", name: "GPT-4o", capabilities: [:structured_output] }
  #         ]
  #       }
  #     }
  #     config.contexts = {
  #       playground: { default_provider: :openai, default_api: :chat_completions, default_model: "gpt-4o" }
  #     }
  #   end
  #
  class Configuration
    # Path to the directory containing prompt YAML files.
    # @return [String] the prompts directory path
    attr_accessor :prompts_path

    # Basic authentication username for web UI access.
    # @return [String, nil] the username
    attr_accessor :basic_auth_username

    # Basic authentication password for web UI access.
    # @return [String, nil] the password
    attr_accessor :basic_auth_password

    # Provider definitions including api_key, name, APIs, and models.
    # @return [Hash] hash of provider symbol => provider config hash
    # @example
    #   {
    #     openai: {
    #       api_key: ENV["OPENAI_API_KEY"],
    #       name: "OpenAI",
    #       apis: {
    #         chat_completions: { name: "Chat Completions", default: true },
    #         responses: { name: "Responses" }
    #       },
    #       models: [
    #         { id: "gpt-4o", name: "GPT-4o", capabilities: [:structured_output] }
    #       ]
    #     }
    #   }
    attr_accessor :providers

    # Context-specific default selections.
    # @return [Hash] hash of context symbol => defaults hash
    # @example
    #   {
    #     playground: { default_provider: :openai, default_api: :chat_completions, default_model: "gpt-4o" },
    #     llm_judge: { default_provider: :openai, default_api: :chat_completions, default_model: "gpt-4o" }
    #   }
    attr_accessor :contexts

    # Feature flags.
    # @return [Hash] hash of feature symbol => boolean
    # @example
    #   { openai_assistant_sync: true }
    attr_accessor :features

    # Built-in tools metadata (for Response API and Assistants API).
    # Maps tool capability symbols to display information.
    # @return [Hash] hash of tool symbol => tool metadata hash
    # @example
    #   {
    #     web_search: {
    #       name: "Web Search",
    #       description: "Search the web for current information",
    #       icon: "bi-globe"
    #     }
    #   }
    attr_accessor :builtin_tools

    # Initialize with default values.
    def initialize
      @prompts_path = default_prompts_path
      @basic_auth_username = nil
      @basic_auth_password = nil
      @providers = {}
      @contexts = {}
      @features = {}
      @builtin_tools = default_builtin_tools
    end

    # Check if basic authentication is enabled.
    # @return [Boolean] true if both username and password are set
    def basic_auth_enabled?
      basic_auth_username.present? && basic_auth_password.present?
    end

    # =========================================================================
    # Provider Methods
    # =========================================================================

    # Check if a provider has a valid API key configured.
    # @param provider [Symbol] the provider name
    # @return [Boolean] true if the provider has an API key
    def provider_configured?(provider)
      key = providers.dig(provider.to_sym, :api_key)
      key.present?
    end

    # Get the API key for a specific provider.
    # @param provider [Symbol] the provider name
    # @return [String, nil] the API key or nil if not configured
    def api_key_for(provider)
      providers.dig(provider.to_sym, :api_key)
    end

    # Get all providers that have API keys configured.
    # @return [Array<Symbol>] list of configured provider symbols
    def enabled_providers
      providers.select { |_, config| config[:api_key].present? }.keys
    end

    # Get the display name for a provider.
    # @param provider [Symbol] the provider key
    # @return [String] the provider display name
    def provider_name(provider)
      providers.dig(provider.to_sym, :name) || provider.to_s.titleize
    end

    # Get available APIs for a provider.
    # @param provider [Symbol] the provider key
    # @return [Array<Hash>] array of API hashes with :key, :name, :default, :capabilities, :description
    def apis_for(provider)
      provider_config = providers[provider.to_sym]
      return [] unless provider_config && provider_config[:apis]

      provider_config[:apis].map do |api_key, api_config|
        {
          key: api_key,
          name: api_config[:name] || api_key.to_s.titleize,
          default: api_config[:default] || false,
          capabilities: ApiCapabilities.features_for(provider, api_key),
          description: api_config[:description]
        }
      end
    end

    # Get the default API for a provider.
    # @param provider [Symbol] the provider key
    # @return [Symbol, nil] the default API key or first available API
    def default_api_for_provider(provider)
      apis = apis_for(provider)
      default_api = apis.find { |a| a[:default] }
      (default_api || apis.first)&.dig(:key)
    end

    # Check if a provider has multiple APIs.
    # @param provider [Symbol] the provider key
    # @return [Boolean] true if provider has more than one API
    def provider_has_multiple_apis?(provider)
      apis_for(provider).size > 1
    end

    # Get all models for a provider.
    # @param provider [Symbol] the provider key
    # @return [Array<Hash>] array of model hashes
    def models_for_provider(provider)
      providers.dig(provider.to_sym, :models) || []
    end

    # Get models for a specific provider and API combination.
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [Array<Hash>] array of model hashes compatible with the API
    def models_for_api(provider, api)
      provider_models = models_for_provider(provider)

      provider_models.select do |model|
        supported_apis = model[:supported_apis]
        # If no supported_apis specified, assume model works with all APIs
        supported_apis.nil? || supported_apis.include?(api.to_sym)
      end
    end

    # =========================================================================
    # Context Methods
    # =========================================================================

    # Get a context default value.
    # @param context [Symbol] the context name
    # @param attribute [Symbol] the attribute (:provider, :api, :model)
    # @return [Object, nil] the default value or nil
    def context_default(context, attribute)
      contexts.dig(context.to_sym, :"default_#{attribute}")
    end

    # Get the default provider for a context.
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default provider or nil
    def default_provider_for(context)
      context_default(context, :provider)
    end

    # Get the default API for a context.
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default API or nil
    def default_api_for(context)
      context_default(context, :api)
    end

    # Get the default model for a context.
    # @param context [Symbol] the context name
    # @return [String, nil] the default model ID or nil
    def default_model_for(context)
      context_default(context, :model)
    end

    # =========================================================================
    # Feature Flag Methods
    # =========================================================================

    # Check if a feature is enabled.
    # @param feature [Symbol] the feature name
    # @return [Boolean] true if the feature is enabled
    def feature_enabled?(feature)
      features[feature.to_sym] == true
    end

    # =========================================================================
    # Provider/API Utility Methods
    # =========================================================================

    # Build a combined provider+api identifier for storage.
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [String] combined identifier like "openai:chat_completions"
    def build_provider_api_key(provider, api)
      "#{provider}:#{api}"
    end

    # Parse a combined provider+api identifier.
    # @param combined_key [String] combined identifier like "openai:chat_completions"
    # @return [Hash] hash with :provider and :api keys
    def parse_provider_api_key(combined_key)
      parts = combined_key.to_s.split(":", 2)
      {
        provider: parts[0]&.to_sym,
        api: parts[1]&.to_sym
      }
    end

    # Get all provider/API combinations for the UI.
    # @return [Array<Hash>] array of hashes with provider and API info
    def all_provider_api_options
      enabled_providers.flat_map do |provider|
        apis = apis_for(provider)
        apis.map do |api|
          {
            provider: provider,
            provider_name: provider_name(provider),
            api: api[:key],
            api_name: api[:name],
            label: "#{provider_name(provider)} - #{api[:name]}",
            value: build_provider_api_key(provider, api[:key])
          }
        end
      end
    end

    # Get available tools for a specific provider and API combination.
    # Returns tool metadata for a provider/API combination.
    # Delegates to ApiCapabilities for capability detection, then enriches with metadata.
    #
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [Array<Hash>] array of tool hashes with :id, :name, :description, :icon, :configurable
    def tools_for_api(provider, api)
      # Get tools from ApiCapabilities (single source of truth)
      tool_symbols = ApiCapabilities.tools_for(provider, api)

      # Enrich with metadata from builtin_tools
      tool_symbols.map do |tool_symbol|
        tool_metadata = builtin_tools[tool_symbol]
        next unless tool_metadata

        {
          id: tool_symbol.to_s,
          name: tool_metadata[:name],
          description: tool_metadata[:description],
          icon: tool_metadata[:icon],
          configurable: tool_metadata[:configurable] == true
        }
      end.compact
    end

    private

    # Get the default prompts path.
    # @return [String] default path
    def default_prompts_path
      if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
        Rails.root.join("app", "prompts").to_s
      else
        File.join(Dir.pwd, "app", "prompts")
      end
    end

    # Get the default built-in tools with metadata.
    # @return [Hash] hash of tool symbol => tool metadata
    def default_builtin_tools
      {
        web_search: {
          name: "Web Search",
          description: "Search the web for current information",
          icon: "bi-globe"
        },
        file_search: {
          name: "File Search",
          description: "Search through uploaded files",
          icon: "bi-file-earmark-search",
          configurable: true
        },
        code_interpreter: {
          name: "Code Interpreter",
          description: "Execute Python code for analysis",
          icon: "bi-code-slash"
        },
        functions: {
          name: "Functions",
          description: "Define custom function schemas",
          icon: "bi-braces-asterisk",
          configurable: true
        }
      }
    end
  end

  # Get the current configuration.
  #
  # @return [Configuration] the configuration instance
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Configure PromptTracker.
  #
  # @yield [Configuration] the configuration instance
  # @example
  #   PromptTracker.configure do |config|
  #     config.prompts_path = "/custom/path"
  #   end
  def self.configure
    yield(configuration)
  end

  # Reset configuration to defaults.
  # Mainly used for testing.
  def self.reset_configuration!
    @configuration = Configuration.new
  end
end
