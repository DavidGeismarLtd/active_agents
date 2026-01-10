# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::EvaluatorRegistry do
  # Reset registry before each test to ensure clean state
  before do
    described_class.reset!
  end

  describe ".all" do
    it "returns all registered evaluators" do
      evaluators = described_class.all

      expect(evaluators).to be_a(Hash)
      expect(evaluators).to have_key(:length)
      expect(evaluators).to have_key(:keyword)
      expect(evaluators).to have_key(:format)
      expect(evaluators).to have_key(:llm_judge)
      expect(evaluators).to have_key(:exact_match)
      expect(evaluators).to have_key(:pattern_match)
    end

    it "includes metadata for each evaluator" do
      evaluator = described_class.all[:length]

      expect(evaluator).to include(
        key: :length,
        name: "Length Validator",
        description: kind_of(String),
        evaluator_class: PromptTracker::Evaluators::LengthEvaluator,
        icon: "rulers",
        default_config: kind_of(Hash)
      )
    end
  end

  describe ".for_testable" do
    it "returns only evaluators compatible with PromptVersion" do
      prompt = create(:prompt)
      version = create(:prompt_version, prompt: prompt)

      evaluators = described_class.for_testable(version)

      expect(evaluators).to be_a(Hash)
      # PromptVersion is compatible with both single-response and conversational evaluators
      expect(evaluators.keys).to include(:length, :keyword, :format, :llm_judge, :exact_match, :pattern_match)
      # Conversational evaluators are also compatible with PromptVersion (for conversational mode)
      expect(evaluators.keys).to include(:conversation_judge)
    end

    it "returns only evaluators compatible with Assistant" do
      assistant = create(:openai_assistant)

      evaluators = described_class.for_testable(assistant)

      expect(evaluators).to be_a(Hash)
      # Assistants are compatible with conversational evaluators
      expect(evaluators.keys).to include(:conversation_judge)
      # Single-response evaluators are NOT compatible with Assistants
      expect(evaluators.keys).not_to include(:length, :keyword, :format, :llm_judge, :exact_match, :pattern_match)
    end

    it "returns empty hash for incompatible testable" do
      # Create a mock testable that no evaluators are compatible with
      incompatible_testable = double("IncompatibleTestable")

      evaluators = described_class.for_testable(incompatible_testable)

      expect(evaluators).to be_a(Hash)
      expect(evaluators).to be_empty
    end
  end

  describe ".get" do
    it "returns metadata for a specific evaluator by symbol" do
      metadata = described_class.get(:length)

      expect(metadata).to be_a(Hash)
      expect(metadata[:name]).to eq("Length Validator")
    end

    it "returns metadata for a specific evaluator by string" do
      metadata = described_class.get("length")

      expect(metadata).to be_a(Hash)
      expect(metadata[:name]).to eq("Length Validator")
    end

    it "returns nil for non-existent evaluator" do
      metadata = described_class.get(:non_existent)

      expect(metadata).to be_nil
    end
  end

  describe ".exists?" do
    it "returns true for registered evaluator" do
      expect(described_class.exists?(:length)).to be true
    end

    it "returns false for non-existent evaluator" do
      expect(described_class.exists?(:non_existent)).to be false
    end

    it "works with string keys" do
      expect(described_class.exists?("length")).to be true
    end
  end

  describe ".build" do
    let(:llm_response) { create(:llm_response, response_text: "Test response text") }
    let(:config) { { min_length: 100, max_length: 1000, llm_response: llm_response } }

    it "builds an instance of the evaluator" do
      evaluator = described_class.build(:length, llm_response.response_text, config)

      expect(evaluator).to be_a(PromptTracker::Evaluators::LengthEvaluator)
    end

    it "passes config to the evaluator" do
      evaluator = described_class.build(:length, llm_response.response_text, config)

      expect(evaluator.instance_variable_get(:@config)).to include(min_length: 100, max_length: 1000)
    end

    it "passes response_text as evaluated_data" do
      evaluator = described_class.build(:length, llm_response.response_text, config)

      expect(evaluator.instance_variable_get(:@response_text)).to eq("Test response text")
    end

    it "raises ArgumentError for non-existent evaluator" do
      expect {
        described_class.build(:non_existent, llm_response.response_text, config)
      }.to raise_error(ArgumentError, /not found in registry/)
    end
  end

  describe ".register" do
    let(:custom_evaluator_class) { Class.new(PromptTracker::Evaluators::BaseEvaluator) }

    it "registers a new evaluator" do
      described_class.register(
        key: :custom_eval,
        name: "Custom Evaluator",
        description: "A custom evaluator",
        evaluator_class: custom_evaluator_class,
        icon: "gear"
      )

      expect(described_class.exists?(:custom_eval)).to be true
      expect(described_class.get(:custom_eval)[:name]).to eq("Custom Evaluator")
    end

    it "uses default values for optional parameters" do
      described_class.register(
        key: :simple_eval,
        name: "Simple",
        description: "Simple evaluator",
        evaluator_class: custom_evaluator_class,
        icon: "gear"
      )

      metadata = described_class.get(:simple_eval)
      expect(metadata[:icon]).to eq("gear")
      expect(metadata[:default_config]).to eq({})
      expect(metadata[:form_template]).to be_nil
    end

    it "allows custom icon and default config" do
      described_class.register(
        key: :advanced_eval,
        name: "Advanced",
        description: "Advanced evaluator",
        evaluator_class: custom_evaluator_class,
        icon: "star",
        default_config: { threshold: 75 }
      )

      metadata = described_class.get(:advanced_eval)
      expect(metadata[:icon]).to eq("star")
      expect(metadata[:default_config][:threshold]).to eq(75)
    end
  end

  describe ".unregister" do
    it "removes an evaluator from the registry" do
      expect(described_class.exists?(:length)).to be true

      described_class.unregister(:length)

      expect(described_class.exists?(:length)).to be false
    end

    it "works with string keys" do
      described_class.unregister("keyword")

      expect(described_class.exists?(:keyword)).to be false
    end
  end

  describe ".reset!" do
    it "clears and reinitializes the registry" do
      # Add a custom evaluator
      custom_class = Class.new(PromptTracker::Evaluators::BaseEvaluator)
      described_class.register(
        key: :temp_eval,
        name: "Temp",
        description: "Temporary",
        evaluator_class: custom_class,
        icon: "gear"
      )

      expect(described_class.exists?(:temp_eval)).to be true

      # Reset should remove custom evaluator but keep built-ins
      described_class.reset!

      expect(described_class.exists?(:temp_eval)).to be false
      expect(described_class.exists?(:length)).to be true
    end
  end

  describe ".by_category" do
    it "returns single_response evaluators" do
      evaluators = described_class.by_category(:single_response)

      expect(evaluators).to be_a(Hash)
      expect(evaluators.keys).to include(:length, :keyword, :format)
    end

    it "returns conversational evaluators" do
      evaluators = described_class.by_category(:conversational)

      expect(evaluators).to be_a(Hash)
      expect(evaluators.keys).to include(:conversation_judge)
    end
  end

  describe ".single_response_evaluators" do
    it "returns evaluators for single-response evaluation" do
      evaluators = described_class.single_response_evaluators

      expect(evaluators.keys).to include(:length, :keyword, :format, :llm_judge)
      expect(evaluators.keys).not_to include(:conversation_judge)
    end
  end

  describe ".conversational_evaluators" do
    it "returns evaluators for conversational evaluation" do
      evaluators = described_class.conversational_evaluators

      expect(evaluators.keys).to include(:conversation_judge)
      expect(evaluators.keys).not_to include(:length, :keyword)
    end
  end

  describe ".for_api" do
    it "returns evaluators compatible with OpenAI Chat Completion" do
      evaluators = described_class.for_api(PromptTracker::ApiTypes::OPENAI_CHAT_COMPLETION)

      expect(evaluators).to be_a(Hash)
      expect(evaluators.keys).to include(:length, :keyword)
    end

    it "returns evaluators compatible with OpenAI Assistants API" do
      evaluators = described_class.for_api(PromptTracker::ApiTypes::OPENAI_ASSISTANTS_API)

      expect(evaluators).to be_a(Hash)
      expect(evaluators.keys).to include(:conversation_judge)
    end
  end

  describe ".normalizer_for" do
    it "returns ChatCompletionNormalizer for OPENAI_CHAT_COMPLETION" do
      normalizer = described_class.normalizer_for(PromptTracker::ApiTypes::OPENAI_CHAT_COMPLETION)

      expect(normalizer).to be_a(PromptTracker::Evaluators::Normalizers::ChatCompletionNormalizer)
    end

    it "returns ResponseApiNormalizer for OPENAI_RESPONSE_API" do
      normalizer = described_class.normalizer_for(PromptTracker::ApiTypes::OPENAI_RESPONSE_API)

      expect(normalizer).to be_a(PromptTracker::Evaluators::Normalizers::ResponseApiNormalizer)
    end

    it "returns AssistantsApiNormalizer for OPENAI_ASSISTANTS_API" do
      normalizer = described_class.normalizer_for(PromptTracker::ApiTypes::OPENAI_ASSISTANTS_API)

      expect(normalizer).to be_a(PromptTracker::Evaluators::Normalizers::AssistantsApiNormalizer)
    end

    it "returns AnthropicNormalizer for ANTHROPIC_MESSAGES" do
      normalizer = described_class.normalizer_for(PromptTracker::ApiTypes::ANTHROPIC_MESSAGES)

      expect(normalizer).to be_a(PromptTracker::Evaluators::Normalizers::AnthropicNormalizer)
    end

    it "raises ArgumentError for unknown API type" do
      expect { described_class.normalizer_for(:unknown_api) }.to raise_error(ArgumentError)
    end
  end
end
