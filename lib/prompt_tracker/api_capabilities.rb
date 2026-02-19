# frozen_string_literal: true

module PromptTracker
  # ApiCapabilities defines what each provider/API combination supports.
  # This is the single source of truth for API-specific capabilities in the engine.
  #
  # **Important distinction:**
  # - `builtin_tools` = API-provided tools (web_search, file_search, code_interpreter)
  # - Model capabilities (function_calling, vision) come from RubyLLM, NOT here
  #
  # @example Get builtin tools for OpenAI Responses API
  #   ApiCapabilities.builtin_tools_for(:openai, :responses)
  #   # => [:web_search, :file_search, :code_interpreter]
  #
  # @example Get playground UI panels (with fallback to default)
  #   ApiCapabilities.playground_ui_for(:openai, :chat_completions)
  #   # => [:system_prompt, :user_prompt_template, :variables, ...]
  #
  #   ApiCapabilities.playground_ui_for(:unknown, :api)  # Falls back to DEFAULT
  #   # => [:system_prompt, :user_prompt_template, :variables, ...]
  #
  # @example Check if API requires remote entity sync
  #   ApiCapabilities.supports_feature?(:openai, :assistants, :remote_entity_linked)
  #   # => true
  module ApiCapabilities
    # Default playground UI panels for undeclared APIs.
    # Show everything by default for maximum flexibility.
    DEFAULT_PLAYGROUND_UI = [
      :system_prompt, :user_prompt_template, :variables,
      :preview, :conversation, :tools, :model_config
    ].freeze

    # Capability matrix defining what each provider/API supports.
    # Structure: { provider: { api: { builtin_tools: [...], features: [...], playground_ui: [...] } } }
    #
    # **builtin_tools** - API-provided tools (NOT model capabilities):
    # - :web_search - Web search (Responses API only)
    # - :file_search - File/vector search (Responses, Assistants)
    # - :code_interpreter - Python execution (Responses, Assistants)
    # NOTE: :functions is a MODEL capability, comes from RubyLLM, NOT here
    #
    # **Features** - Behavioral capabilities (non-UI):
    # - :remote_entity_linked - API requires syncing with remote entities (e.g., OpenAI Assistants)
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
          builtin_tools: [],
          features: [],
          playground_ui: DEFAULT_PLAYGROUND_UI
        },
        responses: {
          builtin_tools: [ :web_search, :file_search, :code_interpreter ],
          features: [],
          playground_ui: DEFAULT_PLAYGROUND_UI
        },
        assistants: {
          builtin_tools: [ :code_interpreter, :file_search ],
          features: [ :remote_entity_linked ],
          playground_ui: [ :system_prompt, :conversation, :tools, :model_config ]
        }
      },
      anthropic: {
        messages: {
          builtin_tools: [],
          features: [],
          playground_ui: DEFAULT_PLAYGROUND_UI
        }
      }
    }.freeze

    # Get API-specific built-in tools for a provider/API combination.
    # These are tools provided by the API itself, NOT model capabilities.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai, :anthropic)
    # @param api [Symbol, String] the API key (e.g., :chat_completions, :messages)
    # @return [Array<Symbol>] array of builtin tool symbols (e.g., [:web_search, :file_search])
    #
    # @example
    #   ApiCapabilities.builtin_tools_for(:openai, :chat_completions)
    #   # => []  # No builtin tools, but model may support function_calling
    #
    #   ApiCapabilities.builtin_tools_for(:openai, :responses)
    #   # => [:web_search, :file_search, :code_interpreter]
    def self.builtin_tools_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :builtin_tools) || []
    end

    # Check if a provider/API supports a specific feature.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @param feature [Symbol, String] the feature to check (e.g., :remote_entity_linked)
    # @return [Boolean] true if the feature is supported
    #
    # @example
    #   ApiCapabilities.supports_feature?(:openai, :assistants, :remote_entity_linked)
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
    #   ApiCapabilities.features_for(:openai, :assistants)
    #   # => [:remote_entity_linked]
    def self.features_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
    end

    # Get playground UI panels for a provider/API combination.
    # Returns DEFAULT_PLAYGROUND_UI for unknown provider/API combinations.
    #
    # @param provider [Symbol, String] the provider key
    # @param api [Symbol, String] the API key
    # @return [Array<Symbol>] array of UI panel symbols
    #
    # @example Known API
    #   ApiCapabilities.playground_ui_for(:openai, :assistants)
    #   # => [:system_prompt, :conversation, :tools, :model_config]
    #
    # @example Unknown API (falls back to default)
    #   ApiCapabilities.playground_ui_for(:unknown, :api)
    #   # => [:system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config]
    def self.playground_ui_for(provider, api)
      return DEFAULT_PLAYGROUND_UI if provider.nil? || api.nil?
      return DEFAULT_PLAYGROUND_UI if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :playground_ui) || DEFAULT_PLAYGROUND_UI
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
      return false if panel.nil?

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
