# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_tests
#
#  created_at         :datetime         not null
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  id                 :bigint           not null, primary key
#  metadata           :jsonb            not null
#  name               :string           not null
#  prompt_version_id  :bigint           not null
#  tags               :jsonb            not null
#  updated_at         :datetime         not null
#
require "rails_helper"

module PromptTracker
  RSpec.describe Test, type: :model do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:test) do
      create(:test,
             testable: version,
             name: "test_greeting")
    end

    describe "associations" do
      it { should belong_to(:testable) }
      it { should have_many(:test_runs).dependent(:destroy) }
    end

    describe "validations" do
      it { should validate_presence_of(:name) }
    end

    describe "scopes" do
      let!(:enabled_test) { create(:test, testable: version, enabled: true) }
      let!(:disabled_test) { create(:test, testable: version, enabled: false) }

      it "filters enabled tests" do
        expect(Test.enabled).to include(enabled_test)
        expect(Test.enabled).not_to include(disabled_test)
      end

      it "filters disabled tests" do
        expect(Test.disabled).to include(disabled_test)
        expect(Test.disabled).not_to include(enabled_test)
      end
    end

      describe "#single_turn? and #conversational?" do
        context "when testable does not respond to api_type" do
          before do
            non_api_testable = double("NonApiTestable")
            allow(non_api_testable).to receive(:respond_to?).with(:api_type).and_return(false)
            allow(test).to receive(:testable).and_return(non_api_testable)
          end

          it "defaults to single-turn mode" do
            expect(test.single_turn?).to be true
            expect(test.conversational?).to be false
          end
        end

        context "when testable api_type is openai_chat_completions" do
          before do
            chat_testable = double("ChatTestable", api_type: :openai_chat_completions)
            allow(chat_testable).to receive(:respond_to?).with(:api_type).and_return(true)
            allow(test).to receive(:testable).and_return(chat_testable)
          end

          it "is single-turn" do
            expect(test.single_turn?).to be true
            expect(test.conversational?).to be false
          end
        end

        context "when testable api_type is conversational (e.g. Assistants API)" do
          before do
            assistant_testable = double("AssistantTestable", api_type: :openai_assistants)
            allow(assistant_testable).to receive(:respond_to?).with(:api_type).and_return(true)
            allow(test).to receive(:testable).and_return(assistant_testable)
          end

          it "is conversational" do
            expect(test.single_turn?).to be false
            expect(test.conversational?).to be true
          end
        end
      end

    describe "#pass_rate" do
      let!(:passed_run) { create(:test_run, test: test, passed: true) }
      let!(:failed_run) { create(:test_run, test: test, passed: false) }

      it "calculates pass rate correctly" do
        expect(test.pass_rate).to eq(50.0)
      end
    end

    describe "#passing?" do
      context "when last run passed" do
        let!(:run) { create(:test_run, test: test, passed: true) }

        it "returns true" do
          expect(test.passing?).to be true
        end
      end

      context "when last run failed" do
        let!(:run) { create(:test_run, test: test, passed: false) }

        it "returns false" do
          expect(test.passing?).to be false
        end
      end
    end
  end
end
