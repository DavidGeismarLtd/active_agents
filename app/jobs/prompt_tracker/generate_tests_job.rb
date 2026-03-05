# frozen_string_literal: true

module PromptTracker
  # Background job to generate tests using AI.
  #
  # This job:
  # 1. Calls TestGeneratorService to generate tests (tests broadcast themselves via callbacks)
  # 2. Broadcasts generation status updates
  #
  # @example Enqueue the job
  #   GenerateTestsJob.perform_later(prompt_version.id, instructions: "Focus on edge cases")
  #
  class GenerateTestsJob < ApplicationJob
    queue_as :prompt_tracker_test_generation

    # Generate tests for a prompt version
    #
    # @param prompt_version_id [Integer] ID of the prompt version
    # @param instructions [String, nil] optional custom instructions for the LLM
    def perform(prompt_version_id, instructions: nil)
      Rails.logger.info { "🚀 GenerateTestsJob started for PromptVersion #{prompt_version_id}" }

      prompt_version = PromptVersion.find(prompt_version_id)

      # Broadcast start status
      broadcast_generation_status(prompt_version, status: "running", message: "Generating tests with AI...")

      # Generate tests using the service (tests will broadcast themselves via after_create_commit)
      result = TestGeneratorService.generate(
        prompt_version: prompt_version,
        instructions: instructions
      )

      Rails.logger.info { "✅ Generated #{result[:count]} tests for PromptVersion #{prompt_version_id}" }

      # Broadcast completion status
      broadcast_generation_status(
        prompt_version,
        status: "complete",
        message: "Successfully generated #{result[:count]} test(s)"
      )

      # Broadcast updated test count in header
      broadcast_test_count_update(prompt_version)

      Rails.logger.info { "📡 Broadcasts sent for PromptVersion #{prompt_version_id}" }
    rescue TestGeneratorService::MalformedResponseError => e
      Rails.logger.error { "❌ Test generation failed: #{e.message}" }

      broadcast_generation_status(
        prompt_version,
        status: "error",
        message: "Test generation failed: #{e.message}"
      )
    end

    private

    # Broadcast generation status update
    #
    # @param prompt_version [PromptVersion] the prompt version
    # @param status [String] "running", "complete", or "error"
    # @param message [String] status message to display
    def broadcast_generation_status(prompt_version, status:, message:)
      html = PromptTracker::ApplicationController.render(
        partial: "prompt_tracker/testing/tests/generation_status",
        locals: {
          status: status,
          message: message
        }
      )

      Turbo::StreamsChannel.broadcast_update_to(
        prompt_version.testable_stream_name,
        target: "test-generation-status",
        html: html
      )
    end

    # Broadcast updated test count in the card header
    #
    # @param prompt_version [PromptVersion] the prompt version
    def broadcast_test_count_update(prompt_version)
      Turbo::StreamsChannel.broadcast_update_to(
        prompt_version.testable_stream_name,
        target: "tests-count",
        html: prompt_version.tests.count.to_s
      )
    end
  end
end
