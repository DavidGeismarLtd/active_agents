# frozen_string_literal: true

module PromptTracker
  # Background job to generate dataset rows using AI.
  #
  # This job:
  # 1. Calls DatasetRowGeneratorService to generate rows (rows broadcast themselves via callbacks)
  # 2. Broadcasts generation status updates
  #
  # @example Enqueue the job
  #   GenerateDatasetRowsJob.perform_later(dataset.id, count: 20, instructions: "Focus on edge cases")
  #
  class GenerateDatasetRowsJob < ApplicationJob
    queue_as :prompt_tracker_dataset_generation

    # Generate dataset rows
    #
    # @param dataset_id [Integer] ID of the dataset
    # @param count [Integer] number of rows to generate (1-100)
    # @param instructions [String, nil] optional custom instructions for the LLM
    # @param model [String, nil] optional model to use (defaults to configured default)
    def perform(dataset_id, count:, instructions: nil, model: nil)
      Rails.logger.info { "🚀 GenerateDatasetRowsJob started for dataset #{dataset_id}" }

      dataset = Dataset.find(dataset_id)

      # Broadcast start status
      broadcast_generation_status(dataset, status: "running", message: "Generating #{count} rows...")

      # Generate rows using the service (rows will broadcast themselves via after_create_commit)
      rows = DatasetRowGeneratorService.generate(
        dataset: dataset,
        count: count,
        instructions: instructions,
        model: model
      )

      Rails.logger.info { "✅ Generated #{rows.length} rows for dataset #{dataset_id}" }

      # Broadcast completion status
      broadcast_generation_status(
        dataset,
        status: "complete",
        message: "Successfully generated #{rows.length} rows"
      )

      # Broadcast updated row count in header
      broadcast_row_count_update(dataset)

      Rails.logger.info { "📡 Broadcasts sent for dataset #{dataset_id}" }
    end

    private

    # Broadcast generation status update
    #
    # @param dataset [Dataset] the dataset
    # @param status [String] "running", "complete", or "error"
    # @param message [String] status message to display
    def broadcast_generation_status(dataset, status:, message:)
      html = PromptTracker::ApplicationController.render(
        partial: "prompt_tracker/testing/datasets/generation_status",
        locals: {
          status: status,
          message: message
        }
      )

      Turbo::StreamsChannel.broadcast_update_to(
        "dataset_#{dataset.id}_rows",
        target: "generation-status",
        html: html
      )
    end

    # Broadcast updated row count in the card header
    #
    # @param dataset [Dataset] the dataset
    def broadcast_row_count_update(dataset)
      Turbo::StreamsChannel.broadcast_update_to(
        "dataset_#{dataset.id}_rows",
        target: "dataset-row-count",
        html: dataset.row_count.to_s
      )
    end
  end
end
