# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::GenerateDatasetRowsJob, type: :job do
  describe "#perform" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }
    let(:dataset) { create(:dataset, testable: version) }

    before do
      # Stub Turbo Stream broadcasts
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)

      # Stub DatasetRow broadcasts to avoid route helper issues in tests
      allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_prepend_to_dataset)
      allow_any_instance_of(PromptTracker::DatasetRow).to receive(:broadcast_replace_to_dataset)
    end

    it "calls DatasetRowGeneratorService with correct parameters" do
      expect(PromptTracker::DatasetRowGeneratorService).to receive(:generate).with(
        dataset: dataset,
        count: 10,
        instructions: "Test instructions",
        model: "gpt-4o"
      ).and_return([])

      described_class.perform_now(
        dataset.id,
        count: 10,
        instructions: "Test instructions",
        model: "gpt-4o"
      )
    end

    it "broadcasts running status at start" do
      allow(PromptTracker::DatasetRowGeneratorService).to receive(:generate).and_return([])

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        "dataset_#{dataset.id}_rows",
        hash_including(target: "generation-status")
      )

      described_class.perform_now(dataset.id, count: 10)
    end

    it "generates rows (which broadcast themselves via callbacks)" do
      allow(PromptTracker::DatasetRowGeneratorService).to receive(:generate) do
        # Create rows which will trigger their own broadcasts via after_create_commit
        [
          create(:dataset_row, dataset: dataset),
          create(:dataset_row, dataset: dataset)
        ]
      end

      described_class.perform_now(dataset.id, count: 2)
    end

    it "broadcasts completion status" do
      row = create(:dataset_row, dataset: dataset)
      allow(PromptTracker::DatasetRowGeneratorService).to receive(:generate).and_return([ row ])

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        "dataset_#{dataset.id}_rows",
        hash_including(target: "generation-status")
      ).at_least(:once)

      described_class.perform_now(dataset.id, count: 1)
    end

    it "broadcasts row count update" do
      allow(PromptTracker::DatasetRowGeneratorService).to receive(:generate).and_return([])

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        "dataset_#{dataset.id}_rows",
        hash_including(target: "dataset-row-count")
      )

      described_class.perform_now(dataset.id, count: 10)
    end

    it "logs start and completion" do
      allow(PromptTracker::DatasetRowGeneratorService).to receive(:generate).and_return([])

      expect(Rails.logger).to receive(:info).at_least(:once)

      described_class.perform_now(dataset.id, count: 10)
    end
  end
end
