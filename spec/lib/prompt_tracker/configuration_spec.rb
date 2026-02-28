# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe Configuration do
    let(:config) { Configuration.new }

    describe "#initialize" do
      it "sets basic_auth_username to nil" do
        expect(config.basic_auth_username).to be_nil
      end

      it "sets basic_auth_password to nil" do
        expect(config.basic_auth_password).to be_nil
      end

      it "sets providers to empty hash" do
        expect(config.providers).to eq({})
      end

      it "sets contexts to empty hash" do
        expect(config.contexts).to eq({})
      end

      it "sets features to empty hash" do
        expect(config.features).to eq({})
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
        config.providers = {
          openai: { api_key: "sk-test-openai", name: "OpenAI" },
          anthropic: { api_key: "sk-test-anthropic", name: "Anthropic" },
          google: { api_key: nil, name: "Google" }
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
        config.providers = {
          openai: { api_key: "sk-test-openai", name: "OpenAI" },
          anthropic: { api_key: "sk-test-anthropic", name: "Anthropic" },
          google: { api_key: nil, name: "Google" }
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

    describe "#enabled_providers" do
      before do
        config.providers = {
          openai: { api_key: "sk-test-openai", name: "OpenAI" },
          anthropic: { api_key: "sk-test-anthropic", name: "Anthropic" },
          google: { api_key: nil, name: "Google" },
          azure: { api_key: "", name: "Azure" }
        }
      end

      it "returns only providers with non-blank API keys" do
        expect(config.enabled_providers).to contain_exactly(:openai, :anthropic)
      end
    end

    describe "#models_for_provider" do
      before do
        config.providers = {
          openai: {
            api_key: "sk-test-openai",
            name: "OpenAI",
            models: [
              { id: "gpt-4o", name: "GPT-4o", capabilities: [ :chat, :structured_output ] },
              { id: "gpt-4", name: "GPT-4", capabilities: [ :chat ] }
            ]
          },
          anthropic: {
            api_key: "sk-test-anthropic",
            name: "Anthropic",
            models: [
              { id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", capabilities: [ :chat, :structured_output ] }
            ]
          },
          google: { api_key: nil, name: "Google" }
        }
      end

      it "returns models from RubyLLM for a configured provider" do
        result = config.models_for_provider(:openai)
        expect(result).to be_an(Array)
        expect(result.length).to be > 0
        # Should include well-known models (RubyLLM provides these)
        model_ids = result.map { |m| m[:id] }
        expect(model_ids).to include("gpt-4o")
        # Each model should have expected structure
        result.each do |model|
          expect(model).to have_key(:id)
          expect(model).to have_key(:name)
          expect(model).to have_key(:capabilities)
        end
      end

      it "returns models from RubyLLM for Google (mapped from gemini)" do
        result = config.models_for_provider(:google)
        expect(result).to be_an(Array)
        # Google models should exist in RubyLLM (mapped from "gemini" provider)
        expect(result.length).to be > 0
        model_ids = result.map { |m| m[:id] }
        expect(model_ids.any? { |id| id.include?("gemini") }).to be true
      end

      it "returns empty array for unknown provider" do
        result = config.models_for_provider(:unknown)
        expect(result).to eq([])
      end

      it "handles string provider names" do
        result = config.models_for_provider("openai")
        expect(result).to be_an(Array)
        expect(result.length).to be > 0
        expect(result.map { |m| m[:id] }).to include("gpt-4o")
      end
    end

    describe "#context_default" do
      before do
        config.contexts = {
          playground: {
            description: "Prompt testing",
            default_provider: :openai,
            default_api: :chat_completions,
            default_model: "gpt-4o"
          },
          llm_judge: {
            description: "LLM evaluation",
            default_provider: :anthropic,
            default_api: :messages,
            default_model: "claude-3-5-sonnet"
          }
        }
      end

      it "returns the default value for a context attribute" do
        expect(config.context_default(:playground, :provider)).to eq(:openai)
        expect(config.context_default(:playground, :api)).to eq(:chat_completions)
        expect(config.context_default(:playground, :model)).to eq("gpt-4o")
      end

      it "returns nil for unknown context" do
        expect(config.context_default(:unknown, :provider)).to be_nil
      end

      it "returns nil for unknown attribute" do
        expect(config.context_default(:playground, :unknown_attr)).to be_nil
      end
    end

    describe "#default_model_for" do
      before do
        config.contexts = {
          playground: { default_model: "gpt-4o" },
          llm_judge: { default_model: "claude-3-5-sonnet" }
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
        config.contexts = {
          playground: { default_provider: :openai },
          llm_judge: { default_provider: :anthropic }
        }
      end

      it "returns the default provider for the context" do
        expect(config.default_provider_for(:playground)).to eq(:openai)
        expect(config.default_provider_for(:llm_judge)).to eq(:anthropic)
      end

      it "returns nil for unknown context" do
        expect(config.default_provider_for(:unknown)).to be_nil
      end
    end

    describe "#default_api_for" do
      before do
        config.contexts = {
          playground: { default_api: :chat_completions },
          llm_judge: { default_api: :messages }
        }
      end

      it "returns the default API for the context" do
        expect(config.default_api_for(:playground)).to eq(:chat_completions)
        expect(config.default_api_for(:llm_judge)).to eq(:messages)
      end

      it "returns nil for unknown context" do
        expect(config.default_api_for(:unknown)).to be_nil
      end
    end

    describe "#feature_enabled?" do
      before do
        config.features = {
          openai_assistant_sync: true,
          experimental_ui: false
        }
      end

      it "returns true for enabled features" do
        expect(config.feature_enabled?(:openai_assistant_sync)).to be true
      end

      it "returns false for disabled features" do
        expect(config.feature_enabled?(:experimental_ui)).to be false
      end

      it "returns false for unknown features" do
        expect(config.feature_enabled?(:unknown_feature)).to be false
      end

      it "handles string feature names" do
        expect(config.feature_enabled?("openai_assistant_sync")).to be true
      end
    end

    describe "#tools_for_api" do
      context "with OpenAI provider" do
        it "returns functions for chat_completions API (no builtin tools, but model supports function_calling by default)" do
          tools = config.tools_for_api(:openai, :chat_completions)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)

          functions_tool = tools.first
          expect(functions_tool[:id]).to eq("functions")
          expect(functions_tool[:name]).to eq("Functions")
          expect(functions_tool[:description]).to eq("Define custom function schemas")
          expect(functions_tool[:icon]).to eq("bi-braces-asterisk")
          expect(functions_tool[:configurable]).to be true
        end

        it "returns builtin tools + functions for responses API" do
          tools = config.tools_for_api(:openai, :responses)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(4)

          tool_ids = tools.map { |t| t[:id] }
          expect(tool_ids).to contain_exactly("web_search", "file_search", "code_interpreter", "functions")

          # Verify metadata structure
          tools.each do |tool|
            expect(tool).to have_key(:id)
            expect(tool).to have_key(:name)
            expect(tool).to have_key(:description)
            expect(tool).to have_key(:icon)
            expect(tool).to have_key(:configurable)
          end

          # Verify configurable flags
          file_search = tools.find { |t| t[:id] == "file_search" }
          expect(file_search[:configurable]).to be true

          web_search = tools.find { |t| t[:id] == "web_search" }
          expect(web_search[:configurable]).to be false
        end

        it "returns builtin tools + functions for assistants API" do
          tools = config.tools_for_api(:openai, :assistants)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(3)

          tool_ids = tools.map { |t| t[:id] }
          expect(tool_ids).to contain_exactly("code_interpreter", "file_search", "functions")
        end
      end

      context "with Anthropic provider" do
        it "returns functions for messages API (no builtin tools)" do
          tools = config.tools_for_api(:anthropic, :messages)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)

          functions_tool = tools.first
          expect(functions_tool[:id]).to eq("functions")
          expect(functions_tool[:name]).to eq("Functions")
        end
      end

      context "with unknown provider" do
        it "returns only functions (model supports function_calling by default)" do
          tools = config.tools_for_api(:unknown_provider, :chat_completions)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end

      context "with unknown API" do
        it "returns only functions for known provider but unknown API" do
          tools = config.tools_for_api(:openai, :unknown_api)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end

      context "with nil arguments" do
        it "returns only functions when provider is nil" do
          tools = config.tools_for_api(nil, :chat_completions)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end

        it "returns only functions when API is nil" do
          tools = config.tools_for_api(:openai, nil)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end

        it "returns only functions when both are nil" do
          tools = config.tools_for_api(nil, nil)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end

      context "with string arguments" do
        it "converts strings to symbols" do
          tools = config.tools_for_api("openai", "chat_completions")

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)
          expect(tools.first[:id]).to eq("functions")
        end
      end
    end

    # =========================================================================
    # Dynamic Configuration (configuration_provider)
    # =========================================================================

    describe "#configuration_provider" do
      it "defaults to nil" do
        expect(config.configuration_provider).to be_nil
      end

      it "can be set to a Proc" do
        provider = -> { { providers: { openai: { api_key: "dynamic-key" } } } }
        config.configuration_provider = provider
        expect(config.configuration_provider).to eq(provider)
      end
    end

    describe "#dynamic_configuration?" do
      it "returns false when configuration_provider is nil" do
        config.configuration_provider = nil
        expect(config.dynamic_configuration?).to be false
      end

      it "returns true when configuration_provider is set" do
        config.configuration_provider = -> { {} }
        expect(config.dynamic_configuration?).to be true
      end
    end

    describe "#effective_providers" do
      context "without configuration_provider" do
        before do
          config.providers = { openai: { api_key: "static-key" } }
        end

        it "returns static providers" do
          expect(config.effective_providers).to eq({ openai: { api_key: "static-key" } })
        end
      end

      context "with configuration_provider" do
        before do
          config.providers = { openai: { api_key: "static-key" } }
          config.configuration_provider = -> {
            { providers: { openai: { api_key: "dynamic-key" }, anthropic: { api_key: "anthropic-key" } } }
          }
        end

        it "returns dynamic providers" do
          expect(config.effective_providers).to eq({
            openai: { api_key: "dynamic-key" },
            anthropic: { api_key: "anthropic-key" }
          })
        end

        it "affects api_key_for" do
          expect(config.api_key_for(:openai)).to eq("dynamic-key")
          expect(config.api_key_for(:anthropic)).to eq("anthropic-key")
        end

        it "affects enabled_providers" do
          expect(config.enabled_providers).to contain_exactly(:openai, :anthropic)
        end

        it "affects provider_configured?" do
          expect(config.provider_configured?(:openai)).to be true
          expect(config.provider_configured?(:anthropic)).to be true
        end
      end

      context "when configuration_provider returns nil for providers" do
        before do
          config.providers = { openai: { api_key: "static-key" } }
          config.configuration_provider = -> { { contexts: {} } }
        end

        it "falls back to static providers" do
          expect(config.effective_providers).to eq({ openai: { api_key: "static-key" } })
        end
      end
    end

    describe "#effective_contexts" do
      context "without configuration_provider" do
        before do
          config.contexts = { playground: { default_model: "gpt-4o" } }
        end

        it "returns static contexts" do
          expect(config.effective_contexts).to eq({ playground: { default_model: "gpt-4o" } })
        end
      end

      context "with configuration_provider" do
        before do
          config.contexts = { playground: { default_model: "gpt-4o" } }
          config.configuration_provider = -> {
            { contexts: { playground: { default_model: "claude-3" }, llm_judge: { default_model: "gpt-4o" } } }
          }
        end

        it "returns dynamic contexts" do
          expect(config.effective_contexts).to eq({
            playground: { default_model: "claude-3" },
            llm_judge: { default_model: "gpt-4o" }
          })
        end

        it "affects context_default" do
          expect(config.context_default(:playground, :model)).to eq("claude-3")
          expect(config.context_default(:llm_judge, :model)).to eq("gpt-4o")
        end
      end

      context "when configuration_provider returns nil for contexts" do
        before do
          config.contexts = { playground: { default_model: "gpt-4o" } }
          config.configuration_provider = -> { { providers: {} } }
        end

        it "falls back to static contexts" do
          expect(config.effective_contexts).to eq({ playground: { default_model: "gpt-4o" } })
        end
      end
    end

    describe "#effective_features" do
      context "without configuration_provider" do
        before do
          config.features = { openai_assistant_sync: true }
        end

        it "returns static features" do
          expect(config.effective_features).to eq({ openai_assistant_sync: true })
        end
      end

      context "with configuration_provider" do
        before do
          config.features = { openai_assistant_sync: false }
          config.configuration_provider = -> {
            { features: { openai_assistant_sync: true, new_feature: true } }
          }
        end

        it "returns dynamic features" do
          expect(config.effective_features).to eq({
            openai_assistant_sync: true,
            new_feature: true
          })
        end

        it "affects feature_enabled?" do
          expect(config.feature_enabled?(:openai_assistant_sync)).to be true
          expect(config.feature_enabled?(:new_feature)).to be true
        end
      end

      context "when configuration_provider returns nil for features" do
        before do
          config.features = { openai_assistant_sync: true }
          config.configuration_provider = -> { { providers: {} } }
        end

        it "falls back to static features" do
          expect(config.effective_features).to eq({ openai_assistant_sync: true })
        end
      end
    end

    describe "#ruby_llm_config" do
      it "returns empty hash when no providers configured" do
        expect(config.ruby_llm_config).to eq({})
      end

      it "maps provider api_keys to RubyLLM config keys" do
        config.providers = {
          openai: { api_key: "sk-openai" },
          anthropic: { api_key: "sk-anthropic" },
          google: { api_key: "google-key" }
        }

        result = config.ruby_llm_config

        expect(result[:openai_api_key]).to eq("sk-openai")
        expect(result[:anthropic_api_key]).to eq("sk-anthropic")
        expect(result[:gemini_api_key]).to eq("google-key")
      end

      it "uses effective_providers when configuration_provider is set" do
        config.providers = { openai: { api_key: "static-key" } }
        config.configuration_provider = -> {
          { providers: { openai: { api_key: "dynamic-key" } } }
        }

        result = config.ruby_llm_config

        expect(result[:openai_api_key]).to eq("dynamic-key")
      end

      it "excludes providers with nil or blank api_keys" do
        config.providers = {
          openai: { api_key: "sk-openai" },
          anthropic: { api_key: nil },
          google: { api_key: "" }
        }

        result = config.ruby_llm_config

        expect(result).to have_key(:openai_api_key)
        expect(result).not_to have_key(:anthropic_api_key)
        expect(result).not_to have_key(:gemini_api_key)
      end
    end
  end
end
