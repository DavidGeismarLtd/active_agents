# frozen_string_literal: true

module PromptTracker
  module TestRunners
    # Base class for all test runners.
    #
    # Provides common functionality for running tests on any testable
    # (PromptVersions, Assistants, etc.)
    #
    # Subclasses must implement:
    # - #run - Execute the test
    #
    # @example Create a new runner
    #   class MyRunner < Base
    #     def run
    #       # Run the test
    #     end
    #   end
    #
    class Base
      attr_reader :test_run, :test, :testable, :use_real_llm

      # Initialize the runner
      #
      # @param test_run [TestRun] the test run to execute
      # @param test [Test] the test configuration
      # @param testable [Object] the testable object (PromptVersion, Assistant, etc.)
      # @param use_real_llm [Boolean] whether to use real LLM API (default: false)
      def initialize(test_run:, test:, testable:, use_real_llm: false)
        @test_run = test_run
        @test = test
        @testable = testable
        @use_real_llm = use_real_llm
      end

      # Execute the test - must be implemented by subclasses
      #
      # @raise [NotImplementedError] if not implemented
      def run
        raise NotImplementedError, "Subclasses must implement #run"
      end

      private

      # Get variables from dataset row or custom variables
      #
      # @return [HashWithIndifferentAccess] the variables
      def variables
        if test_run.dataset_row.present?
          test_run.dataset_row.row_data.with_indifferent_access
        elsif test_run.metadata.dig("custom_variables").present?
          test_run.metadata["custom_variables"].with_indifferent_access
        else
          {}.with_indifferent_access
        end
      end

      # Run evaluators and return results
      #
      # @param evaluated_data [Object] the data to evaluate (conversation_data or llm_response)
      # @return [Array<Hash>] array of evaluator results
      def run_evaluators(evaluated_data)
        evaluator_configs = test.evaluator_configs.enabled.order(:created_at)
        results = []

        evaluator_configs.each do |config|
          evaluator_key = config.evaluator_key.to_sym
          evaluator_config = config.config || {}

          # Add evaluator_config_id and test_run to the config
          evaluator_config = evaluator_config.merge(
            evaluator_config_id: config.id,
            evaluation_context: "test_run",
            test_run: test_run
          )

          # Build and run the evaluator using EvaluatorRegistry
          evaluator = EvaluatorRegistry.build(
            evaluator_key,
            evaluated_data,
            evaluator_config
          )
          evaluation = evaluator.evaluate

          results << {
            evaluator_type: config.evaluator_type,
            score: evaluation.score,
            passed: evaluation.passed,
            feedback: evaluation.feedback
          }
        end

        results
      end

      # Update test run with final results
      #
      # @param passed [Boolean] whether the test passed
      # @param execution_time_ms [Integer] execution time in milliseconds
      # @param evaluator_results [Array<Hash>] evaluator results
      # @param extra_metadata [Hash] additional metadata to merge
      def update_test_run_results(passed:, execution_time_ms:, evaluator_results:, extra_metadata: {})
        test_run.update!(
          status: passed ? "passed" : "failed",
          passed: passed,
          execution_time_ms: execution_time_ms,
          metadata: test_run.metadata.merge(
            completed_at: Time.current.iso8601,
            evaluator_results: evaluator_results
          ).merge(extra_metadata)
        )
      end
    end
  end
end
