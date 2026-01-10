# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::ApiTypes do
  describe "constants" do
    it "defines OPENAI_CHAT_COMPLETION" do
      expect(described_class::OPENAI_CHAT_COMPLETION).to eq(:openai_chat_completion)
    end

    it "defines OPENAI_RESPONSE_API" do
      expect(described_class::OPENAI_RESPONSE_API).to eq(:openai_response_api)
    end

    it "defines OPENAI_ASSISTANTS_API" do
      expect(described_class::OPENAI_ASSISTANTS_API).to eq(:openai_assistants_api)
    end

    it "defines ANTHROPIC_MESSAGES" do
      expect(described_class::ANTHROPIC_MESSAGES).to eq(:anthropic_messages)
    end
  end

  describe ".all" do
    it "returns all API types" do
      expect(described_class.all).to contain_exactly(
        :openai_chat_completion,
        :openai_response_api,
        :openai_assistants_api,
        :anthropic_messages
      )
    end
  end

  describe ".valid?" do
    it "returns true for valid API types" do
      expect(described_class.valid?(:openai_chat_completion)).to be true
      expect(described_class.valid?(:openai_response_api)).to be true
      expect(described_class.valid?(:openai_assistants_api)).to be true
      expect(described_class.valid?(:anthropic_messages)).to be true
    end

    it "returns false for invalid API types" do
      expect(described_class.valid?(:invalid_api)).to be false
      expect(described_class.valid?(nil)).to be false
    end
  end

  describe ".single_response_apis" do
    it "returns APIs that support single-response evaluation" do
      expect(described_class.single_response_apis).to contain_exactly(
        :openai_chat_completion,
        :openai_response_api,
        :anthropic_messages
      )
    end
  end

  describe ".conversational_apis" do
    it "returns APIs that support conversational evaluation" do
      expect(described_class.conversational_apis).to contain_exactly(
        :openai_response_api,
        :openai_assistants_api
      )
    end
  end
end
