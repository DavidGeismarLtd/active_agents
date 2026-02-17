# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ApiTypes do
  describe ".from_config" do
    context "with specialized APIs" do
      it "converts openai responses" do
        expect(described_class.from_config(:openai, :responses)).to eq(:openai_responses)
      end

      it "converts openai assistants" do
        expect(described_class.from_config(:openai, :assistants)).to eq(:openai_assistants)
      end

      it "handles string inputs for specialized APIs" do
        expect(described_class.from_config("openai", "responses")).to eq(:openai_responses)
        expect(described_class.from_config("openai", "assistants")).to eq(:openai_assistants)
      end
    end

    context "with RubyLLM-compatible APIs" do
      it "returns ruby_llm for openai chat_completions" do
        expect(described_class.from_config(:openai, :chat_completions)).to eq(:ruby_llm)
      end

      it "returns ruby_llm for anthropic messages" do
        expect(described_class.from_config(:anthropic, :messages)).to eq(:ruby_llm)
      end

      it "returns ruby_llm for google gemini" do
        expect(described_class.from_config(:google, :gemini)).to eq(:ruby_llm)
      end

      it "returns ruby_llm for unknown combinations" do
        expect(described_class.from_config(:unknown, :api)).to eq(:ruby_llm)
      end

      it "handles string inputs" do
        expect(described_class.from_config("openai", "chat_completions")).to eq(:ruby_llm)
        expect(described_class.from_config("anthropic", "messages")).to eq(:ruby_llm)
      end
    end
  end

  describe ".requires_direct_sdk?" do
    it "returns true for openai_responses" do
      expect(described_class.requires_direct_sdk?(:openai_responses)).to be true
    end

    it "returns true for openai_assistants" do
      expect(described_class.requires_direct_sdk?(:openai_assistants)).to be true
    end

    it "returns false for ruby_llm" do
      expect(described_class.requires_direct_sdk?(:ruby_llm)).to be false
    end
  end

  describe ".all" do
    it "returns all API types" do
      expect(described_class.all).to contain_exactly(
        :openai_responses,
        :openai_assistants,
        :ruby_llm
      )
    end
  end

  describe ".valid?" do
    it "returns true for valid API types" do
      expect(described_class.valid?(:openai_responses)).to be true
      expect(described_class.valid?(:openai_assistants)).to be true
      expect(described_class.valid?(:ruby_llm)).to be true
    end

    it "returns false for invalid API types" do
      expect(described_class.valid?(:invalid_api)).to be false
      expect(described_class.valid?(nil)).to be false
    end

    it "handles string inputs" do
      expect(described_class.valid?("openai_responses")).to be true
      expect(described_class.valid?("ruby_llm")).to be true
    end
  end

  describe ".display_name" do
    it "returns human-readable names" do
      expect(described_class.display_name(:openai_responses)).to eq("OpenAI Responses")
      expect(described_class.display_name(:openai_assistants)).to eq("OpenAI Assistants")
      expect(described_class.display_name(:ruby_llm)).to eq("RubyLLM (Universal)")
    end

    it "titleizes unknown API types" do
      expect(described_class.display_name(:unknown_api)).to eq("Unknown Api")
    end
  end
end
