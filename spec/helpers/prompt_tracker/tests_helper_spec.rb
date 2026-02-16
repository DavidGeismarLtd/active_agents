# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe TestsHelper, type: :helper do
    describe "#run_test_path" do
      context "when test belongs to a PromptVersion" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, prompt: prompt) }
        let(:test) { create(:test, testable: version) }

        it "returns the correct path" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .run_testing_prompt_version_test_path(version, test)
          expect(helper.run_test_path(test)).to eq(expected_path)
        end
      end

      context "when test belongs to a PromptVersion with Assistants API" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, :with_assistants, prompt: prompt) }
        let(:test) { create(:test, testable: version) }

        it "returns the correct path" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .run_testing_prompt_version_test_path(version, test)
          expect(helper.run_test_path(test)).to eq(expected_path)
        end
      end

      context "when test belongs to unknown testable type" do
        let(:test) { build(:test) }

        it "raises ArgumentError" do
          allow(test).to receive(:testable).and_return(double("Unknown"))
          expect { helper.run_test_path(test) }.to raise_error(ArgumentError, /Unknown testable type/)
        end
      end
    end

    describe "#datasets_path_for_testable" do
      context "when testable is a PromptVersion" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, prompt: prompt) }

        it "returns the correct path" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .testing_prompt_prompt_version_datasets_path(prompt, version)
          expect(helper.datasets_path_for_testable(version)).to eq(expected_path)
        end
      end

      context "when testable is a PromptVersion with Assistants API" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, :with_assistants, prompt: prompt) }

        it "returns the correct path" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .testing_prompt_prompt_version_datasets_path(prompt, version)
          expect(helper.datasets_path_for_testable(version)).to eq(expected_path)
        end
      end

      context "when testable is unknown type" do
        it "raises ArgumentError" do
          unknown = double("Unknown")
          expect { helper.datasets_path_for_testable(unknown) }.to raise_error(ArgumentError, /Unknown testable type/)
        end
      end
    end

    describe "#load_more_runs_path_for_test" do
      context "when test belongs to a PromptVersion" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, prompt: prompt) }
        let(:test) { create(:test, testable: version) }

        it "returns the correct path with pagination params" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .load_more_runs_testing_prompt_version_test_path(version, test, offset: 10, limit: 5)
          expect(helper.load_more_runs_path_for_test(test, offset: 10, limit: 5)).to eq(expected_path)
        end
      end

      context "when test belongs to a PromptVersion with Assistants API" do
        let(:prompt) { create(:prompt) }
        let(:version) { create(:prompt_version, :with_assistants, prompt: prompt) }
        let(:test) { create(:test, testable: version) }

        it "returns the correct path with pagination params" do
          expected_path = PromptTracker::Engine.routes.url_helpers
            .load_more_runs_testing_prompt_version_test_path(version, test, offset: 0, limit: 10)
          expect(helper.load_more_runs_path_for_test(test, offset: 0, limit: 10)).to eq(expected_path)
        end
      end

      context "when test belongs to unknown testable type" do
        let(:test) { build(:test) }

        it "raises ArgumentError" do
          allow(test).to receive(:testable).and_return(double("Unknown"))
          expect { helper.load_more_runs_path_for_test(test, offset: 0, limit: 5) }
            .to raise_error(ArgumentError, /Unknown testable type/)
        end
      end
    end
  end
end
