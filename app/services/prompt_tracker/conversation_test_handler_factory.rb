# frozen_string_literal: true

module PromptTracker
  # Factory for building conversation test handlers based on model configuration.
  #
  # This service encapsulates the logic for selecting the appropriate
  # handler class based on the API type (provider + api combination).
  #
  # All handlers are namespaced under their provider to maintain clear
  # separation of concerns and make it easy to add provider-specific logic.
  #
  # @example Build a handler for OpenAI Chat Completions
  #   handler = ConversationTestHandlerFactory.build(
  #     model_config: { provider: "openai", api: "chat_completions", model: "gpt-4o" },
  #     use_real_llm: true,
  #     testable: prompt_version
  #   )
  #   # Returns: TestRunners::Openai::ChatCompletionHandler
  #
  # @example Build a handler for OpenAI Response API
  #   handler = ConversationTestHandlerFactory.build(
  #     model_config: { provider: "openai", api: "responses", model: "gpt-4o" },
  #     use_real_llm: true
  #   )
  #   # Returns: TestRunners::Openai::ResponseApiHandler
  #
  class ConversationTestHandlerFactory
    class << self
      # Build a conversation test handler instance
      #
      # @param model_config [Hash] model configuration with provider, api, model
      # @param use_real_llm [Boolean] whether to use real LLM API or mock
      # @param testable [Object, nil] optional testable object (for test runners)
      # @return [TestRunners::ConversationTestHandler] handler instance
      # @raise [ArgumentError] if model_config is missing required keys
      def build(model_config:, use_real_llm: false, testable: nil)
        validate_model_config!(model_config)

        executor_class = executor_class_for(model_config)

        executor_class.new(
          model_config: model_config,
          use_real_llm: use_real_llm,
          testable: testable
        )
      end

      private

      # Validate model configuration has required keys
      #
      # @param model_config [Hash] model configuration
      # @raise [ArgumentError] if required keys are missing
      def validate_model_config!(model_config)
        config = model_config.with_indifferent_access

        if config[:provider].blank?
          raise ArgumentError, "model_config must include :provider"
        end

        if config[:api].blank?
          raise ArgumentError, "model_config must include :api"
        end
      end

      # Determine handler class based on model config
      #
      # Routes to provider-specific handlers based on the API type.
      # All handlers are namespaced under TestRunners::{Provider}::
      #
      # @param model_config [Hash] model configuration
      # @return [Class] handler class
      def executor_class_for(model_config)
        config = model_config.with_indifferent_access
        api_type = ApiTypes.from_config(config[:provider], config[:api])

        case api_type
        when :openai_responses
          # OpenAI Response API has special stateful conversation handling
          TestRunners::Openai::ResponseApiHandler
        when :openai_chat_completions
          # OpenAI Chat Completions API
          TestRunners::Openai::ChatCompletionHandler
        when :anthropic_messages
          # Anthropic uses the same completion pattern as OpenAI
          # For now, use the ChatCompletionHandler (could be split later if needed)
          TestRunners::Openai::ChatCompletionHandler
        when :google_gemini
          # Google Gemini uses the same completion pattern
          TestRunners::Openai::ChatCompletionHandler
        else
          # Fallback to ChatCompletionHandler for unknown API types
          # This handles any custom or future API types that follow the chat completion pattern
          TestRunners::Openai::ChatCompletionHandler
        end
      end
    end
  end
end
