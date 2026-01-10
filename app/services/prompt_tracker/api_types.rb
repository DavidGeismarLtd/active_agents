# frozen_string_literal: true

module PromptTracker
  # Defines the API types supported by the evaluator system.
  #
  # These constants represent the different AI provider APIs that can be used
  # for generating responses. Evaluators declare which API types they are
  # compatible with, allowing the system to filter evaluators based on the
  # API being used.
  #
  # @example Check if evaluator is compatible with an API
  #   evaluator_class.compatible_with_api?(ApiTypes::OPENAI_CHAT_COMPLETION)
  #
  # @example Get all API types
  #   ApiTypes::ALL # => [:openai_chat_completion, :openai_response_api, ...]
  #
  module ApiTypes
    # OpenAI Chat Completions API (single-turn or multi-turn with manual state management)
    OPENAI_CHAT_COMPLETION = :openai_chat_completion

    # OpenAI Responses API (stateful conversations with built-in memory)
    OPENAI_RESPONSE_API = :openai_response_api

    # OpenAI Assistants API (stateful with threads, runs, and tool execution)
    OPENAI_ASSISTANTS_API = :openai_assistants_api

    # Anthropic Messages API
    ANTHROPIC_MESSAGES = :anthropic_messages

    # All supported API types
    ALL = [
      OPENAI_CHAT_COMPLETION,
      OPENAI_RESPONSE_API,
      OPENAI_ASSISTANTS_API,
      ANTHROPIC_MESSAGES
    ].freeze

    # APIs that support single-response evaluation
    SINGLE_RESPONSE_APIS = [
      OPENAI_CHAT_COMPLETION,
      OPENAI_RESPONSE_API,
      ANTHROPIC_MESSAGES
    ].freeze

    # APIs that support conversational evaluation
    CONVERSATIONAL_APIS = [
      OPENAI_RESPONSE_API,
      OPENAI_ASSISTANTS_API
    ].freeze

    # Returns all API types
    #
    # @return [Array<Symbol>] all API type symbols
    def self.all
      ALL
    end

    # Check if a value is a valid API type
    #
    # @param value [Symbol, String] the value to check
    # @return [Boolean] true if the value is a valid API type
    def self.valid?(value)
      return false if value.nil?

      ALL.include?(value.to_sym)
    end

    # Returns APIs that support single-response evaluation
    #
    # @return [Array<Symbol>] API types for single-response
    def self.single_response_apis
      SINGLE_RESPONSE_APIS
    end

    # Returns APIs that support conversational evaluation
    #
    # @return [Array<Symbol>] API types for conversational
    def self.conversational_apis
      CONVERSATIONAL_APIS
    end

    # Get human-readable name for an API type
    #
    # @param api_type [Symbol] the API type
    # @return [String] human-readable name
    def self.display_name(api_type)
      case api_type.to_sym
      when OPENAI_CHAT_COMPLETION
        "OpenAI Chat Completion"
      when OPENAI_RESPONSE_API
        "OpenAI Response API"
      when OPENAI_ASSISTANTS_API
        "OpenAI Assistants API"
      when ANTHROPIC_MESSAGES
        "Anthropic Messages"
      else
        api_type.to_s.titleize
      end
    end
  end
end
