# frozen_string_literal: true

module PromptTracker
  # Background job to run a single test for a AgentVersion.
  #
  # This job:
  # 1. Loads an existing TestRun (created by controller with "running" status)
  # 2. Executes the test via AgentVersionRunner
  # 3. Updates the test run with results
  # 4. Broadcasts completion via Turbo Streams
  #
  # All testables (prompts and assistants) are now represented as AgentVersions,
  # so this job always uses TestRunners::AgentVersionRunner.
  #
  # @example Enqueue a test run
  #   test_run = TestRun.create!(test: test, agent_version: version, status: "running")
  #   RunTestJob.perform_later(test_run.id, use_real_llm: true)
  #
  class RunTestJob < ApplicationJob
    queue_as :prompt_tracker_tests


    # Execute the test run
    #
    # @param test_run_id [Integer] ID of the TestRun to execute
    # @param use_real_llm [Boolean] whether to use real LLM API or mock
    def perform(test_run_id, use_real_llm: false)
      Rails.logger.info "🚀 RunTestJob started for test_run #{test_run_id}"

      test_run = TestRun.find(test_run_id)
      test = test_run.test
      testable = test.testable

      # Always use AgentVersionRunner (unified for all testables)
      runner = TestRunners::AgentVersionRunner.new(
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
