# frozen_string_literal: true

module PromptTracker
  # Configuration for PromptTracker.
  #
  # @example Configure in an initializer
  #   PromptTracker.configure do |config|
  #     config.prompts_path = Rails.root.join("app", "prompts")
  #     config.basic_auth_username = "admin"
  #     config.basic_auth_password = "secret"
  #     config.api_keys = { openai: ENV["OPENAI_API_KEY"] }
  #     config.providers = {
  #       openai: {
  #         name: "OpenAI",
  #         apis: {
  #           chat_completion: { name: "Chat Completions", default: true },
  #           response_api: { name: "Responses API" }
  #         }
  #       }
  #     }
  #     config.models = { openai: [{ id: "gpt-4o", name: "GPT-4o" }] }
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

    # API keys for each provider. A provider is only available if its key is present.
    # @return [Hash] hash of provider symbol => API key string
    attr_accessor :api_keys

    # Provider definitions with their available APIs.
    # @return [Hash] hash of provider symbol => provider config hash
    # @example
    #   {
    #     openai: {
    #       name: "OpenAI",
    #       apis: {
    #         chat_completion: { name: "Chat Completions", default: true },
    #         response_api: { name: "Responses API", capabilities: [:web_search] }
    #       }
    #     }
    #   }
    attr_accessor :providers

    # Master model registry. All available models in the system.
    # @return [Hash] hash of provider symbol => array of model hashes
    attr_accessor :models



    # Context-specific model restrictions.
    # @return [Hash] hash of context symbol => restrictions hash
    attr_accessor :contexts

    # Default model selections for each context.
    # @return [Hash] hash of setting name => value
    attr_accessor :defaults

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
      @api_keys = {}
      @providers = {}
      @models = {}
      @contexts = {}
      @defaults = {}
      @builtin_tools = default_builtin_tools
    end

    # Check if basic authentication is enabled.
    # @return [Boolean] true if both username and password are set
    def basic_auth_enabled?
      basic_auth_username.present? && basic_auth_password.present?
    end

    # Check if a provider has a valid API key configured.
    # @param provider [Symbol] the provider name
    # @return [Boolean] true if the provider has an API key
    def provider_configured?(provider)
      key = api_keys[provider.to_sym]
      key.present?
    end

    # Get the API key for a specific provider.
    # @param provider [Symbol] the provider name
    # @return [String, nil] the API key or nil if not configured
    def api_key_for(provider)
      api_keys[provider.to_sym]
    end

    # Get all providers that have API keys configured.
    # @return [Array<Symbol>] list of configured provider symbols
    def configured_providers
      api_keys.select { |_, key| key.present? }.keys
    end

    # Get available providers for a specific context.
    # Filters by both context restrictions AND API key presence.
    # @param context [Symbol] the context name (e.g., :playground, :llm_judge)
    # @return [Array<Symbol>] list of available provider symbols
    def providers_for(context)
      context_config = contexts[context] || {}
      allowed_providers = context_config[:providers]

      if allowed_providers.nil?
        configured_providers
      else
        allowed_providers.select { |p| provider_configured?(p) }
      end
    end

    # Get available models for a context.
    # @param context [Symbol] the context name
    # @param provider [Symbol, nil] optional provider filter
    # @return [Hash, Array] hash of provider => models, or array if provider specified
    def models_for(context, provider: nil)
      context_config = contexts[context] || {}
      available_providers = providers_for(context)
      required_capability = context_config[:require_capability]
      allowed_model_ids = context_config[:models]

      if provider
        filter_models_for_provider(provider, available_providers, required_capability, allowed_model_ids)
      else
        available_providers.each_with_object({}) do |p, result|
          filtered = filter_models_for_provider(p, available_providers, required_capability, allowed_model_ids)
          result[p] = filtered if filtered.any?
        end
      end
    end

    # Get the default model for a context.
    # @param context [Symbol] the context name
    # @return [String, nil] the default model ID or nil
    def default_model_for(context)
      key = :"#{context}_model"
      defaults[key]
    end

    # Get the default provider for a context.
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default provider or nil
    def default_provider_for(context)
      key = :"#{context}_provider"
      defaults[key]
    end

    # Get the default API for a context.
    # @param context [Symbol] the context name
    # @return [Symbol, nil] the default API or nil
    def default_api_for(context)
      key = :"#{context}_api"
      defaults[key]
    end

    # =========================================================================
    # Provider/API Methods
    # =========================================================================

    # Get the display name for a provider.
    # @param provider [Symbol] the provider key
    # @return [String] the provider display name
    def provider_name(provider)
      providers.dig(provider.to_sym, :name) || provider.to_s.titleize
    end

    # Get available APIs for a provider.
    # @param provider [Symbol] the provider key
    # @return [Array<Hash>] array of API hashes with :key, :name, :default, :capabilities
    def apis_for(provider)
      provider_config = providers[provider.to_sym]
      return [] unless provider_config && provider_config[:apis]

      provider_config[:apis].map do |api_key, api_config|
        {
          key: api_key,
          name: api_config[:name] || api_key.to_s.titleize,
          default: api_config[:default] || false,
          capabilities: api_config[:capabilities] || [],
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

    # Get models for a specific provider and API combination.
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [Array<Hash>] array of model hashes compatible with the API
    def models_for_api(provider, api)
      provider_models = models[provider.to_sym] || []

      provider_models.select do |model|
        supported_apis = model[:supported_apis]
        # If no supported_apis specified, assume model works with all APIs
        supported_apis.nil? || supported_apis.include?(api.to_sym)
      end
    end

    # Build a combined provider+api identifier for storage.
    # @param provider [Symbol] the provider key
    # @param api [Symbol] the API key
    # @return [String] combined identifier like "openai:chat_completion"
    def build_provider_api_key(provider, api)
      "#{provider}:#{api}"
    end

    # Parse a combined provider+api identifier.
    # @param combined_key [String] combined identifier like "openai:chat_completion"
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
      configured_providers.flat_map do |provider|
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

    # =========================================================================
    # Backward Compatibility Methods (DEPRECATED)
    # =========================================================================

    # @deprecated Use {#models} instead
    def available_models
      models
    end

    # @deprecated Use {#models=} instead
    def available_models=(value)
      self.models = value
    end

    # @deprecated Use {#api_keys} instead
    def provider_api_key_env_vars
      # Return a mapping that mimics the old behavior for backward compatibility
      api_keys.transform_values { |_| "CONFIGURED" }
    end

    # @deprecated Use {#api_keys=} instead
    def provider_api_key_env_vars=(value)
      # Convert old format to new format by looking up ENV vars
      self.api_keys = value.transform_values { |env_var| ENV[env_var] }
    end

    # @deprecated Use {#defaults[:prompt_generator_model]} instead
    def prompt_generator_model
      defaults[:prompt_generator_model]
    end

    # @deprecated Use {#defaults=} instead
    def prompt_generator_model=(value)
      defaults[:prompt_generator_model] = value
    end

    # Get the dataset generator model (with fallback to gpt-4o)
    # @return [String] the model to use for dataset generation
    def dataset_generator_model
      defaults[:dataset_generator_model] || "gpt-4o"
    end

    # Set the dataset generator model
    # @param value [String] the model to use
    def dataset_generator_model=(value)
      defaults[:dataset_generator_model] = value
    end

    # Get the dataset generator provider (with fallback to openai)
    # @return [String] the provider to use for dataset generation
    def dataset_generator_provider
      defaults[:dataset_generator_provider] || "openai"
    end

    # Set the dataset generator provider
    # @param value [String] the provider to use
    def dataset_generator_provider=(value)
      defaults[:dataset_generator_provider] = value
    end

    # Get the dataset generator API (with fallback to chat_completions)
    # @return [String] the API to use for dataset generation
    def dataset_generator_api
      defaults[:dataset_generator_api] || "chat_completions"
    end

    # Set the dataset generator API
    # @param value [String] the API to use
    def dataset_generator_api=(value)
      defaults[:dataset_generator_api] = value
    end

    # @deprecated Use {#defaults[:llm_judge_model]} instead
    def llm_judge_model
      defaults[:llm_judge_model]
    end

    # @deprecated Use {#defaults=} instead
    def llm_judge_model=(value)
      defaults[:llm_judge_model] = value
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

    # Filter models for a specific provider based on context restrictions.
    def filter_models_for_provider(provider, available_providers, required_capability, allowed_model_ids)
      return [] unless available_providers.include?(provider.to_sym)

      provider_models = models[provider.to_sym] || []

      provider_models.select do |model|
        # Filter by allowed model IDs if specified
        next false if allowed_model_ids && !allowed_model_ids.include?(model[:id])

        # Filter by required capability if specified
        if required_capability
          capabilities = model[:capabilities] || []
          next false unless capabilities.include?(required_capability)
        end

        true
      end
    end

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
