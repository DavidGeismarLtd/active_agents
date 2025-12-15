# frozen_string_literal: true

module PromptTracker
  # Calculates the cost of LLM API calls based on token usage.
  #
  # Different LLM providers charge different rates for input (prompt) and output (completion) tokens.
  # This service maintains a pricing database and calculates costs automatically.
  #
  # @example Calculate cost for a specific call
  #   calculator = CostCalculator.new("openai", "gpt-4")
  #   cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 50)
  #   # => 0.006 (USD)
  #
  # @example Using class method
  #   cost = CostCalculator.calculate(
  #     provider: "openai",
  #     model: "gpt-4",
  #     tokens_prompt: 100,
  #     tokens_completion: 50
  #   )
  #   # => 0.006 (USD)
  #
  # @example Fuzzy model matching
  #   calculator = CostCalculator.new("openai", "gpt-4-0125-preview")
  #   # Automatically matches to "gpt-4" pricing
  #
  class CostCalculator
    # Pricing per 1,000 tokens (in USD)
    # Updated as of January 2024
    PRICING = {
      "openai" => {
        "gpt-4" => { input: 0.03, output: 0.06 },
        "gpt-4-turbo" => { input: 0.01, output: 0.03 },
        "gpt-4-turbo-preview" => { input: 0.01, output: 0.03 },
        "gpt-3.5-turbo" => { input: 0.0015, output: 0.002 },
        "gpt-3.5-turbo-16k" => { input: 0.003, output: 0.004 }
      },
      "anthropic" => {
        "claude-3-opus" => { input: 0.015, output: 0.075 },
        "claude-3-sonnet" => { input: 0.003, output: 0.015 },
        "claude-3-haiku" => { input: 0.00025, output: 0.00125 },
        "claude-2.1" => { input: 0.008, output: 0.024 },
        "claude-2" => { input: 0.008, output: 0.024 },
        "claude-instant" => { input: 0.0008, output: 0.0024 }
      },
      "google" => {
        "gemini-pro" => { input: 0.00025, output: 0.0005 },
        "gemini-pro-vision" => { input: 0.00025, output: 0.0005 }
      },
      "cohere" => {
        "command" => { input: 0.001, output: 0.002 },
        "command-light" => { input: 0.0003, output: 0.0006 }
      }
    }.freeze

    attr_reader :provider, :model, :pricing

    # Initialize a new cost calculator
    #
    # @param provider [String] the LLM provider (e.g., "openai", "anthropic")
    # @param model [String] the model name (e.g., "gpt-4", "claude-3-opus")
    def initialize(provider, model)
      @provider = provider.to_s.downcase
      @model = model.to_s.downcase
      @pricing = find_pricing
    end

    # Calculate the cost of an LLM call
    #
    # @param tokens_prompt [Integer] number of input/prompt tokens
    # @param tokens_completion [Integer] number of output/completion tokens
    # @return [Float] total cost in USD
    def calculate(tokens_prompt: 0, tokens_completion: 0)
      return 0.0 if pricing.nil?
      return 0.0 if tokens_prompt.nil? && tokens_completion.nil?

      prompt_tokens = tokens_prompt.to_i
      completion_tokens = tokens_completion.to_i

      input_cost = (prompt_tokens / 1000.0) * pricing[:input]
      output_cost = (completion_tokens / 1000.0) * pricing[:output]

      (input_cost + output_cost).round(6)
    end

    # Check if pricing is available for this provider/model
    #
    # @return [Boolean] true if pricing is available
    def pricing_available?
      !pricing.nil?
    end

    # Get the input token price per 1K tokens
    #
    # @return [Float, nil] price in USD or nil if not available
    def input_price
      pricing&.dig(:input)
    end

    # Get the output token price per 1K tokens
    #
    # @return [Float, nil] price in USD or nil if not available
    def output_price
      pricing&.dig(:output)
    end

    # Class method for one-off calculations
    #
    # @param provider [String] the LLM provider
    # @param model [String] the model name
    # @param tokens_prompt [Integer] number of input tokens
    # @param tokens_completion [Integer] number of output tokens
    # @return [Float] total cost in USD
    def self.calculate(provider:, model:, tokens_prompt: 0, tokens_completion: 0)
      new(provider, model).calculate(
        tokens_prompt: tokens_prompt,
        tokens_completion: tokens_completion
      )
    end

    # Get all available providers
    #
    # @return [Array<String>] list of provider names
    def self.available_providers
      PRICING.keys
    end

    # Get all available models for a provider
    #
    # @param provider [String] the provider name
    # @return [Array<String>] list of model names
    def self.available_models(provider)
      PRICING.dig(provider.to_s.downcase)&.keys || []
    end

    private

    # Find pricing for the current provider/model
    # Uses fuzzy matching to handle model variants (e.g., "gpt-4-0125-preview" -> "gpt-4")
    #
    # @return [Hash, nil] pricing hash with :input and :output keys, or nil if not found
    def find_pricing
      provider_pricing = PRICING[provider]
      return nil if provider_pricing.nil?

      # Try exact match first
      return provider_pricing[model] if provider_pricing.key?(model)

      # Try fuzzy matching - find the first model key that the actual model starts with
      # e.g., "gpt-4-0125-preview" matches "gpt-4"
      matched_key = provider_pricing.keys.find { |key| model.start_with?(key) }
      return provider_pricing[matched_key] if matched_key

      # Try reverse fuzzy matching - find if any key starts with the model
      # e.g., "gpt-4" matches "gpt-4-turbo"
      matched_key = provider_pricing.keys.find { |key| key.start_with?(model) }
      return provider_pricing[matched_key] if matched_key

      nil
    end
  end
end
