# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::AssistantChatbot::Functions::ListRecentlyReleasedModels do
  let(:context) { {} }
  let(:arguments) { { per_provider_limit: 2 } }

  subject(:function) { described_class.new(arguments, context) }

  before do
    allow(PromptTracker.configuration).to receive(:enabled_providers).and_return([ :openai, :anthropic ])
    allow(PromptTracker.configuration).to receive(:default_provider_for).with(:playground).and_return(:openai)
    allow(PromptTracker.configuration).to receive(:default_api_for).with(:playground).and_return(:chat_completions)
    allow(PromptTracker.configuration).to receive(:default_model_for).with(:playground).and_return("gpt-4o")

    allow(PromptTracker::RubyLlmModelAdapter).to receive(:raw_models_for).with(:openai).and_return([
      { id: "gpt-4o", name: "GPT-4o" },
      { id: "gpt-4o-2024-08-06", name: "GPT-4o (2024-08-06)" },
      { id: "gpt-4.1-2025-02-15", name: "GPT-4.1 (2025-02-15)" },
      { id: "gpt-4.1-mini-2025-02-20", name: "GPT-4.1 mini (2025-02-20)" }
    ])

    allow(PromptTracker::RubyLlmModelAdapter).to receive(:raw_models_for).with(:anthropic).and_return([
      { id: "claude-3-7-sonnet-20250301", name: "Claude 3.7 Sonnet" },
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet" }
    ])
  end

  describe "#call" do
    it "returns default model first and the most recently released models after" do
      result = function.call

      expect(result.success?).to be true
      expect(result.message).to include("(default)")
      expect(result.message).to include("gpt-4o")
      expect(result.message).to include("released 2025-03-01")
      expect(result.message).to include("released 2024-10-22")

      lines = result.message.split("\n").select { |l| l.match?(/^\d+\./) }
      expect(lines.length).to eq(5)
      expect(lines.first).to include("gpt-4o")
    end
  end
end
