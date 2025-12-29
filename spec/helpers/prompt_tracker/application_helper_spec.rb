# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApplicationHelper, type: :helper do
    before do
      PromptTracker.configuration.api_keys = {
        openai: "sk-test-openai",
        anthropic: "sk-test-anthropic",
        google: nil
      }
      PromptTracker.configuration.models = {
        openai: [
          { id: "gpt-4o", name: "GPT-4o", category: "Latest", capabilities: [ :chat, :structured_output ] },
          { id: "gpt-4", name: "GPT-4", category: "GPT-4", capabilities: [ :chat ] }
        ],
        anthropic: [
          { id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", capabilities: [ :chat, :structured_output ] }
        ],
        google: [
          { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", capabilities: [ :chat ] }
        ]
      }
      PromptTracker.configuration.contexts = {
        playground: { providers: nil, models: nil, require_capability: nil },
        llm_judge: { providers: [ :openai ], models: nil, require_capability: :structured_output }
      }
      PromptTracker.configuration.defaults = {
        playground_provider: :openai,
        playground_model: "gpt-4o",
        llm_judge_model: "gpt-4o"
      }
    end

    describe "#provider_api_key_present?" do
      context "when API key is present" do
        it "returns true for string provider" do
          expect(helper.provider_api_key_present?("openai")).to be true
        end

        it "returns true for symbol provider" do
          expect(helper.provider_api_key_present?(:openai)).to be true
        end
      end

      context "when API key is missing" do
        it "returns false" do
          expect(helper.provider_api_key_present?(:google)).to be false
        end
      end

      context "when provider is not configured" do
        it "returns false" do
          expect(helper.provider_api_key_present?("unknown_provider")).to be false
        end
      end
    end

    describe "#providers_for" do
      context "when context has no restrictions" do
        it "returns all configured providers" do
          expect(helper.providers_for(:playground)).to contain_exactly(:openai, :anthropic)
        end
      end

      context "when context has provider restrictions" do
        it "returns only allowed providers that are also configured" do
          expect(helper.providers_for(:llm_judge)).to contain_exactly(:openai)
        end
      end
    end

    describe "#available_providers" do
      it "returns all configured providers" do
        expect(helper.available_providers).to contain_exactly(:openai, :anthropic)
      end

      context "when no API keys are configured" do
        before do
          PromptTracker.configuration.api_keys = {}
        end

        it "returns empty array" do
          expect(helper.available_providers).to be_empty
        end
      end
    end

    describe "#models_for" do
      context "without provider filter" do
        it "returns models from all available providers" do
          result = helper.models_for(:playground)
          expect(result.keys).to contain_exactly(:openai, :anthropic)
        end
      end

      context "with provider filter" do
        it "returns only models from that provider" do
          result = helper.models_for(:playground, provider: :openai)
          expect(result).to be_an(Array)
          expect(result.map { |m| m[:id] }).to contain_exactly("gpt-4o", "gpt-4")
        end
      end

      context "when context requires a capability" do
        it "filters models by capability" do
          result = helper.models_for(:llm_judge)
          expect(result[:openai].map { |m| m[:id] }).to contain_exactly("gpt-4o")
        end
      end
    end

    describe "#default_model_for" do
      it "returns the default model for the context" do
        expect(helper.default_model_for(:playground)).to eq("gpt-4o")
      end

      it "returns nil for unknown context" do
        expect(helper.default_model_for(:unknown)).to be_nil
      end
    end

    describe "#default_provider_for" do
      it "returns the default provider for the context" do
        expect(helper.default_provider_for(:playground)).to eq(:openai)
      end

      it "returns nil for unknown context" do
        expect(helper.default_provider_for(:unknown)).to be_nil
      end
    end
  end
end
