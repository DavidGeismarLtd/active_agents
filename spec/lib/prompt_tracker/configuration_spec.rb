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

    describe "#tools_for_api" do
      context "with OpenAI provider" do
        it "returns enriched tool metadata for chat_completions API" do
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

        it "returns enriched tool metadata for responses API" do
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

        it "returns enriched tool metadata for assistants API" do
          tools = config.tools_for_api(:openai, :assistants)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(3)

          tool_ids = tools.map { |t| t[:id] }
          expect(tool_ids).to contain_exactly("code_interpreter", "file_search", "functions")
        end
      end

      context "with Anthropic provider" do
        it "returns enriched tool metadata for messages API" do
          tools = config.tools_for_api(:anthropic, :messages)

          expect(tools).to be_an(Array)
          expect(tools.length).to eq(1)

          functions_tool = tools.first
          expect(functions_tool[:id]).to eq("functions")
          expect(functions_tool[:name]).to eq("Functions")
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          tools = config.tools_for_api(:unknown_provider, :chat_completions)
          expect(tools).to eq([])
        end
      end

      context "with unknown API" do
        it "returns empty array for known provider but unknown API" do
          tools = config.tools_for_api(:openai, :unknown_api)
          expect(tools).to eq([])
        end
      end

      context "with nil arguments" do
        it "returns empty array when provider is nil" do
          tools = config.tools_for_api(nil, :chat_completions)
          expect(tools).to eq([])
        end

        it "returns empty array when API is nil" do
          tools = config.tools_for_api(:openai, nil)
          expect(tools).to eq([])
        end

        it "returns empty array when both are nil" do
          tools = config.tools_for_api(nil, nil)
          expect(tools).to eq([])
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
  end
end
