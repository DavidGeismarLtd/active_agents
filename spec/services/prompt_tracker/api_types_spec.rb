# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ApiTypes do
  describe ".from_config" do
    it "converts openai chat_completions" do
      expect(described_class.from_config(:openai, :chat_completions)).to eq(:openai_chat_completions)
    end

    it "converts openai responses" do
      expect(described_class.from_config(:openai, :responses)).to eq(:openai_responses)
    end

    it "converts openai assistants" do
      expect(described_class.from_config(:openai, :assistants)).to eq(:openai_assistants)
    end

    it "converts anthropic messages" do
      expect(described_class.from_config(:anthropic, :messages)).to eq(:anthropic_messages)
    end

    it "converts google gemini" do
      expect(described_class.from_config(:google, :gemini)).to eq(:google_gemini)
    end

    it "returns nil for unknown combinations" do
      expect(described_class.from_config(:unknown, :api)).to be_nil
    end

    it "handles string inputs" do
      expect(described_class.from_config("openai", "chat_completions")).to eq(:openai_chat_completions)
    end
  end

  describe ".to_config" do
    it "converts openai_chat_completions to config format" do
      result = described_class.to_config(:openai_chat_completions)
      expect(result).to eq({ provider: :openai, api: :chat_completions })
    end

    it "converts openai_responses to config format" do
      result = described_class.to_config(:openai_responses)
      expect(result).to eq({ provider: :openai, api: :responses })
    end

    it "converts openai_assistants to config format" do
      result = described_class.to_config(:openai_assistants)
      expect(result).to eq({ provider: :openai, api: :assistants })
    end

    it "converts anthropic_messages to config format" do
      result = described_class.to_config(:anthropic_messages)
      expect(result).to eq({ provider: :anthropic, api: :messages })
    end

    it "returns nil for unknown API types" do
      expect(described_class.to_config(:unknown_api)).to be_nil
    end
  end

  describe ".all" do
    it "returns all API types" do
      expect(described_class.all).to contain_exactly(
        :openai_chat_completions,
        :openai_responses,
        :openai_assistants,
        :anthropic_messages,
        :google_gemini
      )
    end
  end

  describe ".valid?" do
    it "returns true for valid API types" do
      expect(described_class.valid?(:openai_chat_completions)).to be true
      expect(described_class.valid?(:openai_responses)).to be true
      expect(described_class.valid?(:openai_assistants)).to be true
      expect(described_class.valid?(:anthropic_messages)).to be true
      expect(described_class.valid?(:google_gemini)).to be true
    end

    it "returns false for invalid API types" do
      expect(described_class.valid?(:invalid_api)).to be false
      expect(described_class.valid?(nil)).to be false
    end

    it "handles string inputs" do
      expect(described_class.valid?("openai_chat_completions")).to be true
    end
  end

  describe ".display_name" do
    it "returns human-readable names" do
      expect(described_class.display_name(:openai_chat_completions)).to eq("OpenAI Chat Completions")
      expect(described_class.display_name(:openai_responses)).to eq("OpenAI Responses")
      expect(described_class.display_name(:openai_assistants)).to eq("OpenAI Assistants")
      expect(described_class.display_name(:anthropic_messages)).to eq("Anthropic Messages")
      expect(described_class.display_name(:google_gemini)).to eq("Google Gemini")
    end

    it "titleizes unknown API types" do
      expect(described_class.display_name(:unknown_api)).to eq("Unknown Api")
    end
  end
end
