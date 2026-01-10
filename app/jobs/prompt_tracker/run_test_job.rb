# frozen_string_literal: true

module PromptTracker
  # Background job to run a single test (prompt version or assistant).
  #
  # This job:
  # 1. Loads an existing TestRun (created by controller with "running" status)
  # 2. Detects test type and routes to appropriate runner
  # 3. Executes the test via the runner service
  # 4. Updates the test run with results
  # 5. Broadcasts completion via Turbo Streams
  #
  # Runner routing:
  # - PromptTracker::PromptVersion (single-turn) → PromptTracker::TestRunners::SingleTurnRunner
  # - PromptTracker::PromptVersion (conversational) → PromptTracker::TestRunners::Openai::ResponseApiConversationalRunner
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

      # Route to appropriate runner based on testable type and test mode
      runner_class = resolve_runner_class(test, testable)

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

    # Resolve the runner class based on testable type and test mode
    #
    # Runner selection matrix:
    # - PromptVersion + single_turn  → SingleTurnRunner (all providers)
    # - PromptVersion + conversational → ResponseApiConversationalRunner
    # - Openai::Assistant → AssistantRunner
    #
    # @param test [Test] the test configuration
    # @param testable [Object] the testable object
    # @return [Class] the runner class
    # @raise [ArgumentError] if no runner found for testable type
    def resolve_runner_class(test, testable)
      case testable
      when PromptVersion
        if test_is_conversational?(test)
          TestRunners::Openai::ResponseApiConversationalRunner
        else
          TestRunners::SingleTurnRunner
        end
      when Openai::Assistant
        TestRunners::Openai::AssistantRunner
      else
        raise ArgumentError, "No runner found for testable type: #{testable.class.name}"
      end
    end

    # Check if test is conversational mode
    #
    # @param test [Test] the test
    # @return [Boolean]
    def test_is_conversational?(test)
      # Check if test has test_mode column and is conversational
      test.respond_to?(:conversational?) && test.conversational?
    end
  end
end
