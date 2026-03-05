# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe RubyLlmModelAdapter do
    describe ".models_for" do
      context "with OpenAI provider" do
        let(:openai_models) { described_class.models_for(:openai) }

        it "returns an array of model hashes" do
          expect(openai_models).to be_an(Array)
          expect(openai_models).not_to be_empty
        end

        it "filters out chatgpt-* convenience aliases" do
          chatgpt_aliases = openai_models.select { |m| m[:id].start_with?("chatgpt-") }
          expect(chatgpt_aliases).to be_empty
        end

        it "includes real gpt-* model IDs" do
          gpt_models = openai_models.select { |m| m[:id].start_with?("gpt-") }
          expect(gpt_models).not_to be_empty
        end

        it "includes expected model structure" do
          model = openai_models.first
          expect(model).to include(
            :id,
            :name,
            :category,
            :capabilities,
            :context_window,
            :max_output_tokens,
            :pricing
          )
        end
      end

      context "with Anthropic provider" do
        let(:anthropic_models) { described_class.models_for(:anthropic) }

        it "returns an array of model hashes" do
          expect(anthropic_models).to be_an(Array)
          expect(anthropic_models).not_to be_empty
        end

        it "filters out *-latest convenience aliases" do
          latest_aliases = anthropic_models.select { |m| m[:id].end_with?("-latest") }
          expect(latest_aliases).to be_empty
        end

        it "includes dated model versions" do
          dated_models = anthropic_models.select { |m| m[:id].match?(/\d{8}$/) }
          expect(dated_models).not_to be_empty
        end
      end

      context "with Google provider" do
        let(:google_models) { described_class.models_for(:google) }

        it "does not filter any models (no known alias issues)" do
          # Google doesn't have known convenience alias issues
          # Just verify we get models back
          expect(google_models).to be_an(Array)
        end
      end

      context "with unknown provider" do
        it "returns empty array" do
          expect(described_class.models_for(:unknown_provider)).to eq([])
        end
      end
    end

    describe ".find_model" do
      it "finds a valid OpenAI model" do
        model = described_class.find_model("gpt-4o")
        expect(model).to be_present
        expect(model[:id]).to eq("gpt-4o")
      end

      it "finds a valid Anthropic model" do
        model = described_class.find_model("claude-3-5-haiku-20241022")
        expect(model).to be_present
        expect(model[:id]).to eq("claude-3-5-haiku-20241022")
      end

      it "returns nil for blank model_id" do
        expect(described_class.find_model("")).to be_nil
        expect(described_class.find_model(nil)).to be_nil
      end

      it "returns nil for non-existent model" do
        expect(described_class.find_model("non-existent-model-xyz")).to be_nil
      end
    end

    describe ".capabilities_for" do
      it "returns capabilities for a valid model" do
        capabilities = described_class.capabilities_for("gpt-4o")
        expect(capabilities).to be_an(Array)
        expect(capabilities).to include(:function_calling)
      end

      it "returns empty array for non-existent model" do
        expect(described_class.capabilities_for("non-existent-model")).to eq([])
      end

      it "returns empty array for nil model_id" do
        expect(described_class.capabilities_for(nil)).to eq([])
      end
    end

    describe "convenience alias filtering" do
      # Test the private method indirectly through models_for
      context "OpenAI convenience aliases" do
        it "filters chatgpt-4o-latest" do
          models = described_class.models_for(:openai)
          expect(models.map { |m| m[:id] }).not_to include("chatgpt-4o-latest")
        end

        it "filters chatgpt-4o-mini-latest" do
          models = described_class.models_for(:openai)
          expect(models.map { |m| m[:id] }).not_to include("chatgpt-4o-mini-latest")
        end

        it "keeps gpt-4o (real model ID)" do
          models = described_class.models_for(:openai)
          expect(models.map { |m| m[:id] }).to include("gpt-4o")
        end
      end

      context "Anthropic convenience aliases" do
        it "filters claude-3-5-sonnet-latest" do
          models = described_class.models_for(:anthropic)
          expect(models.map { |m| m[:id] }).not_to include("claude-3-5-sonnet-latest")
        end

        it "filters claude-3-5-haiku-latest" do
          models = described_class.models_for(:anthropic)
          expect(models.map { |m| m[:id] }).not_to include("claude-3-5-haiku-latest")
        end

        it "keeps claude-3-5-haiku-20241022 (dated version)" do
          models = described_class.models_for(:anthropic)
          expect(models.map { |m| m[:id] }).to include("claude-3-5-haiku-20241022")
        end
      end
    end
  end
end
