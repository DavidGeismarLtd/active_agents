# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe ApplicationHelper, type: :helper do
    describe "#provider_api_key_present?" do
      context "when OpenAI API key is present" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test-key")
        end

        it "returns true for openai" do
          expect(helper.provider_api_key_present?("openai")).to be true
        end
      end

      context "when OpenAI API key is not present" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
        end

        it "returns false for openai" do
          expect(helper.provider_api_key_present?("openai")).to be false
        end
      end

      context "when Anthropic API key is present" do
        before do
          allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
        end

        it "returns true for anthropic" do
          expect(helper.provider_api_key_present?("anthropic")).to be true
        end
      end

      context "when Google API key is present" do
        before do
          allow(ENV).to receive(:[]).with("GOOGLE_API_KEY").and_return("google-test-key")
        end

        it "returns true for google" do
          expect(helper.provider_api_key_present?("google")).to be true
        end
      end

      context "when Azure API key is present" do
        before do
          allow(ENV).to receive(:[]).with("AZURE_OPENAI_API_KEY").and_return("azure-test-key")
        end

        it "returns true for azure" do
          expect(helper.provider_api_key_present?("azure")).to be true
        end
      end

      context "when provider is unknown" do
        it "returns false" do
          expect(helper.provider_api_key_present?("unknown_provider")).to be false
        end
      end

      context "when API key is empty string" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("")
        end

        it "returns false for openai" do
          expect(helper.provider_api_key_present?("openai")).to be false
        end
      end
    end

    describe "#available_providers" do
      context "when no API keys are configured" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("GOOGLE_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("AZURE_OPENAI_API_KEY").and_return(nil)
        end

        it "returns empty array" do
          expect(helper.available_providers).to eq([])
        end
      end

      context "when only OpenAI API key is configured" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
          allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("GOOGLE_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("AZURE_OPENAI_API_KEY").and_return(nil)
        end

        it "returns only openai" do
          expect(helper.available_providers).to eq([ "openai" ])
        end
      end

      context "when multiple API keys are configured" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
          allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
          allow(ENV).to receive(:[]).with("GOOGLE_API_KEY").and_return(nil)
          allow(ENV).to receive(:[]).with("AZURE_OPENAI_API_KEY").and_return("azure-test")
        end

        it "returns all configured providers" do
          expect(helper.available_providers).to contain_exactly("openai", "anthropic", "azure")
        end
      end

      context "when all API keys are configured" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
          allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
          allow(ENV).to receive(:[]).with("GOOGLE_API_KEY").and_return("google-test")
          allow(ENV).to receive(:[]).with("AZURE_OPENAI_API_KEY").and_return("azure-test")
        end

        it "returns all providers" do
          expect(helper.available_providers).to contain_exactly("openai", "anthropic", "google", "azure")
        end
      end
    end

    describe "#models_for_provider" do
      context "when provider is openai" do
        it "returns OpenAI models" do
          models = helper.models_for_provider("openai")
          expect(models).to eq({
            "gpt-4" => "GPT-4",
            "gpt-4-turbo" => "GPT-4 Turbo",
            "gpt-3.5-turbo" => "GPT-3.5 Turbo"
          })
        end
      end

      context "when provider is anthropic" do
        it "returns Anthropic models" do
          models = helper.models_for_provider("anthropic")
          expect(models).to eq({
            "claude-3-opus" => "Claude 3 Opus",
            "claude-3-sonnet" => "Claude 3 Sonnet",
            "claude-3-haiku" => "Claude 3 Haiku"
          })
        end
      end

      context "when provider is google" do
        it "returns Google models" do
          models = helper.models_for_provider("google")
          expect(models).to eq({
            "gemini-pro" => "Gemini Pro",
            "gemini-ultra" => "Gemini Ultra"
          })
        end
      end

      context "when provider is azure" do
        it "returns Azure OpenAI models" do
          models = helper.models_for_provider("azure")
          expect(models).to eq({
            "gpt-4" => "GPT-4",
            "gpt-35-turbo" => "GPT-3.5 Turbo"
          })
        end
      end

      context "when provider is unknown" do
        it "returns empty hash" do
          models = helper.models_for_provider("unknown_provider")
          expect(models).to eq({})
        end
      end

      context "when provider is uppercase" do
        it "handles case insensitively" do
          models = helper.models_for_provider("OPENAI")
          expect(models).to eq({
            "gpt-4" => "GPT-4",
            "gpt-4-turbo" => "GPT-4 Turbo",
            "gpt-3.5-turbo" => "GPT-3.5 Turbo"
          })
        end
      end
    end
  end
end
