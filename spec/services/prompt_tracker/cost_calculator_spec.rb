# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe CostCalculator do
    describe "basic calculations" do
      it "calculates cost for OpenAI GPT-4" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 50)

        # Input: (100 / 1000) * 0.03 = 0.003
        # Output: (50 / 1000) * 0.06 = 0.003
        # Total: 0.006
        expect(cost).to eq(0.006)
      end

      it "calculates cost for OpenAI GPT-3.5-turbo" do
        calculator = described_class.new("openai", "gpt-3.5-turbo")
        cost = calculator.calculate(tokens_prompt: 1000, tokens_completion: 500)

        # Input: (1000 / 1000) * 0.0015 = 0.0015
        # Output: (500 / 1000) * 0.002 = 0.001
        # Total: 0.0025
        expect(cost).to eq(0.0025)
      end

      it "calculates cost for Anthropic Claude-3-Opus" do
        calculator = described_class.new("anthropic", "claude-3-opus")
        cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 50)

        # Input: (100 / 1000) * 0.015 = 0.0015
        # Output: (50 / 1000) * 0.075 = 0.00375
        # Total: 0.00525
        expect(cost).to eq(0.00525)
      end

      it "calculates cost for Google Gemini Pro" do
        calculator = described_class.new("google", "gemini-pro")
        cost = calculator.calculate(tokens_prompt: 1000, tokens_completion: 1000)

        # Input: (1000 / 1000) * 0.00025 = 0.00025
        # Output: (1000 / 1000) * 0.0005 = 0.0005
        # Total: 0.00075
        expect(cost).to eq(0.00075)
      end
    end

    describe "fuzzy model matching" do
      it "matches GPT-4 variants to base GPT-4 pricing" do
        variants = [ "gpt-4-0125-preview", "gpt-4-turbo-preview", "gpt-4-1106-preview" ]

        variants.each do |variant|
          calculator = described_class.new("openai", variant)
          expect(calculator.pricing_available?).to be(true), "Pricing should be available for #{variant}"
        end
      end

      it "matches Claude variants to base pricing" do
        calculator = described_class.new("anthropic", "claude-3-opus-20240229")
        expect(calculator.pricing_available?).to be true
        expect(calculator.input_price).to eq(0.015)
      end

      it "handles exact model matches" do
        calculator = described_class.new("openai", "gpt-4")
        expect(calculator.pricing_available?).to be true
        expect(calculator.input_price).to eq(0.03)
        expect(calculator.output_price).to eq(0.06)
      end
    end

    describe "edge cases" do
      it "returns 0 for zero tokens" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 0, tokens_completion: 0)
        expect(cost).to eq(0.0)
      end

      it "handles nil tokens" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: nil, tokens_completion: nil)
        expect(cost).to eq(0.0)
      end

      it "handles only prompt tokens" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 0)
        expect(cost).to eq(0.003)
      end

      it "handles only completion tokens" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 0, tokens_completion: 50)
        expect(cost).to eq(0.003)
      end
    end

    describe "unknown provider/model" do
      it "returns 0 for unknown provider" do
        calculator = described_class.new("unknown_provider", "some-model")
        expect(calculator.pricing_available?).to be false
        cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 50)
        expect(cost).to eq(0.0)
      end

      it "returns 0 for unknown model" do
        calculator = described_class.new("openai", "unknown-model")
        expect(calculator.pricing_available?).to be false
        cost = calculator.calculate(tokens_prompt: 100, tokens_completion: 50)
        expect(cost).to eq(0.0)
      end

      it "returns nil pricing for unknown provider" do
        calculator = described_class.new("unknown", "model")
        expect(calculator.input_price).to be_nil
        expect(calculator.output_price).to be_nil
      end
    end

    describe ".calculate class method" do
      it "calculates using class method" do
        cost = described_class.calculate(
          provider: "openai",
          model: "gpt-4",
          tokens_prompt: 100,
          tokens_completion: 50
        )
        expect(cost).to eq(0.006)
      end

      it "handles class method with zero tokens" do
        cost = described_class.calculate(
          provider: "openai",
          model: "gpt-4",
          tokens_prompt: 0,
          tokens_completion: 0
        )
        expect(cost).to eq(0.0)
      end
    end

    describe "provider/model listing" do
      it "lists available providers" do
        providers = described_class.available_providers
        expect(providers).to include("openai")
        expect(providers).to include("anthropic")
        expect(providers).to include("google")
        expect(providers).to include("cohere")
      end

      it "lists available models for OpenAI" do
        models = described_class.available_models("openai")
        expect(models).to include("gpt-4")
        expect(models).to include("gpt-3.5-turbo")
        expect(models).to include("gpt-4-turbo")
      end

      it "lists available models for Anthropic" do
        models = described_class.available_models("anthropic")
        expect(models).to include("claude-3-opus")
        expect(models).to include("claude-3-sonnet")
        expect(models).to include("claude-3-haiku")
      end

      it "returns empty array for unknown provider" do
        models = described_class.available_models("unknown")
        expect(models).to eq([])
      end
    end

    describe "case insensitivity" do
      it "handles case-insensitive provider names" do
        calculator = described_class.new("OpenAI", "gpt-4")
        expect(calculator.pricing_available?).to be true
      end

      it "handles case-insensitive model names" do
        calculator = described_class.new("openai", "GPT-4")
        expect(calculator.pricing_available?).to be true
      end
    end

    describe "pricing accuracy" do
      it "has correct pricing for all OpenAI models" do
        pricing = described_class::PRICING["openai"]
        expect(pricing["gpt-4"][:input]).to eq(0.03)
        expect(pricing["gpt-4"][:output]).to eq(0.06)
        expect(pricing["gpt-3.5-turbo"][:input]).to eq(0.0015)
        expect(pricing["gpt-3.5-turbo"][:output]).to eq(0.002)
      end

      it "has correct pricing for all Anthropic models" do
        pricing = described_class::PRICING["anthropic"]
        expect(pricing["claude-3-opus"][:input]).to eq(0.015)
        expect(pricing["claude-3-opus"][:output]).to eq(0.075)
        expect(pricing["claude-3-sonnet"][:input]).to eq(0.003)
        expect(pricing["claude-3-sonnet"][:output]).to eq(0.015)
      end
    end

    describe "large numbers" do
      it "handles large token counts" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 100_000, tokens_completion: 50_000)

        # Input: (100000 / 1000) * 0.03 = 3.0
        # Output: (50000 / 1000) * 0.06 = 3.0
        # Total: 6.0
        expect(cost).to eq(6.0)
      end

      it "rounds to 6 decimal places" do
        calculator = described_class.new("openai", "gpt-4")
        cost = calculator.calculate(tokens_prompt: 1, tokens_completion: 1)

        # Should be rounded to 6 decimals
        expect(cost).to eq(0.00009)
      end
    end

    describe "instance variables" do
      it "exposes provider and model" do
        calculator = described_class.new("openai", "gpt-4")
        expect(calculator.provider).to eq("openai")
        expect(calculator.model).to eq("gpt-4")
      end

      it "exposes pricing hash" do
        calculator = described_class.new("openai", "gpt-4")
        expect(calculator.pricing).to eq({ input: 0.03, output: 0.06 })
      end

      it "has nil pricing for unknown model" do
        calculator = described_class.new("openai", "unknown")
        expect(calculator.pricing).to be_nil
      end
    end
  end
end
