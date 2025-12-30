# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe CopyTestEvaluatorsService do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    describe ".call" do
      context "when there are no tests" do
        it "returns success with zero counts" do
          result = described_class.call(prompt_version: version)

          expect(result).to be_success
          expect(result.copied_count).to eq(0)
          expect(result.skipped_count).to eq(0)
          expect(result.error).to be_nil
        end
      end

      context "when tests have no evaluator configs" do
        before do
          create(:test, testable: version)
        end

        it "returns success with zero counts" do
          result = described_class.call(prompt_version: version)

          expect(result).to be_success
          expect(result.copied_count).to eq(0)
          expect(result.skipped_count).to eq(0)
        end
      end

      context "when copying from a single test" do
        let!(:test) { create(:test, testable: version) }
        let!(:test_config) do
          create(:evaluator_config,
                 configurable: test,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 10, max_length: 100 })
        end

        it "copies the evaluator config to monitoring" do
          expect {
            described_class.call(prompt_version: version)
          }.to change { version.evaluator_configs.count }.by(1)
        end

        it "returns success with correct counts" do
          result = described_class.call(prompt_version: version)

          expect(result).to be_success
          expect(result.copied_count).to eq(1)
          expect(result.skipped_count).to eq(0)
        end

        it "copies the config correctly" do
          described_class.call(prompt_version: version)

          monitoring_config = version.evaluator_configs.first
          expect(monitoring_config.evaluator_type).to eq("PromptTracker::Evaluators::LengthEvaluator")
          expect(monitoring_config.config).to eq({ "min_length" => 10, "max_length" => 100 })
          expect(monitoring_config.enabled).to be true
        end

        it "creates a separate record (not sharing the same config)" do
          described_class.call(prompt_version: version)

          monitoring_config = version.evaluator_configs.first
          expect(monitoring_config.id).not_to eq(test_config.id)
          expect(monitoring_config.configurable_type).to eq("PromptTracker::PromptVersion")
          expect(monitoring_config.configurable_id).to eq(version.id)
        end
      end

      context "when copying from multiple tests" do
        let!(:test1) { create(:test, testable: version, name: "Test 1") }
        let!(:test2) { create(:test, testable: version, name: "Test 2") }
        let!(:config1) do
          create(:evaluator_config,
                 configurable: test1,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 10 })
        end
        let!(:config2) do
          create(:evaluator_config,
                 configurable: test2,
                 evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
                 config: { keywords: [ "test" ] })
        end

        it "copies all unique evaluator configs" do
          expect {
            described_class.call(prompt_version: version)
          }.to change { version.evaluator_configs.count }.by(2)
        end

        it "returns success with correct counts" do
          result = described_class.call(prompt_version: version)

          expect(result).to be_success
          expect(result.copied_count).to eq(2)
          expect(result.skipped_count).to eq(0)
        end
      end

      context "when handling duplicates" do
        let!(:test) { create(:test, testable: version) }
        let!(:test_config) do
          create(:evaluator_config,
                 configurable: test,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 10 })
        end
        let!(:existing_monitoring_config) do
          create(:evaluator_config,
                 configurable: version,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 50 })
        end

        it "skips evaluators that already exist in monitoring" do
          expect {
            described_class.call(prompt_version: version)
          }.not_to change { version.evaluator_configs.count }
        end

        it "returns success with correct skip count" do
          result = described_class.call(prompt_version: version)

          expect(result).to be_success
          expect(result.copied_count).to eq(0)
          expect(result.skipped_count).to eq(1)
        end

        it "does not modify existing monitoring config" do
          described_class.call(prompt_version: version)

          existing_monitoring_config.reload
          expect(existing_monitoring_config.config).to eq({ "min_length" => 50 })
        end
      end

      context "when handling multiple tests with same evaluator type" do
        let!(:test1) { create(:test, testable: version, name: "Test 1") }
        let!(:test2) { create(:test, testable: version, name: "Test 2") }
        let!(:config1) do
          create(:evaluator_config,
                 configurable: test1,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 10 })
        end
        let!(:config2) do
          create(:evaluator_config,
                 configurable: test2,
                 evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
                 config: { min_length: 20 })
        end

        it "copies only the first occurrence" do
          expect {
            described_class.call(prompt_version: version)
          }.to change { version.evaluator_configs.count }.by(1)
        end

        it "uses the config from the first test" do
          described_class.call(prompt_version: version)

          monitoring_config = version.evaluator_configs.first
          expect(monitoring_config.config).to eq({ "min_length" => 10 })
        end
      end
    end
  end
end
