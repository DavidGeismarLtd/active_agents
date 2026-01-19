# frozen_string_literal: true

module PromptTracker
  # Defines the API types supported by the system.
  #
  # Maps (provider, api) pairs from configuration to unified API type constants.
  # This allows the system to work with a consistent set of API types regardless
  # of how they're configured.
  #
  # @example Convert from config format
  #   ApiTypes.from_config(:openai, :chat_completions) # => :openai_chat_completions
  #
  # @example Convert to config format
  #   ApiTypes.to_config(:openai_responses) # => { provider: :openai, api: :responses }
  #
  # @example Get all API types
  #   ApiTypes.all # => [:openai_chat_completions, :openai_responses, ...]
  #
  module ApiTypes
    # Mapping from config format (provider, api) to ApiType constant
    CONFIG_TO_API_TYPE = {
      %i[openai chat_completions] => :openai_chat_completions,
      %i[openai responses] => :openai_responses,
      %i[openai assistants] => :openai_assistants,
      %i[anthropic messages] => :anthropic_messages,
      %i[google gemini] => :google_gemini
    }.freeze

    # Mapping from ApiType constant to config format (provider, api)
    API_TYPE_TO_CONFIG = CONFIG_TO_API_TYPE.invert.freeze

    # Convert from config format (provider + api) to ApiType constant.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai)
    # @param api [Symbol, String] the API key (e.g., :chat_completions)
    # @return [Symbol, nil] the ApiType constant or nil if not found
    def self.from_config(provider, api)
      CONFIG_TO_API_TYPE[[ provider.to_sym, api.to_sym ]]
    end

    # Convert from ApiType constant to config format.
    #
    # @param api_type [Symbol] the ApiType constant
    # @return [Hash, nil] hash with :provider and :api keys, or nil if not found
    def self.to_config(api_type)
      result = API_TYPE_TO_CONFIG[api_type.to_sym]
      return nil unless result

      { provider: result[0], api: result[1] }
    end

    # Returns all API types
    #
    # @return [Array<Symbol>] all API type symbols
    def self.all
      CONFIG_TO_API_TYPE.values
    end

    # Check if a value is a valid API type
    #
    # @param value [Symbol, String] the value to check
    # @return [Boolean] true if the value is a valid API type
    def self.valid?(value)
      return false if value.nil?

      all.include?(value.to_sym)
    end

    # Get human-readable name for an API type
    #
    # @param api_type [Symbol] the API type
    # @return [String] human-readable name
    def self.display_name(api_type)
      case api_type.to_sym
      when :openai_chat_completions
        "OpenAI Chat Completions"
      when :openai_responses
        "OpenAI Responses"
      when :openai_assistants
        "OpenAI Assistants"
      when :anthropic_messages
        "Anthropic Messages"
      when :google_gemini
        "Google Gemini"
      else
        api_type.to_s.titleize
      end
    end
  end
end
