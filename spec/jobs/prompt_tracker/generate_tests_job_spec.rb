# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::GenerateTestsJob, type: :job do
  describe "#perform" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    before do
      # Stub Turbo Stream broadcasts
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)

      # Stub Test broadcasts to avoid route helper issues in tests
      allow_any_instance_of(PromptTracker::Test).to receive(:broadcast_prepend_to_testable)
    end

    it "calls TestGeneratorService with correct parameters" do
      expect(PromptTracker::TestGeneratorService).to receive(:generate).with(
        prompt_version: version,
        instructions: "Test instructions",
        count: 5
      ).and_return({ tests: [], count: 0, overall_reasoning: "Test reasoning" })

      described_class.perform_now(
        version.id,
        instructions: "Test instructions"
      )
    end

    it "broadcasts running status at start" do
      allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return({ tests: [], count: 0, overall_reasoning: "" })

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        version.testable_stream_name,
        hash_including(target: "test-generation-status")
      )

      described_class.perform_now(version.id, instructions: nil)
    end

    it "generates tests (which broadcast themselves via callbacks)" do
      test = create(:test, testable: version)
      allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return(
        { tests: [ test ], count: 1, overall_reasoning: "Test reasoning" }
      )

      described_class.perform_now(version.id, instructions: nil)
    end

    it "broadcasts completion status" do
      test = create(:test, testable: version)
      allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return(
        { tests: [ test ], count: 1, overall_reasoning: "Test reasoning" }
      )

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        version.testable_stream_name,
        hash_including(target: "test-generation-status")
      ).at_least(:once)

      described_class.perform_now(version.id, instructions: nil)
    end

    it "broadcasts test count update" do
      allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return({ tests: [], count: 0, overall_reasoning: "" })

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        version.testable_stream_name,
        hash_including(target: "tests-count")
      )

      described_class.perform_now(version.id, instructions: nil)
    end

    it "logs start and completion" do
      allow(PromptTracker::TestGeneratorService).to receive(:generate).and_return({ tests: [], count: 0, overall_reasoning: "" })

      expect(Rails.logger).to receive(:info).at_least(:once)

      described_class.perform_now(version.id, instructions: nil)
    end

    context "when generation fails" do
      it "broadcasts error status" do
        allow(PromptTracker::TestGeneratorService).to receive(:generate).and_raise(
          PromptTracker::TestGeneratorService::MalformedResponseError.new("Invalid response")
        )

        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
          version.testable_stream_name,
          hash_including(target: "test-generation-status")
        ).at_least(:once)

        described_class.perform_now(version.id, instructions: nil)
      end

      it "logs the error" do
        allow(PromptTracker::TestGeneratorService).to receive(:generate).and_raise(
          PromptTracker::TestGeneratorService::MalformedResponseError.new("Invalid response")
        )

        expect(Rails.logger).to receive(:error).at_least(:once)

        described_class.perform_now(version.id, instructions: nil)
      end
    end
  end
end
