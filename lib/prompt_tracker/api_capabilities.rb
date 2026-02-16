# frozen_string_literal: true

module PromptTracker
  # ApiCapabilities defines what each provider/API combination supports.
  # This is the single source of truth for API capabilities in the engine.
  #
  # @example Get tools for OpenAI Chat Completions
  #   ApiCapabilities.tools_for(:openai, :chat_completions)
  #   # => [:functions]
  #
  # @example Check if API supports tools
  #   ApiCapabilities.supports_tools?(:openai, :responses)
  #   # => true
  #
  # @example Check if API uses prompt templates
  #   ApiCapabilities.supports_feature?(:openai, :chat_completions, :template_based)
  #   # => true
  #   ApiCapabilities.supports_feature?(:openai, :assistants, :template_based)
  #   # => false
  #
  # @example Check if API requires remote entity sync
  #   ApiCapabilities.supports_feature?(:openai, :assistants, :remote_entity_linked)
  #   # => true
  module ApiCapabilities
    # Capability matrix defining what each provider/API supports.
    # Structure: { provider: { api: { tools: [...], features: [...], playground_ui: [...] } } }
    #
    # **Features** - Behavioral capabilities (non-UI):
    # - :remote_entity_linked - API requires syncing with remote entities (e.g., OpenAI Assistants)
    # - Future: :streaming, :vision, :structured_output (when actually implemented)
    #
    # **Playground UI** - Defines which UI panels to show in playground:
    # - :system_prompt - System prompt editor
    # - :user_prompt_template - User prompt template editor with variables
    # - :variables - Variables panel
    # - :preview - Live preview panel
    # - :conversation - Conversation testing panel
    # - :tools - Tools configuration panel
    # - :model_config - Model configuration panel
    #
    # Note: Use `playground_ui` array to determine UI visibility, NOT features array.
    CAPABILITIES = {
      openai: {
        chat_completions: {
          tools: [ :functions ],
          features: [],
          playground_ui: [ :system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config ]
        },
        responses: {
          tools: [ :web_search, :file_search, :code_interpreter, :functions ],
          features: [],
          playground_ui: [ :system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config ]
        },
        assistants: {
          tools: [ :code_interpreter, :file_search, :functions ],
          features: [ :remote_entity_linked ],
          playground_ui: [ :system_prompt, :conversation, :tools, :model_config ]
        }
      },
      anthropic: {
        messages: {
          tools: [ :functions ],
          features: [],
          playground_ui: [ :system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config ]
        }
      }
    }.freeze

    # Get available tools for a specific provider and API combination.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai, :anthropic)
    # @param api [Symbol, String] the API key (e.g., :chat_completions, :messages)
    # @return [Array<Symbol>] array of tool symbols (e.g., [:functions, :web_search])
    #
    # @example
    #   ApiCapabilities.tools_for(:openai, :chat_completions)
    #   # => [:functions]
    #
    #   ApiCapabilities.tools_for(:openai, :responses)
    #   # => [:web_search, :file_search, :code_interpreter, :functions]
    def self.tools_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :tools) || []
    end

    # Check if a provider/API combination supports tools.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Boolean] true if the API supports any tools
    #
    # @example
    #   ApiCapabilities.supports_tools?(:openai, :chat_completions)
    #   # => true
    def self.supports_tools?(provider, api)
      tools_for(provider, api).any?
    end

    # Check if a provider/API supports a specific feature.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @param feature [Symbol, String] the feature to check (e.g., :streaming, :vision)
    # @return [Boolean] true if the feature is supported
    #
    # @example
    #   ApiCapabilities.supports_feature?(:openai, :chat_completions, :streaming)
    #   # => true
    def self.supports_feature?(provider, api, feature)
      return false if provider.nil? || api.nil? || feature.nil?

      features = CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
      features.include?(feature.to_sym)
    end

    # Get all features for a provider/API combination.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Array<Symbol>] array of feature symbols
    #
    # @example
    #   ApiCapabilities.features_for(:openai, :chat_completions)
    #   # => [:template_based]
    def self.features_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
    end

    # Get playground UI panels for a provider/API combination.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Array<Symbol>] array of UI panel symbols
    #
    # @example
    #   ApiCapabilities.playground_ui_for(:openai, :chat_completions)
    #   # => [:system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config]
    #
    #   ApiCapabilities.playground_ui_for(:openai, :assistants)
    #   # => [:system_prompt, :conversation, :tools, :model_config]
    def self.playground_ui_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :playground_ui) || []
    end

    # Check if a specific UI panel should be shown for a provider/API combination.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @param panel [Symbol, String] the panel to check (e.g., :system_prompt, :variables)
    # @return [Boolean] true if the panel should be shown
    #
    # @example
    #   ApiCapabilities.show_ui_panel?(:openai, :chat_completions, :variables)
    #   # => true
    #
    #   ApiCapabilities.show_ui_panel?(:openai, :assistants, :variables)
    #   # => false
    def self.show_ui_panel?(provider, api, panel)
      return false if provider.nil? || api.nil? || panel.nil?

      ui_panels = playground_ui_for(provider, api)
      ui_panels.include?(panel.to_sym)
    end

    # Get the entire capabilities matrix as a hash (for serialization to JSON).
    #
    # @return [Hash] the complete capabilities matrix
    def self.to_h
      CAPABILITIES
    end
  end
end
