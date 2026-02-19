# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApiCapabilities do
    describe ".builtin_tools_for" do
      context "with OpenAI provider" do
        it "returns empty array for chat_completions API (no builtin tools)" do
          expect(described_class.builtin_tools_for(:openai, :chat_completions)).to eq([])
        end

        it "returns builtin tools for responses API (no functions - that's a model capability)" do
          expect(described_class.builtin_tools_for(:openai, :responses)).to eq(
            [ :web_search, :file_search, :code_interpreter ]
          )
        end

        it "returns builtin tools for assistants API (no functions)" do
          expect(described_class.builtin_tools_for(:openai, :assistants)).to eq(
            [ :code_interpreter, :file_search ]
          )
        end
      end

      context "with Anthropic provider" do
        it "returns empty array for messages API (no builtin tools)" do
          expect(described_class.builtin_tools_for(:anthropic, :messages)).to eq([])
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          expect(described_class.builtin_tools_for(:unknown_provider, :chat_completions)).to eq([])
        end
      end

      context "with unknown API" do
        it "returns empty array for known provider but unknown API" do
          expect(described_class.builtin_tools_for(:openai, :unknown_api)).to eq([])
        end
      end

      context "with string arguments" do
        it "converts strings to symbols for provider" do
          expect(described_class.builtin_tools_for("openai", :responses)).to eq(
            [ :web_search, :file_search, :code_interpreter ]
          )
        end

        it "converts strings to symbols for API" do
          expect(described_class.builtin_tools_for(:openai, "responses")).to eq(
            [ :web_search, :file_search, :code_interpreter ]
          )
        end

        it "converts both provider and API strings to symbols" do
          expect(described_class.builtin_tools_for("openai", "responses")).to eq(
            [ :web_search, :file_search, :code_interpreter ]
          )
        end
      end

      context "with nil arguments" do
        it "returns empty array when provider is nil" do
          expect(described_class.builtin_tools_for(nil, :chat_completions)).to eq([])
        end

        it "returns empty array when API is nil" do
          expect(described_class.builtin_tools_for(:openai, nil)).to eq([])
        end

        it "returns empty array when both are nil" do
          expect(described_class.builtin_tools_for(nil, nil)).to eq([])
        end
      end

      context "with empty string arguments" do
        it "returns empty array when provider is empty string" do
          expect(described_class.builtin_tools_for("", :chat_completions)).to eq([])
        end

        it "returns empty array when API is empty string" do
          expect(described_class.builtin_tools_for(:openai, "")).to eq([])
        end

        it "returns empty array when both are empty strings" do
          expect(described_class.builtin_tools_for("", "")).to eq([])
        end
      end
    end

    describe ".supports_feature?" do
      it "returns true for supported features" do
        expect(described_class.supports_feature?(:openai, :assistants, :remote_entity_linked)).to be true
      end

      it "returns false for unsupported features" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :remote_entity_linked)).to be false
        expect(described_class.supports_feature?(:openai, :assistants, :streaming)).to be false
      end

      it "returns false for unknown provider/API" do
        expect(described_class.supports_feature?(:unknown, :unknown, :remote_entity_linked)).to be false
      end

      it "returns false when provider is nil" do
        expect(described_class.supports_feature?(nil, :chat_completions, :remote_entity_linked)).to be false
      end

      it "returns false when API is nil" do
        expect(described_class.supports_feature?(:openai, nil, :remote_entity_linked)).to be false
      end

      it "returns false when feature is nil" do
        expect(described_class.supports_feature?(:openai, :chat_completions, nil)).to be false
      end

      it "converts string arguments to symbols" do
        expect(described_class.supports_feature?("openai", "assistants", "remote_entity_linked")).to be true
      end
    end

    describe ".features_for" do
      it "returns all features for an API" do
        features = described_class.features_for(:openai, :assistants)
        expect(features).to eq([ :remote_entity_linked ])
      end

      it "returns empty array for APIs with no features" do
        features = described_class.features_for(:openai, :chat_completions)
        expect(features).to eq([])
      end

      it "returns empty array for unknown provider/API" do
        expect(described_class.features_for(:unknown, :unknown)).to eq([])
      end

      it "returns empty array when provider is nil" do
        expect(described_class.features_for(nil, :chat_completions)).to eq([])
      end

      it "returns empty array when API is nil" do
        expect(described_class.features_for(:openai, nil)).to eq([])
      end

      it "returns empty array when provider is empty string" do
        expect(described_class.features_for("", :chat_completions)).to eq([])
      end

      it "returns empty array when API is empty string" do
        expect(described_class.features_for(:openai, "")).to eq([])
      end

      it "converts string arguments to symbols" do
        features = described_class.features_for("openai", "assistants")
        expect(features).to eq([ :remote_entity_linked ])
      end
    end

    describe "remote_entity_linked feature" do
      it "returns true for OpenAI Assistants API" do
        expect(described_class.supports_feature?(:openai, :assistants, :remote_entity_linked)).to be true
      end

      it "returns false for template-based APIs" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :remote_entity_linked)).to be false
        expect(described_class.supports_feature?(:openai, :responses, :remote_entity_linked)).to be false
        expect(described_class.supports_feature?(:anthropic, :messages, :remote_entity_linked)).to be false
      end
    end

    describe "remote_entity_linked feature" do
      it "returns true for OpenAI Assistants API" do
        expect(described_class.supports_feature?(:openai, :assistants, :remote_entity_linked)).to be true
      end

      it "returns false for template-based APIs" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :remote_entity_linked)).to be false
        expect(described_class.supports_feature?(:openai, :responses, :remote_entity_linked)).to be false
        expect(described_class.supports_feature?(:anthropic, :messages, :remote_entity_linked)).to be false
      end
    end

    describe ".playground_ui_for" do
      it "returns UI panels for template-based APIs" do
        ui_panels = described_class.playground_ui_for(:openai, :chat_completions)
        expect(ui_panels).to include(:system_prompt, :user_prompt_template, :variables, :preview, :conversation, :tools, :model_config)
      end

      it "returns UI panels for remote entity APIs" do
        ui_panels = described_class.playground_ui_for(:openai, :assistants)
        expect(ui_panels).to include(:system_prompt, :conversation, :tools, :model_config)
        expect(ui_panels).not_to include(:user_prompt_template, :variables, :preview)
      end

      it "returns DEFAULT_PLAYGROUND_UI for unknown provider/API" do
        expect(described_class.playground_ui_for(:unknown, :unknown)).to eq(described_class::DEFAULT_PLAYGROUND_UI)
      end

      it "returns DEFAULT_PLAYGROUND_UI when provider is nil" do
        expect(described_class.playground_ui_for(nil, :chat_completions)).to eq(described_class::DEFAULT_PLAYGROUND_UI)
      end

      it "returns DEFAULT_PLAYGROUND_UI when API is nil" do
        expect(described_class.playground_ui_for(:openai, nil)).to eq(described_class::DEFAULT_PLAYGROUND_UI)
      end

      it "returns DEFAULT_PLAYGROUND_UI when provider is empty string" do
        expect(described_class.playground_ui_for("", :chat_completions)).to eq(described_class::DEFAULT_PLAYGROUND_UI)
      end

      it "returns DEFAULT_PLAYGROUND_UI when API is empty string" do
        expect(described_class.playground_ui_for(:openai, "")).to eq(described_class::DEFAULT_PLAYGROUND_UI)
      end

      it "converts string arguments to symbols" do
        ui_panels = described_class.playground_ui_for("openai", "chat_completions")
        expect(ui_panels).to include(:system_prompt, :user_prompt_template)
      end
    end

    describe "DEFAULT_PLAYGROUND_UI constant" do
      it "includes all standard UI panels" do
        expect(described_class::DEFAULT_PLAYGROUND_UI).to include(
          :system_prompt, :user_prompt_template, :variables,
          :preview, :conversation, :tools, :model_config
        )
      end

      it "is frozen" do
        expect(described_class::DEFAULT_PLAYGROUND_UI).to be_frozen
      end
    end

    describe "CAPABILITIES constant" do
      it "is frozen" do
        expect(described_class::CAPABILITIES).to be_frozen
      end

      it "has expected structure for OpenAI" do
        expect(described_class::CAPABILITIES[:openai]).to be_a(Hash)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:builtin_tools)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:features)
      end

      it "has expected structure for Anthropic" do
        expect(described_class::CAPABILITIES[:anthropic]).to be_a(Hash)
        expect(described_class::CAPABILITIES[:anthropic][:messages]).to have_key(:builtin_tools)
        expect(described_class::CAPABILITIES[:anthropic][:messages]).to have_key(:features)
      end

      it "contains only symbols as keys" do
        described_class::CAPABILITIES.each do |provider_key, provider_config|
          expect(provider_key).to be_a(Symbol)
          provider_config.each do |api_key, api_config|
            expect(api_key).to be_a(Symbol)
            expect(api_config[:builtin_tools]).to all(be_a(Symbol))
            expect(api_config[:features]).to all(be_a(Symbol))
          end
        end
      end
    end

    describe ".show_ui_panel?" do
      it "returns true when panel is in playground_ui array" do
        expect(described_class.show_ui_panel?(:openai, :chat_completions, :system_prompt)).to be true
        expect(described_class.show_ui_panel?(:openai, :chat_completions, :variables)).to be true
        expect(described_class.show_ui_panel?(:openai, :assistants, :conversation)).to be true
      end

      it "returns false when panel is not in playground_ui array" do
        expect(described_class.show_ui_panel?(:openai, :assistants, :variables)).to be false
        expect(described_class.show_ui_panel?(:openai, :assistants, :user_prompt_template)).to be false
        expect(described_class.show_ui_panel?(:openai, :assistants, :preview)).to be false
      end

      it "returns true for unknown provider/API (uses DEFAULT_PLAYGROUND_UI)" do
        expect(described_class.show_ui_panel?(:unknown, :unknown, :system_prompt)).to be true
        expect(described_class.show_ui_panel?(:unknown, :unknown, :variables)).to be true
      end

      it "returns true when provider is nil (uses DEFAULT_PLAYGROUND_UI)" do
        expect(described_class.show_ui_panel?(nil, :chat_completions, :system_prompt)).to be true
      end

      it "returns true when API is nil (uses DEFAULT_PLAYGROUND_UI)" do
        expect(described_class.show_ui_panel?(:openai, nil, :system_prompt)).to be true
      end

      it "returns false when panel is nil" do
        expect(described_class.show_ui_panel?(:openai, :chat_completions, nil)).to be false
      end

      it "converts string arguments to symbols" do
        expect(described_class.show_ui_panel?("openai", "chat_completions", "variables")).to be true
      end
    end

    describe ".to_h" do
      it "returns the complete capabilities matrix" do
        result = described_class.to_h
        expect(result).to be_a(Hash)
        expect(result).to have_key(:openai)
        expect(result).to have_key(:anthropic)
      end

      it "includes all provider configurations" do
        result = described_class.to_h
        expect(result[:openai]).to have_key(:chat_completions)
        expect(result[:openai]).to have_key(:responses)
        expect(result[:openai]).to have_key(:assistants)
        expect(result[:anthropic]).to have_key(:messages)
      end

      it "includes builtin_tools, features, and playground_ui for each API" do
        result = described_class.to_h
        chat_config = result[:openai][:chat_completions]
        expect(chat_config).to have_key(:builtin_tools)
        expect(chat_config).to have_key(:features)
        expect(chat_config).to have_key(:playground_ui)
      end
    end
  end
end
