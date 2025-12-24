# frozen_string_literal: true

module PromptTracker
  module Openai
    # Service for running tests on OpenAI Assistants.
    #
    # This service orchestrates:
    # 1. Running a conversation with the assistant using ConversationRunner
    # 2. Storing conversation data in TestRun
    # 3. Running configured evaluators (e.g., ConversationJudgeEvaluator)
    # 4. Recording the result
    #
    # @example Run a test
    #   runner = AssistantTestRunner.new(test, assistant)
    #   test_run = runner.run!(dataset_row: dataset_row)
    #   # => TestRun with conversation_data and evaluations
    #
    class AssistantTestRunner
      attr_reader :test, :assistant, :metadata, :test_run

      # Initialize the test runner
      #
      # @param test [Test] the test to run
      # @param assistant [Openai::Assistant] the assistant to test
      # @param metadata [Hash] additional metadata for the test run
      def initialize(test, assistant, metadata: {})
        @test = test
        @assistant = assistant
        @metadata = metadata || {}
        @test_run = nil
      end

      # Run the test synchronously
      #
      # @param dataset_row [DatasetRow] the dataset row with test scenario
      # @return [TestRun] the test run result
      def run!(dataset_row:)
        start_time = Time.current

        # Extract and validate test scenario from dataset row BEFORE creating test_run
        row_data = dataset_row.row_data.with_indifferent_access
        interlocutor_prompt = row_data[:interlocutor_simulation_prompt] || row_data["interlocutor_simulation_prompt"]
        max_turns = row_data[:max_turns] || row_data["max_turns"] || 5

        raise ArgumentError, "dataset_row must have interlocutor_simulation_prompt" if interlocutor_prompt.blank?

        # Create test run record
        @test_run = TestRun.create!(
          test: test,
          dataset_id: dataset_row.dataset_id,
          dataset_row_id: dataset_row.id,
          status: "running",
          metadata: metadata.merge(
            assistant_id: assistant.assistant_id,
            started_at: start_time.iso8601
          )
        )

        # Run the conversation
        conversation_runner = ConversationRunner.new(
          assistant_id: assistant.assistant_id,
          interlocutor_simulation_prompt: interlocutor_prompt,
          max_turns: max_turns
        )

        conversation_result = conversation_runner.run!

        # Store conversation data
        @test_run.update!(conversation_data: conversation_result)

        # Run evaluators
        evaluator_results = run_evaluators

        # Calculate pass/fail
        passed = determine_pass_fail(evaluator_results)

        # Update test run
        execution_time = ((Time.current - start_time) * 1000).to_i
        update_test_run_success(
          evaluator_results: evaluator_results,
          passed: passed,
          execution_time_ms: execution_time
        )

        @test_run.reload
      rescue => e
        # If test_run was created, update it with error details
        if @test_run
          execution_time = ((Time.current - start_time) * 1000).to_i
          update_test_run_error(e, execution_time)
          @test_run.reload
        else
          # If test_run wasn't created (validation error before creation), re-raise
          raise
        end
      end

      # Run the test asynchronously (evaluators run in background)
      #
      # @param dataset_row [DatasetRow] the dataset row with test scenario
      # @return [TestRun] the test run result (in "running" state)
      def run_async!(dataset_row:)
        start_time = Time.current

        # Create test run record
        @test_run = TestRun.create!(
          test: test,
          dataset_id: dataset_row.dataset_id,
          dataset_row_id: dataset_row.id,
          status: "running",
          metadata: metadata.merge(
            assistant_id: assistant.assistant_id,
            async: true,
            started_at: start_time.iso8601
          )
        )

        # Extract test scenario from dataset row
        row_data = dataset_row.row_data.with_indifferent_access
        interlocutor_prompt = row_data[:interlocutor_simulation_prompt] || row_data["interlocutor_simulation_prompt"]
        max_turns = row_data[:max_turns] || row_data["max_turns"] || 5

        raise ArgumentError, "dataset_row must have interlocutor_simulation_prompt" if interlocutor_prompt.blank?

        # Run the conversation
        conversation_runner = ConversationRunner.new(
          assistant_id: assistant.assistant_id,
          interlocutor_simulation_prompt: interlocutor_prompt,
          max_turns: max_turns
        )

        conversation_result = conversation_runner.run!

        # Store conversation data and execution time
        execution_time = ((Time.current - start_time) * 1000).to_i
        @test_run.update!(
          conversation_data: conversation_result,
          execution_time_ms: execution_time
        )

        # Enqueue background job to run evaluators
        RunEvaluatorsJob.perform_later(@test_run.id)

        @test_run
      rescue => e
        execution_time = ((Time.current - start_time) * 1000).to_i
        update_test_run_error(e, execution_time)
        @test_run
      end

      private

      # Run all configured evaluators
      #
      # @return [Array<Hash>] array of evaluator results
      def run_evaluators
        # Get evaluator configs, ordered by priority
        evaluator_configs = test.evaluator_configs.enabled.order(priority: :desc)
        results = []

        evaluator_configs.each do |config|
          evaluator_type = config.evaluator_type
          evaluator_config = config.config || {}

          # Add evaluator_config_id to the config
          evaluator_config = evaluator_config.merge(
            evaluator_config_id: config.id,
            evaluation_context: "test"
          )

          # Build and run the evaluator
          evaluator_class = evaluator_type.constantize
          evaluator = evaluator_class.new(@test_run, evaluator_config)
          evaluation = evaluator.evaluate

          results << {
            evaluator_type: evaluator_type,
            evaluator_config_id: config.id,
            evaluation_id: evaluation.id,
            score: evaluation.score,
            passed: evaluation.passed
          }
        end

        results
      end

      # Determine if the test passed based on evaluator results
      #
      # @param evaluator_results [Array<Hash>] results from evaluators
      # @return [Boolean] true if all evaluators passed
      def determine_pass_fail(evaluator_results)
        return true if evaluator_results.empty?

        # All evaluators must pass
        evaluator_results.all? { |result| result[:passed] }
      end

      # Update test run with success
      #
      # @param evaluator_results [Array<Hash>] results from evaluators
      # @param passed [Boolean] whether the test passed
      # @param execution_time_ms [Integer] execution time in milliseconds
      def update_test_run_success(evaluator_results:, passed:, execution_time_ms:)
        @test_run.update!(
          status: passed ? "passed" : "failed",
          passed: passed,
          execution_time_ms: execution_time_ms,
          metadata: @test_run.metadata.merge(
            completed_at: Time.current.iso8601,
            evaluator_results: evaluator_results
          )
        )

        # Broadcast update via Turbo Stream
        @test_run.broadcast_update
      end

      # Update test run with error
      #
      # @param error [Exception] the error that occurred
      # @param execution_time_ms [Integer] execution time in milliseconds
      def update_test_run_error(error, execution_time_ms)
        @test_run.update!(
          status: "error",
          passed: false,
          execution_time_ms: execution_time_ms,
          error_message: "#{error.class}: #{error.message}",
          metadata: @test_run.metadata.merge(
            failed_at: Time.current.iso8601,
            error_backtrace: error.backtrace&.first(10)
          )
        )

        # Broadcast update via Turbo Stream
        @test_run.broadcast_update
      end
    end
  end
end
