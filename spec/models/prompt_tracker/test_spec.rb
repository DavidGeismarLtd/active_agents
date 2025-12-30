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
