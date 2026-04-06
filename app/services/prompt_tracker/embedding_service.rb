# frozen_string_literal: true

module PromptTracker
  # Converts text to float vectors using a configured embedding provider.
  #
  # Supports multiple embedding backends. Currently implements OpenAI.
  # Adding a new provider means adding a `when :new_provider` branch.
  #
  # @example Embed text with defaults (OpenAI text-embedding-3-small)
  #   EmbeddingService.embed("What is the refund policy?")
  #   # => [0.023, -0.041, ...]
  #
  # @example Embed with explicit provider and model
  #   EmbeddingService.embed("Hello", provider: :openai, model: "text-embedding-3-large")
  #
  class EmbeddingService
    class EmbeddingError < StandardError; end

    # Embed text into a float vector.
    #
    # @param text [String] the text to embed
    # @param provider [Symbol] embedding provider (:openai)
    # @param model [String] model identifier
    # @return [Array<Float>] the embedding vector
    # @raise [EmbeddingError] if the provider is unsupported or the call fails
    def self.embed(text, provider: :openai, model: "text-embedding-3-small")
      case provider.to_sym
      when :openai
        embed_with_openai(text, model: model)
      else
        raise EmbeddingError, "Unsupported embedding provider: #{provider}"
      end
    end

    private

    def self.embed_with_openai(text, model:)
      require "openai"

      api_key = PromptTracker.configuration.api_key_for(:openai) || ENV["OPENAI_API_KEY"]
      raise EmbeddingError, "OpenAI API key not configured" if api_key.blank?

      client = OpenAI::Client.new(access_token: api_key)
      response = client.embeddings(parameters: { model: model, input: text })
      vector = response.dig("data", 0, "embedding")

      raise EmbeddingError, "Empty embedding response from OpenAI" if vector.blank?

      vector
    rescue EmbeddingError
      raise
    rescue StandardError => e
      raise EmbeddingError, "OpenAI embedding failed: #{e.message}"
    end
  end
end
