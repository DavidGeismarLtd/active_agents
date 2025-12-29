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

    # Master model registry. All available models in the system.
    # @return [Hash] hash of provider symbol => array of model hashes
    attr_accessor :models

    # OpenAI Assistants configuration (separate from chat completions).
    # @return [Hash] hash with :api_key and :available_models keys
    attr_accessor :openai_assistants

    # Context-specific model restrictions.
    # @return [Hash] hash of context symbol => restrictions hash
    attr_accessor :contexts

    # Default model selections for each context.
    # @return [Hash] hash of setting name => value
    attr_accessor :defaults

    # Initialize with default values.
    def initialize
      @prompts_path = default_prompts_path
      @basic_auth_username = nil
      @basic_auth_password = nil
      @api_keys = {}
      @models = {}
      @openai_assistants = { api_key: nil, available_models: [] }
      @contexts = {}
      @defaults = {}
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

    # Check if OpenAI Assistants API is configured.
    # @return [Boolean] true if configured with an API key
    def openai_assistants_configured?
      openai_assistants[:api_key].present?
    end

    # Get available models for OpenAI Assistants.
    # @return [Array<Hash>] list of model hashes
    def openai_assistants_models
      openai_assistants[:available_models] || []
    end

    # Get the API key for OpenAI Assistants.
    # @return [String, nil] the API key
    def openai_assistants_api_key
      openai_assistants[:api_key]
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

    # @deprecated Use {#defaults[:dataset_generator_model]} instead
    def dataset_generator_model
      defaults[:dataset_generator_model]
    end

    # @deprecated Use {#defaults=} instead
    def dataset_generator_model=(value)
      defaults[:dataset_generator_model] = value
    end

    # @deprecated Use {#defaults[:llm_judge_model]} instead
    def llm_judge_model
      defaults[:llm_judge_model]
    end

    # @deprecated Use {#defaults=} instead
    def llm_judge_model=(value)
      defaults[:llm_judge_model] = value
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
