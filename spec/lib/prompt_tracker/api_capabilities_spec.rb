# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApiCapabilities do
    describe ".tools_for" do
      context "with OpenAI provider" do
        it "returns functions for chat_completions API" do
          expect(described_class.tools_for(:openai, :chat_completions)).to eq([ :functions ])
        end

        it "returns all tools for responses API" do
          expect(described_class.tools_for(:openai, :responses)).to eq(
            [ :web_search, :file_search, :code_interpreter, :functions ]
          )
        end

        it "returns builtin tools and functions for assistants API" do
          expect(described_class.tools_for(:openai, :assistants)).to eq(
            [ :code_interpreter, :file_search, :functions ]
          )
        end
      end

      context "with Anthropic provider" do
        it "returns functions for messages API" do
          expect(described_class.tools_for(:anthropic, :messages)).to eq([ :functions ])
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          expect(described_class.tools_for(:unknown_provider, :chat_completions)).to eq([])
        end
      end

      context "with unknown API" do
        it "returns empty array for known provider but unknown API" do
          expect(described_class.tools_for(:openai, :unknown_api)).to eq([])
        end
      end

      context "with string arguments" do
        it "converts strings to symbols for provider" do
          expect(described_class.tools_for("openai", :chat_completions)).to eq([ :functions ])
        end

        it "converts strings to symbols for API" do
          expect(described_class.tools_for(:openai, "chat_completions")).to eq([ :functions ])
        end

        it "converts both provider and API strings to symbols" do
          expect(described_class.tools_for("openai", "responses")).to eq(
            [ :web_search, :file_search, :code_interpreter, :functions ]
          )
        end
      end

      context "with nil arguments" do
        it "returns empty array when provider is nil" do
          expect(described_class.tools_for(nil, :chat_completions)).to eq([])
        end

        it "returns empty array when API is nil" do
          expect(described_class.tools_for(:openai, nil)).to eq([])
        end

        it "returns empty array when both are nil" do
          expect(described_class.tools_for(nil, nil)).to eq([])
        end
      end

      context "with empty string arguments" do
        it "returns empty array when provider is empty string" do
          expect(described_class.tools_for("", :chat_completions)).to eq([])
        end

        it "returns empty array when API is empty string" do
          expect(described_class.tools_for(:openai, "")).to eq([])
        end

        it "returns empty array when both are empty strings" do
          expect(described_class.tools_for("", "")).to eq([])
        end
      end
    end

    describe ".supports_tools?" do
      it "returns true when API has tools" do
        expect(described_class.supports_tools?(:openai, :chat_completions)).to be true
      end

      it "returns false when API has no tools" do
        expect(described_class.supports_tools?(:unknown_provider, :unknown_api)).to be false
      end

      it "returns false when provider is nil" do
        expect(described_class.supports_tools?(nil, :chat_completions)).to be false
      end

      it "returns false when API is nil" do
        expect(described_class.supports_tools?(:openai, nil)).to be false
      end
    end

    describe ".supports_feature?" do
      it "returns true for supported features" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :streaming)).to be true
        expect(described_class.supports_feature?(:openai, :responses, :builtin_tools)).to be true
      end

      it "returns false for unsupported features" do
        expect(described_class.supports_feature?(:openai, :chat_completions, :builtin_tools)).to be false
      end

      it "returns false for unknown provider/API" do
        expect(described_class.supports_feature?(:unknown, :unknown, :streaming)).to be false
      end

      it "returns false when provider is nil" do
        expect(described_class.supports_feature?(nil, :chat_completions, :streaming)).to be false
      end

      it "returns false when API is nil" do
        expect(described_class.supports_feature?(:openai, nil, :streaming)).to be false
      end

      it "returns false when feature is nil" do
        expect(described_class.supports_feature?(:openai, :chat_completions, nil)).to be false
      end

      it "converts string arguments to symbols" do
        expect(described_class.supports_feature?("openai", "chat_completions", "streaming")).to be true
      end
    end

    describe ".features_for" do
      it "returns all features for an API" do
        features = described_class.features_for(:openai, :chat_completions)
        expect(features).to eq([ :streaming, :vision, :structured_output, :function_calling ])
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
        features = described_class.features_for("openai", "chat_completions")
        expect(features).to eq([ :streaming, :vision, :structured_output, :function_calling ])
      end
    end

    describe "CAPABILITIES constant" do
      it "is frozen" do
        expect(described_class::CAPABILITIES).to be_frozen
      end

      it "has expected structure for OpenAI" do
        expect(described_class::CAPABILITIES[:openai]).to be_a(Hash)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:tools)
        expect(described_class::CAPABILITIES[:openai][:chat_completions]).to have_key(:features)
      end

      it "has expected structure for Anthropic" do
        expect(described_class::CAPABILITIES[:anthropic]).to be_a(Hash)
        expect(described_class::CAPABILITIES[:anthropic][:messages]).to have_key(:tools)
        expect(described_class::CAPABILITIES[:anthropic][:messages]).to have_key(:features)
      end

      it "contains only symbols as keys" do
        described_class::CAPABILITIES.each do |provider_key, provider_config|
          expect(provider_key).to be_a(Symbol)
          provider_config.each do |api_key, api_config|
            expect(api_key).to be_a(Symbol)
            expect(api_config[:tools]).to all(be_a(Symbol))
            expect(api_config[:features]).to all(be_a(Symbol))
          end
        end
      end
    end
  end
end
