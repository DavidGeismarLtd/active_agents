# frozen_string_literal: true

module PromptTracker
  # Default provider configuration.
  #
  # Defines default names and APIs for each supported provider.
  # RubyLLM does not provide API information, so we define it here.
  #
  # @example Get provider defaults
  #   ProviderDefaults.for(:openai)
  #   # => { name: "OpenAI", apis: { chat_completions: { name: "Chat Completions", default: true }, ... } }
  #
  module ProviderDefaults
    DEFAULTS = {
      openai: {
        name: "OpenAI",
        apis: {
          chat_completions: { name: "Chat Completions", description: "Standard chat API with messages", default: true },
          responses: { name: "Responses", description: "Stateful conversations with built-in tools" },
          assistants: { name: "Assistants", description: "Full assistant features with threads and runs" }
        }
      },
      anthropic: {
        name: "Anthropic",
        apis: {
          messages: { name: "Messages", description: "Claude chat API", default: true }
        }
      },
      google: {
        name: "Google Gemini",
        apis: {
          generate_content: { name: "Generate Content", description: "Gemini chat API", default: true }
        }
      },
      gemini: {
        name: "Google Gemini",
        apis: {
          generate_content: { name: "Generate Content", description: "Gemini chat API", default: true }
        }
      },
      deepseek: {
        name: "DeepSeek",
        apis: {
          chat: { name: "Chat", description: "DeepSeek chat API", default: true }
        }
      },
      mistral: {
        name: "Mistral",
        apis: {
          chat: { name: "Chat", description: "Mistral chat API", default: true }
        }
      },
      perplexity: {
        name: "Perplexity",
        apis: {
          chat: { name: "Chat", description: "Perplexity chat API with search", default: true }
        }
      },
      openrouter: {
        name: "OpenRouter",
        apis: {
          chat: { name: "Chat", description: "OpenRouter unified API", default: true }
        }
      },
      xai: {
        name: "xAI",
        apis: {
          chat: { name: "Chat", description: "Grok chat API", default: true }
        }
      },
      bedrock: {
        name: "AWS Bedrock",
        apis: {
          invoke: { name: "Invoke Model", description: "Bedrock unified API", default: true }
        }
      },
      azure: {
        name: "Azure OpenAI",
        apis: {
          chat_completions: { name: "Chat Completions", description: "Azure OpenAI chat API", default: true }
        }
      },
      vertexai: {
        name: "Google Vertex AI",
        apis: {
          generate_content: { name: "Generate Content", description: "Vertex AI chat API", default: true }
        }
      },
      ollama: {
        name: "Ollama",
        apis: {
          chat: { name: "Chat", description: "Ollama local chat API", default: true }
        }
      }
    }.freeze

    class << self
      # Get default configuration for a provider.
      #
      # @param provider [Symbol] Provider key
      # @return [Hash, nil] Default configuration hash or nil if unknown provider
      def for(provider)
        DEFAULTS[provider.to_sym]
      end

      # Get default provider name.
      #
      # @param provider [Symbol] Provider key
      # @return [String, nil] Default display name or nil
      def name_for(provider)
        DEFAULTS.dig(provider.to_sym, :name)
      end

      # Get default APIs for a provider.
      #
      # @param provider [Symbol] Provider key
      # @return [Hash] Default APIs hash or empty hash
      def apis_for(provider)
        DEFAULTS.dig(provider.to_sym, :apis) || {}
      end

      # Get all supported provider keys.
      #
      # @return [Array<Symbol>] Array of provider symbols
      def supported_providers
        DEFAULTS.keys
      end
    end
  end
end
