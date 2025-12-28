# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_evaluator_configs
#
#  config            :jsonb            not null
#  configurable_id   :bigint           not null
#  configurable_type :string           not null
#  created_at        :datetime         not null
#  enabled           :boolean          default(TRUE), not null
#  evaluator_key     :string           not null
#  id                :bigint           not null, primary key
#  updated_at        :datetime         not null
#
require "rails_helper"

RSpec.describe PromptTracker::EvaluatorConfig, type: :model do
  describe "associations" do
    it { should belong_to(:configurable) }
  end

  describe "polymorphic association" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:test) { create(:test, testable: version) }

    it "can belong to a PromptVersion" do
      config = described_class.create!(
        configurable: version,
        evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
        enabled: true
      )

      expect(config.configurable_type).to eq("PromptTracker::PromptVersion")
      expect(config.configurable).to eq(version)
    end

    it "can belong to a Test" do
      config = described_class.create!(
        configurable: test,
        evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
        enabled: true
      )

      expect(config.configurable_type).to eq("PromptTracker::Test")
      expect(config.configurable).to eq(test)
    end
  end

  describe "validations" do
    subject { build(:evaluator_config) }

    it { should validate_presence_of(:evaluator_type) }

    describe "uniqueness of evaluator_type" do
      it "validates uniqueness scoped to configurable" do
        prompt = create(:prompt)
        version = create(:prompt_version, prompt: prompt)
        create(:evaluator_config, configurable: version, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")

        duplicate = build(:evaluator_config, configurable: version, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:evaluator_type]).to include("has already been taken")
      end

      it "allows same evaluator_type for different configurables" do
        prompt = create(:prompt)
        version1 = create(:prompt_version, prompt: prompt)
        version2 = create(:prompt_version, prompt: prompt)

        create(:evaluator_config, configurable: version1, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")
        duplicate = build(:evaluator_config, configurable: version2, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")

        expect(duplicate).to be_valid
      end
    end

    describe "evaluator compatibility with testable" do
      context "when configurable is a Test" do
        it "allows PromptVersion evaluators for PromptVersion tests" do
          prompt = create(:prompt)
          version = create(:prompt_version, prompt: prompt)
          test = create(:test, testable: version)

          config = test.evaluator_configs.build(
            evaluator_type: "PromptTracker::Evaluators::LengthEvaluator"
          )

          expect(config).to be_valid
        end

        it "prevents Assistant evaluators for PromptVersion tests" do
          prompt = create(:prompt)
          version = create(:prompt_version, prompt: prompt)
          test = create(:test, testable: version)

          config = test.evaluator_configs.build(
            evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator"
          )

          expect(config).not_to be_valid
          expect(config.errors[:evaluator_type]).to include(
            match(/ConversationJudgeEvaluator is only compatible with PromptTracker::Openai::Assistant/)
          )
        end

        it "allows Assistant evaluators for Assistant tests" do
          assistant = create(:openai_assistant)
          test = create(:test, testable: assistant)

          config = test.evaluator_configs.build(
            evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator"
          )

          expect(config).to be_valid
        end

        it "prevents PromptVersion evaluators for Assistant tests" do
          assistant = create(:openai_assistant)
          test = create(:test, testable: assistant)

          config = test.evaluator_configs.build(
            evaluator_type: "PromptTracker::Evaluators::LengthEvaluator"
          )

          expect(config).not_to be_valid
          expect(config.errors[:evaluator_type]).to include(
            match(/LengthEvaluator is only compatible with PromptTracker::PromptVersion/)
          )
        end

        it "handles invalid evaluator class gracefully" do
          prompt = create(:prompt)
          version = create(:prompt_version, prompt: prompt)
          test = create(:test, testable: version)

          config = test.evaluator_configs.build(
            evaluator_type: "Invalid::EvaluatorClass"
          )

          expect(config).not_to be_valid
          expect(config.errors[:evaluator_type]).to include("is not a valid evaluator class")
        end
      end

      context "when configurable is not a Test" do
        it "skips validation for PromptVersion" do
          prompt = create(:prompt)
          version = create(:prompt_version, prompt: prompt)

          # PromptVersion doesn't have a testable, so validation should be skipped
          config = version.evaluator_configs.build(
            evaluator_type: "PromptTracker::Evaluators::LengthEvaluator"
          )

          expect(config).to be_valid
        end
      end
    end
  end

  describe "scopes" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    describe ".enabled" do
      it "returns only enabled configs" do
        enabled1 = create(:evaluator_config, configurable: version, enabled: true)
        enabled2 = create(:evaluator_config, configurable: version, enabled: true, evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator")
        create(:evaluator_config, :disabled, configurable: version, evaluator_type: "PromptTracker::Evaluators::FormatEvaluator")

        expect(described_class.enabled).to contain_exactly(enabled1, enabled2)
      end
    end
  end

  describe "instance methods" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:config) { create(:evaluator_config, :keyword_evaluator, configurable: version) }

    describe "#name" do
      it "returns titleized evaluator_key when metadata not available" do
        config.evaluator_type = "PromptTracker::Evaluators::CustomEvaluator"
        allow(PromptTracker::EvaluatorRegistry).to receive(:get).and_return(nil)

        expect(config.name).to eq("Custom")
      end

      it "returns name from metadata when available" do
        allow(PromptTracker::EvaluatorRegistry).to receive(:get).and_return({ name: "Custom Name" })
        expect(config.name).to eq("Custom Name")
      end
    end

    describe "#description" do
      it "returns description from metadata when available" do
        allow(PromptTracker::EvaluatorRegistry).to receive(:get).and_return({ description: "Test description" })
        expect(config.description).to eq("Test description")
      end

      it "returns nil when metadata not available" do
        allow(PromptTracker::EvaluatorRegistry).to receive(:get).and_return(nil)
        expect(config.description).to be_nil
      end
    end
  end
end
