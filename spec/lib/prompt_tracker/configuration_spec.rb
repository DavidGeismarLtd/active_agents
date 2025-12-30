# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe Configuration do
    let(:config) { Configuration.new }

    describe "#initialize" do
      it "sets default prompts_path" do
        expect(config.prompts_path).to be_present
      end

      it "sets basic_auth_username to nil" do
        expect(config.basic_auth_username).to be_nil
      end

      it "sets basic_auth_password to nil" do
        expect(config.basic_auth_password).to be_nil
      end

      it "sets api_keys to empty hash" do
        expect(config.api_keys).to eq({})
      end

      it "sets models to empty hash" do
        expect(config.models).to eq({})
      end

      it "sets contexts to empty hash" do
        expect(config.contexts).to eq({})
      end

      it "sets defaults to empty hash" do
        expect(config.defaults).to eq({})
      end

      it "sets openai_assistants with nil api_key" do
        expect(config.openai_assistants[:api_key]).to be_nil
        expect(config.openai_assistants[:available_models]).to eq([])
      end
    end

    describe "#basic_auth_enabled?" do
      it "returns false when both username and password are nil" do
        config.basic_auth_username = nil
        config.basic_auth_password = nil
        expect(config.basic_auth_enabled?).to be false
      end

      it "returns false when only username is set" do
        config.basic_auth_username = "admin"
        config.basic_auth_password = nil
        expect(config.basic_auth_enabled?).to be false
      end

      it "returns false when only password is set" do
        config.basic_auth_username = nil
        config.basic_auth_password = "secret"
        expect(config.basic_auth_enabled?).to be false
      end

      it "returns true when both username and password are set" do
        config.basic_auth_username = "admin"
        config.basic_auth_password = "secret"
        expect(config.basic_auth_enabled?).to be true
      end
    end

    describe "#provider_configured?" do
      before do
        config.api_keys = {
          openai: "sk-test-openai",
          anthropic: "sk-test-anthropic",
          google: nil
        }
      end

      it "returns true for providers with API keys" do
        expect(config.provider_configured?(:openai)).to be true
        expect(config.provider_configured?(:anthropic)).to be true
      end

      it "returns false for providers without API keys" do
        expect(config.provider_configured?(:google)).to be false
      end

      it "returns false for unknown providers" do
        expect(config.provider_configured?(:unknown)).to be false
      end

      it "handles string provider names" do
        expect(config.provider_configured?("openai")).to be true
      end
    end

    describe "#api_key_for" do
      before do
        config.api_keys = {
          openai: "sk-test-openai",
          anthropic: "sk-test-anthropic",
          google: nil
        }
      end

      it "returns the API key for a configured provider" do
        expect(config.api_key_for(:openai)).to eq("sk-test-openai")
        expect(config.api_key_for(:anthropic)).to eq("sk-test-anthropic")
      end

      it "returns nil for providers without API keys" do
        expect(config.api_key_for(:google)).to be_nil
      end

      it "returns nil for unknown providers" do
        expect(config.api_key_for(:unknown)).to be_nil
      end

      it "handles string provider names" do
        expect(config.api_key_for("openai")).to eq("sk-test-openai")
      end
    end

    describe "#configured_providers" do
      before do
        config.api_keys = {
          openai: "sk-test-openai",
          anthropic: "sk-test-anthropic",
          google: nil,
          azure: ""
        }
      end

      it "returns only providers with non-blank API keys" do
        expect(config.configured_providers).to contain_exactly(:openai, :anthropic)
      end
    end

    describe "#providers_for" do
      before do
        config.api_keys = {
          openai: "sk-test-openai",
          anthropic: "sk-test-anthropic",
          google: nil
        }
        config.contexts = {
          playground: { providers: nil, models: nil, require_capability: nil },
          llm_judge: { providers: [ :openai ], models: nil, require_capability: :structured_output }
        }
      end

      context "when context has no restrictions" do
        it "returns all configured providers" do
          expect(config.providers_for(:playground)).to contain_exactly(:openai, :anthropic)
        end
      end

      context "when context has provider restrictions" do
        it "returns only allowed providers that are also configured" do
          expect(config.providers_for(:llm_judge)).to contain_exactly(:openai)
        end
      end

      context "when context restricts to unconfigured provider" do
        before do
          config.contexts[:google_only] = { providers: [ :google ], models: nil, require_capability: nil }
        end

        it "returns empty array" do
          expect(config.providers_for(:google_only)).to eq([])
        end
      end

      context "when context is not defined" do
        it "returns all configured providers" do
          expect(config.providers_for(:unknown_context)).to contain_exactly(:openai, :anthropic)
        end
      end
    end

    describe "#models_for" do
      before do
        config.api_keys = {
          openai: "sk-test-openai",
          anthropic: "sk-test-anthropic",
          google: nil
        }
        config.models = {
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
        config.contexts = {
          playground: { providers: nil, models: nil, require_capability: nil },
          llm_judge: { providers: [ :openai ], models: nil, require_capability: :structured_output },
          restricted: { providers: [ :openai ], models: [ "gpt-4o" ], require_capability: nil }
        }
      end

      context "without provider filter" do
        it "returns models from all available providers for context" do
          result = config.models_for(:playground)
          expect(result.keys).to contain_exactly(:openai, :anthropic)
          expect(result[:openai].map { |m| m[:id] }).to contain_exactly("gpt-4o", "gpt-4")
        end

        it "excludes providers without API keys" do
          result = config.models_for(:playground)
          expect(result.keys).not_to include(:google)
        end
      end

      context "with provider filter" do
        it "returns only models from that provider as an array" do
          result = config.models_for(:playground, provider: :openai)
          expect(result).to be_an(Array)
          expect(result.map { |m| m[:id] }).to contain_exactly("gpt-4o", "gpt-4")
        end

        it "returns empty array for unconfigured provider" do
          result = config.models_for(:playground, provider: :google)
          expect(result).to eq([])
        end
      end

      context "when context requires a capability" do
        it "filters models by capability" do
          result = config.models_for(:llm_judge)
          expect(result[:openai].map { |m| m[:id] }).to contain_exactly("gpt-4o")
          expect(result[:openai].map { |m| m[:id] }).not_to include("gpt-4")
        end
      end

      context "when context restricts to specific models" do
        it "only returns allowed models" do
          result = config.models_for(:restricted)
          expect(result[:openai].map { |m| m[:id] }).to contain_exactly("gpt-4o")
        end
      end
    end

    describe "#default_model_for" do
      before do
        config.defaults = {
          playground_model: "gpt-4o",
          llm_judge_model: "claude-3-5-sonnet"
        }
      end

      it "returns the default model for the context" do
        expect(config.default_model_for(:playground)).to eq("gpt-4o")
        expect(config.default_model_for(:llm_judge)).to eq("claude-3-5-sonnet")
      end

      it "returns nil for unknown context" do
        expect(config.default_model_for(:unknown)).to be_nil
      end
    end

    describe "#default_provider_for" do
      before do
        config.defaults = {
          playground_provider: :openai
        }
      end

      it "returns the default provider for the context" do
        expect(config.default_provider_for(:playground)).to eq(:openai)
      end

      it "returns nil for unknown context" do
        expect(config.default_provider_for(:unknown)).to be_nil
      end
    end

    describe "#openai_assistants_configured?" do
      context "when openai_assistants is configured with API key" do
        before do
          config.openai_assistants = {
            api_key: "sk-test",
            available_models: [ { id: "gpt-4o", name: "GPT-4o" } ]
          }
        end

        it "returns true" do
          expect(config.openai_assistants_configured?).to be true
        end
      end

      context "when openai_assistants has nil API key" do
        before do
          config.openai_assistants = { api_key: nil, available_models: [] }
        end

        it "returns false" do
          expect(config.openai_assistants_configured?).to be false
        end
      end

      context "when openai_assistants has blank API key" do
        before do
          config.openai_assistants = { api_key: "", available_models: [] }
        end

        it "returns false" do
          expect(config.openai_assistants_configured?).to be false
        end
      end
    end

    describe "#openai_assistants_models" do
      before do
        config.openai_assistants = {
          api_key: "sk-test",
          available_models: [
            { id: "gpt-4o", name: "GPT-4o" },
            { id: "gpt-4-turbo", name: "GPT-4 Turbo" }
          ]
        }
      end

      it "returns the configured models" do
        expect(config.openai_assistants_models.length).to eq(2)
        expect(config.openai_assistants_models.first[:id]).to eq("gpt-4o")
      end
    end

    describe "#openai_assistants_api_key" do
      before do
        config.openai_assistants = { api_key: "sk-asst-key", available_models: [] }
      end

      it "returns the API key" do
        expect(config.openai_assistants_api_key).to eq("sk-asst-key")
      end
    end
  end
end
