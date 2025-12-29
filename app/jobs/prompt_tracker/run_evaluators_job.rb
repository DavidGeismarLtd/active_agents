# frozen_string_literal: true

module PromptTracker
  # Background job to run evaluators for a test run asynchronously.
  #
  # This job is enqueued after the LLM response is received to run all
  # configured evaluators (human, llm_judge, automated) in the background.
  #
  # @example Enqueue the job
  #   RunEvaluatorsJob.perform_later(test_run.id)
  #
  class RunEvaluatorsJob < ApplicationJob
    queue_as :prompt_tracker_evaluators

    # Run evaluators for a test run
    #
    # @param test_run_id [Integer] the ID of the test run
    def perform(test_run_id)
      Rails.logger.info "🔧 RunEvaluatorsJob started for test_run #{test_run_id}"

      test_run = PromptTestRun.find(test_run_id)

      # Skip if already completed or no LLM response
      if test_run.completed?
        Rails.logger.info "⏭️  Test run #{test_run_id} already completed, skipping"
        return
      end

      unless test_run.llm_response
        Rails.logger.warn "⚠️  Test run #{test_run_id} has no LLM response, skipping"
        return
      end

      # Mark as running
      test_run.update!(status: "running")
      Rails.logger.info "▶️  Test run #{test_run_id} marked as running"

      # Get the test and version
      prompt_test = test_run.prompt_test
      llm_response = test_run.llm_response

      # Run evaluators and create Evaluation records
      evaluations = run_evaluators(prompt_test, llm_response, test_run)
      Rails.logger.info "📊 Evaluators completed: #{evaluations.length} evaluations created"

      # Determine if test passed (all evaluators must pass)
      passed = evaluations.all?(&:passed)

      # Update test run with results
      passed_evaluators = evaluations.count(&:passed)
      failed_evaluators = evaluations.count { |e| !e.passed }

      test_run.update!(
        status: passed ? "passed" : "failed",
        passed: passed,
        passed_evaluators: passed_evaluators,
        failed_evaluators: failed_evaluators,
        total_evaluators: evaluations.length
      )

      Rails.logger.info "✨ Test run #{test_run_id} completed: #{passed ? 'PASSED' : 'FAILED'}"

      # Broadcast update via ActionCable
      broadcast_test_run_update(test_run)
      Rails.logger.info "📡 Broadcast sent for test run #{test_run_id}"
    rescue StandardError => e
      Rails.logger.error "❌ RunEvaluatorsJob failed for test_run #{test_run_id}: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      test_run.update!(
        status: "error",
        passed: false,
        error_message: "#{e.class}: #{e.message}"
      )

      raise
    end

    private

    # Run all configured evaluators and create Evaluation records
    #
    # @param prompt_test [PromptTest] the test configuration
    # @param llm_response [LlmResponse] the LLM response to evaluate
    # @param test_run [PromptTestRun] the test run to associate evaluations with
    # @return [Array<Evaluation>] array of created evaluations
    def run_evaluators(prompt_test, llm_response, test_run)
      evaluations = []
      # Get evaluator configs, ordered by creation time
      evaluator_configs = prompt_test.evaluator_configs.enabled.order(:created_at)

      evaluator_configs.each do |config|
        evaluator_key = config.evaluator_key.to_sym
        evaluator_config = config.config || {}

        # Add test_run context to evaluator config
        # Include llm_response for evaluation record creation
        evaluator_config = evaluator_config.merge(
          evaluation_context: "test_run",
          test_run_id: test_run.id,
          llm_response: llm_response
        )

        # Build and run evaluator
        # Pass response_text (String) as the evaluated data
        evaluator = EvaluatorRegistry.build(
          evaluator_key,
          llm_response.response_text,
          evaluator_config
        )
        next unless evaluator

        # All evaluators now use RubyLLM directly - no block needed!
        # Evaluation is created with correct context and test_run association
        evaluation = evaluator.evaluate

        evaluations << evaluation
      end

      evaluations
    end

    # Broadcast test run update via Turbo Streams
    #
    # @param test_run [PromptTestRun] the test run that was updated
    def broadcast_test_run_update(test_run)
      test = test_run.prompt_test
      version = test_run.prompt_version
      prompt = version.prompt

      # Broadcast to test run detail page (trigger refresh)
      Turbo::StreamsChannel.broadcast_refresh_to("test_run_#{test_run.id}")

      # Broadcast to tests index page - update test row
      broadcast_turbo_stream_replace(
        stream: "prompt_version_#{version.id}",
        target: "test_row_#{test.id}",
        partial: "prompt_tracker/testing/tests/prompt_versions/test_row",
        locals: { test: test, prompt: prompt, version: version }
      )

      # Broadcast to tests index page - update overall status card
      all_tests = version.prompt_tests.order(created_at: :desc)
      broadcast_turbo_stream_replace(
        stream: "prompt_version_#{version.id}",
        target: "overall_status_card",
        partial: "prompt_tracker/testing/prompt_tests/overall_status_card",
        locals: { tests: all_tests }
      )

      # Broadcast to individual test detail page - update status card
      broadcast_turbo_stream_replace(
        stream: "prompt_test_#{test.id}",
        target: "test_status_card",
        partial: "prompt_tracker/testing/prompt_tests/test_status_card",
        locals: { test: test }
      )

      # Broadcast to individual test detail page - update test run row in recent runs table
      broadcast_turbo_stream_replace(
        stream: "prompt_test_#{test.id}",
        target: "test_run_row_#{test_run.id}",
        partial: "prompt_tracker/testing/test_runs/prompt_versions/row",
        locals: { run: test_run }
      )
    end

    # Helper to broadcast Turbo Stream replace with proper route context
    #
    # @param stream [String] the stream name
    # @param target [String] the DOM target ID
    # @param partial [String] the partial path
    # @param locals [Hash] the locals to pass to the partial
    def broadcast_turbo_stream_replace(stream:, target:, partial:, locals:)
      # Render with ApplicationController to include helpers
      html = PromptTracker::ApplicationController.render(
        partial: partial,
        locals: locals
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        stream,
        target: target,
        html: html
      )
    end
  end
end
