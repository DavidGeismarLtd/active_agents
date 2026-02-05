# frozen_string_literal: true

module PromptTracker
  # Background job to run a single test for a PromptVersion.
  #
  # This job:
  # 1. Loads an existing TestRun (created by controller with "running" status)
  # 2. Executes the test via PromptVersionRunner
  # 3. Updates the test run with results
  # 4. Broadcasts completion via Turbo Streams
  #
  # All testables (prompts and assistants) are now represented as PromptVersions,
  # so this job always uses TestRunners::PromptVersionRunner.
  #
  # @example Enqueue a test run
  #   test_run = TestRun.create!(test: test, prompt_version: version, status: "running")
  #   RunTestJob.perform_later(test_run.id, use_real_llm: true)
  #
  class RunTestJob < ApplicationJob
    queue_as :prompt_tracker_tests

    # Disable retries for now to avoid noise in logs
    sidekiq_options retry: false

    # Execute the test run
    #
    # @param test_run_id [Integer] ID of the TestRun to execute
    # @param use_real_llm [Boolean] whether to use real LLM API or mock
    def perform(test_run_id, use_real_llm: false)
      Rails.logger.info "🚀 RunTestJob started for test_run #{test_run_id}"

      test_run = TestRun.find(test_run_id)
      test = test_run.test
      testable = test.testable

      # Always use PromptVersionRunner (unified for all testables)
      runner = TestRunners::PromptVersionRunner.new(
        test_run: test_run,
        test: test,
        testable: testable,
        use_real_llm: use_real_llm
      )
      runner.run

      Rails.logger.info "✅ RunTestJob completed for test_run #{test_run_id}"
    end
  end
end
