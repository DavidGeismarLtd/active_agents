# frozen_string_literal: true

module PromptTracker
  # Adapter for fetching and normalizing model data from RubyLLM's model registry.
  #
  # RubyLLM maintains an up-to-date registry of models with rich metadata:
  # - capabilities (function_calling, etc.)
  # - context_window, max_output_tokens
  # - pricing (input/output per million tokens)
  # - modalities (text, image, audio)
  #
  # This adapter filters for chat-capable models and normalizes the data
  # to PromptTracker's model format.
  #
  # @example Get models for OpenAI
  #   models = RubyLlmModelAdapter.models_for(:openai)
  #   # => [{ id: "gpt-4o", name: "GPT-4o", capabilities: [:chat, :function_calling], ... }]
  #
  # @example Find a specific model
  #   model = RubyLlmModelAdapter.find_model("gpt-4o")
  #   # => { id: "gpt-4o", name: "GPT-4o", ... }
  #
  class RubyLlmModelAdapter
    # Maps PromptTracker provider symbols to RubyLLM provider strings.
    # RubyLLM uses lowercase strings for provider identification.
    PROVIDER_MAPPING = {
      openai: "openai",
      anthropic: "anthropic",
      google: "gemini",
      gemini: "gemini",
      deepseek: "deepseek",
      mistral: "mistral",
      perplexity: "perplexity",
      openrouter: "openrouter",
      xai: "xai",
      bedrock: "bedrock",
      azure: "azure",
      vertexai: "vertexai",
      ollama: "ollama"
    }.freeze

    class << self
      # Get all chat-capable models for a provider.
      #
      # @param provider [Symbol, String] PromptTracker provider key (e.g., :openai, :anthropic)
      # @return [Array<Hash>] Array of normalized model hashes
      def models_for(provider)
        ruby_llm_provider = PROVIDER_MAPPING[provider.to_sym]
        return [] unless ruby_llm_provider

        chat_models(ruby_llm_provider).map { |m| normalize_model(m) }
      end

      # Find a specific model by ID across all providers.
      #
      # @param model_id [String] Model ID (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")
      # @return [Hash, nil] Normalized model hash or nil if not found
      def find_model(model_id)
        return nil if model_id.blank?

        model = RubyLLM.models.find(model_id)
        return nil unless model

        normalize_model(model)
      end

      # Get capabilities for a specific model.
      #
      # @param model_id [String] Model ID
      # @return [Array<Symbol>] Array of capability symbols
      def capabilities_for(model_id)
        model = find_model(model_id)
        model&.dig(:capabilities) || []
      end

      private

      # Filter RubyLLM models to chat-capable models for a specific provider.
      def chat_models(ruby_llm_provider)
        RubyLLM.models.select do |model|
          model.provider == ruby_llm_provider && chat_capable?(model)
        end
      end

      # Determine if a model is chat-capable (not embedding, TTS, or image generation).
      def chat_capable?(model)
        model.modalities.output.include?("text") &&
          !embedding_model?(model) &&
          !image_generation_model?(model) &&
          !audio_only_model?(model)
      end

      # Check if model is an embedding model.
      def embedding_model?(model)
        model.id.include?("embed") || model.modalities.output.empty?
      end

      # Check if model is an image generation model.
      def image_generation_model?(model)
        model.id.include?("dall-e") ||
          model.id.include?("imagen") ||
          (model.modalities.output.include?("image") && !model.modalities.output.include?("text"))
      end

      # Check if model only handles audio (TTS/STT).
      def audio_only_model?(model)
        (model.id.include?("tts") || model.id.include?("whisper")) &&
          !model.modalities.output.include?("text")
      end

      # Normalize a RubyLLM model to PromptTracker's format.
      def normalize_model(model)
        {
          id: model.id,
          name: model.name || model.id.titleize,
          category: extract_category(model),
          capabilities: extract_capabilities(model),
          context_window: model.context_window,
          max_output_tokens: model.max_output_tokens,
          pricing: extract_pricing(model)
        }
      end

      # Extract category from model family.
      def extract_category(model)
        return "Other" if model.family.blank?

        model.family.to_s.titleize
      end

      # Map RubyLLM capabilities to PromptTracker capability symbols.
      def extract_capabilities(model)
        caps = [ :chat ]
        caps << :function_calling if model.capabilities.include?("function_calling")
        caps << :structured_output if model.capabilities.include?("structured_output")
        caps << :vision if model.modalities.input.include?("image")
        caps << :audio if model.modalities.input.include?("audio")
        caps
      end

      # Extract pricing information.
      # RubyLLM pricing structure: pricing.text_tokens.standard.{input_per_million, output_per_million}
      def extract_pricing(model)
        return nil unless model.pricing

        pricing_hash = model.pricing.to_h
        text_tokens = pricing_hash[:text_tokens]
        return nil unless text_tokens

        standard = text_tokens[:standard]
        return nil unless standard

        {
          input_per_million: standard[:input_per_million],
          output_per_million: standard[:output_per_million]
        }
      end
    end
  end
end
