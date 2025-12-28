# frozen_string_literal: true

module PromptTracker
  # Background job to run a single test (prompt version or assistant).
  #
  # This job:
  # 1. Loads an existing TestRun (created by controller with "running" status)
  # 2. Detects test type and routes to appropriate runner using convention
  # 3. Executes the test via the runner service
  # 4. Updates the test run with results
  # 5. Broadcasts completion via Turbo Streams
  #
  # Convention-based routing:
  # - PromptTracker::PromptVersion → PromptTracker::TestRunners::PromptVersionRunner
  # - PromptTracker::Openai::Assistant → PromptTracker::TestRunners::Openai::AssistantRunner
  #
  # @example Enqueue a prompt version test run
  #   test_run = TestRun.create!(test: test, prompt_version: version, status: "running")
  #   RunTestJob.perform_later(test_run.id, use_real_llm: true)
  #
  # @example Enqueue an assistant test run
  #   test_run = TestRun.create!(test: test, status: "running")
  #   RunTestJob.perform_later(test_run.id)
  #
  class RunTestJob < ApplicationJob
    queue_as :prompt_tracker_tests

    # Disable retries for now to avoid noise in logs
    sidekiq_options retry: false

    # Execute the test run
    #
    # @param test_run_id [Integer] ID of the TestRun to execute
    # @param use_real_llm [Boolean] whether to use real LLM API or mock (for prompt tests)
    def perform(test_run_id, use_real_llm: false)
      Rails.logger.info "🚀 RunTestJob started for test_run #{test_run_id}"

      test_run = TestRun.find(test_run_id)
      test = test_run.test
      testable = test.testable
      # Route to appropriate runner based on testable type using convention
      runner_class = resolve_runner_class(testable)

      runner = runner_class.new(
        test_run: test_run,
        test: test,
        testable: testable,
        use_real_llm: use_real_llm
      )
      runner.run

      Rails.logger.info "✅ RunTestJob completed for test_run #{test_run_id}"
    end

    private

    # Resolve the runner class based on testable type using convention
    #
    # Convention:
    # - PromptTracker::PromptVersion → PromptTracker::TestRunners::PromptVersionRunner
    # - PromptTracker::Openai::Assistant → PromptTracker::TestRunners::Openai::AssistantRunner
    #
    # @param testable [Object] the testable object
    # @return [Class] the runner class
    # @raise [ArgumentError] if no runner found for testable type
    def resolve_runner_class(testable)
      # Get the full class name (e.g., "PromptTracker::PromptVersion")
      testable_class_name = testable.class.name

      # Remove the PromptTracker:: prefix to get the relative path
      # e.g., "PromptVersion" or "Openai::Assistant"
      relative_class_name = testable_class_name.sub(/^PromptTracker::/, "")

      # Build the runner class name by convention
      # e.g., "PromptTracker::TestRunners::PromptVersionRunner"
      # or "PromptTracker::TestRunners::Openai::AssistantRunner"
      runner_class_name = "PromptTracker::TestRunners::#{relative_class_name}Runner"

      # Constantize and return the runner class
      runner_class_name.constantize
    rescue NameError => e
      raise ArgumentError, "No runner found for testable type: #{testable_class_name}. " \
                          "Expected runner class: #{runner_class_name}. " \
                          "Error: #{e.message}"
    end
  end
end
