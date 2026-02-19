# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApplicationHelper, type: :helper do
    before do
      PromptTracker.configuration.providers = {
        openai: {
          api_key: "sk-test-openai",
          name: "OpenAI",
          apis: {
            chat_completions: { name: "Chat Completions", default: true }
          },
          models: [
            { id: "gpt-4o", name: "GPT-4o", category: "Latest", capabilities: [ :chat, :structured_output ] },
            { id: "gpt-4", name: "GPT-4", category: "GPT-4", capabilities: [ :chat ] }
          ]
        },
        anthropic: {
          api_key: "sk-test-anthropic",
          name: "Anthropic",
          apis: {
            messages: { name: "Messages", default: true }
          },
          models: [
            { id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", capabilities: [ :chat, :structured_output ] }
          ]
        },
        google: {
          api_key: nil,
          name: "Google",
          apis: {
            generative: { name: "Generative Language", default: true }
          },
          models: [
            { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", capabilities: [ :chat ] }
          ]
        }
      }
      PromptTracker.configuration.contexts = {
        playground: {
          description: "Prompt testing",
          default_provider: :openai,
          default_api: :chat_completions,
          default_model: "gpt-4o"
        },
        llm_judge: {
          description: "LLM evaluation",
          default_provider: :openai,
          default_api: :chat_completions,
          default_model: "gpt-4o"
        }
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

    describe "#enabled_providers" do
      it "returns all providers with API keys configured" do
        expect(helper.enabled_providers).to contain_exactly(:openai, :anthropic)
      end

      context "when no API keys are configured" do
        before do
          PromptTracker.configuration.providers = {}
        end

        it "returns empty array" do
          expect(helper.enabled_providers).to be_empty
        end
      end
    end

    describe "#models_for_provider" do
      it "returns models for a specific provider" do
        result = helper.models_for_provider(:openai)
        expect(result).to be_an(Array)
        expect(result.map { |m| m[:id] }).to contain_exactly("gpt-4o", "gpt-4")
      end

      it "returns empty array for provider without models" do
        PromptTracker.configuration.providers[:test] = { api_key: "key" }
        expect(helper.models_for_provider(:test)).to eq([])
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

    describe "#default_api_for" do
      it "returns the default API for the context" do
        expect(helper.default_api_for(:playground)).to eq(:chat_completions)
      end

      it "returns nil for unknown context" do
        expect(helper.default_api_for(:unknown)).to be_nil
      end
    end

    describe "#provider_name" do
      it "returns the display name for a provider" do
        expect(helper.provider_name(:openai)).to eq("OpenAI")
        expect(helper.provider_name(:anthropic)).to eq("Anthropic")
      end
    end
  end
end
