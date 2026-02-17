# frozen_string_literal: true

module PromptTracker
  # Defines the API types supported by the system.
  #
  # Routes (provider, api) pairs to either specialized services or the unified RubyLLM service.
  #
  # Specialized APIs (require direct SDK):
  # - :openai_responses - Built-in tools (web_search, file_search, code_interpreter)
  # - :openai_assistants - Thread-based with persistent state
  #
  # All other provider/API combinations use :ruby_llm for unified handling via RubyLLM gem.
  #
  # @example Convert from config format
  #   ApiTypes.from_config(:openai, :responses) # => :openai_responses
  #   ApiTypes.from_config(:openai, :chat_completions) # => :ruby_llm
  #   ApiTypes.from_config(:anthropic, :messages) # => :ruby_llm
  #
  module ApiTypes
    # APIs that require direct SDK access (not through RubyLLM)
    SPECIALIZED_APIS = %i[openai_responses openai_assistants].freeze

    # All recognized API types (for display purposes)
    ALL_API_TYPES = %i[
      openai_responses
      openai_assistants
      ruby_llm
    ].freeze

    # Convert from config format (provider + api) to ApiType constant.
    #
    # Only OpenAI Responses and Assistants APIs get specialized routing.
    # All other provider/api combinations return :ruby_llm for unified handling.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai)
    # @param api [Symbol, String] the API key (e.g., :chat_completions)
    # @return [Symbol] the ApiType constant
    def self.from_config(provider, api)
      case [ provider&.to_s&.downcase, api&.to_s&.downcase ]
      when [ "openai", "responses" ]
        :openai_responses
      when [ "openai", "assistants" ]
        :openai_assistants
      else
        # All others use RubyLLM: openai/chat_completions, anthropic/*, google/*, etc.
        :ruby_llm
      end
    end

    # Check if API type requires direct SDK (not RubyLLM)
    #
    # @param api_type [Symbol] the API type
    # @return [Boolean] true if requires direct SDK
    def self.requires_direct_sdk?(api_type)
      SPECIALIZED_APIS.include?(api_type)
    end

    # Returns all API types
    #
    # @return [Array<Symbol>] all API type symbols
    def self.all
      ALL_API_TYPES
    end

    # Check if a value is a valid API type
    #
    # @param value [Symbol, String] the value to check
    # @return [Boolean] true if the value is a valid API type
    def self.valid?(value)
      return false if value.nil?

      ALL_API_TYPES.include?(value.to_sym)
    end

    # Get human-readable name for an API type
    #
    # @param api_type [Symbol] the API type
    # @return [String] human-readable name
    def self.display_name(api_type)
      case api_type.to_sym
      when :openai_responses
        "OpenAI Responses"
      when :openai_assistants
        "OpenAI Assistants"
      when :ruby_llm
        "RubyLLM (Universal)"
      else
        api_type.to_s.titleize
      end
    end
  end
end
