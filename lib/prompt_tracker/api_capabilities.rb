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
  module ApiCapabilities
    # Capability matrix defining what each provider/API supports.
    # Structure: { provider: { api: { tools: [...], features: [...] } } }
    CAPABILITIES = {
      openai: {
        chat_completions: {
          tools: [ :functions ],
          features: [ :streaming, :vision, :structured_output, :function_calling ]
        },
        responses: {
          tools: [ :web_search, :file_search, :code_interpreter, :functions ],
          features: [ :streaming, :conversation_state, :function_calling, :builtin_tools ]
        },
        assistants: {
          tools: [ :code_interpreter, :file_search, :functions ],
          features: [ :threads, :runs, :function_calling, :builtin_tools, :file_operations ]
        }
      },
      anthropic: {
        messages: {
          tools: [ :functions ],
          features: [ :streaming, :vision, :function_calling ]
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
    #   # => [:streaming, :vision, :structured_output, :function_calling]
    def self.features_for(provider, api)
      return [] if provider.nil? || api.nil?
      return [] if provider.to_s.empty? || api.to_s.empty?

      CAPABILITIES.dig(provider.to_sym, api.to_sym, :features) || []
    end
  end
end
