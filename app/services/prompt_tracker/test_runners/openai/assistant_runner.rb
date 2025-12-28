# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      # Test runner for Openai::Assistant testables.
      #
      # This runner:
      # 1. Extracts test scenario from dataset row or custom variables
      # 2. Runs a multi-turn conversation using ConversationRunner
      # 3. Runs evaluators on the conversation
      # 4. Updates the test run with results
      #
      # @example Run an assistant test
      #   runner = Openai::AssistantRunner.new(
      #     test_run: test_run,
      #     test: test,
      #     testable: assistant
      #   )
      #   runner.run
      #
      class AssistantRunner < Base
        # Execute the assistant test
        #
        # @return [void]
        def run
          # Assistant tests can run with either dataset_row or custom_variables
          start_time = Time.current

          # Extract test scenario from dataset row OR custom variables
          interlocutor_prompt, max_turns = extract_test_scenario

          # Run the conversation
          conversation_runner = PromptTracker::Openai::ConversationRunner.new(
            assistant_id: testable.assistant_id,
            interlocutor_simulation_prompt: interlocutor_prompt,
            max_turns: max_turns
          )

          conversation_result = conversation_runner.run!

          # Store conversation data
          test_run.update!(conversation_data: conversation_result)

          # Run evaluators
          evaluator_results = run_assistant_evaluators

          # Calculate pass/fail
          passed = evaluator_results.all? { |r| r[:passed] }

          # Update test run
          execution_time = ((Time.current - start_time) * 1000).to_i
          test_run.update!(
            status: passed ? "passed" : "failed",
            passed: passed,
            execution_time_ms: execution_time,
            metadata: test_run.metadata.merge(
              completed_at: Time.current.iso8601,
              evaluator_results: evaluator_results
            )
          )

          # Note: Broadcasts are handled by after_update_commit callback in TestRun model
          # Assistant test broadcasts are currently disabled (see broadcast_changes method)
        end

        private

        # Extract test scenario from dataset row or custom variables
        #
        # @return [Array<String, Integer>] interlocutor_prompt and max_turns
        # @raise [ArgumentError] if required data is missing
        def extract_test_scenario
          if test_run.dataset_row.present?
            # Dataset mode: extract from dataset row
            row_data = test_run.dataset_row.row_data.with_indifferent_access
            interlocutor_prompt = row_data[:interlocutor_simulation_prompt]
            max_turns = row_data[:max_turns] || 5
          elsif test_run.metadata.dig("custom_variables").present?
            # Custom mode: extract from metadata
            custom_vars = test_run.metadata["custom_variables"].with_indifferent_access
            interlocutor_prompt = custom_vars[:interlocutor_simulation_prompt]
            max_turns = custom_vars[:max_turns] || 3
          else
            raise ArgumentError, "Assistant test requires either dataset_row or custom_variables"
          end

          raise ArgumentError, "interlocutor_simulation_prompt is required" if interlocutor_prompt.blank?

          [ interlocutor_prompt, max_turns ]
        end

        # Run evaluators for assistant tests
        #
        # @return [Array<Hash>] array of evaluator results
        def run_assistant_evaluators
          evaluator_configs = test.evaluator_configs.enabled.order(:created_at)
          results = []

          evaluator_configs.each do |config|
            evaluator_type = config.evaluator_type
            evaluator_config = config.config || {}

            # Add evaluator_config_id and test_run to the config
            evaluator_config = evaluator_config.merge(
              evaluator_config_id: config.id,
              evaluation_context: "test_run",
              test_run: test_run
            )

            # Build and run the evaluator
            # Pass conversation_data (Hash) instead of test_run (ActiveRecord object)
            evaluator_class = evaluator_type.constantize
            evaluator = evaluator_class.new(test_run.conversation_data, evaluator_config)
            evaluation = evaluator.evaluate

            results << {
              evaluator_type: evaluator_type,
              score: evaluation.score,
              passed: evaluation.passed,
              feedback: evaluation.feedback
            }
          end

          results
        end
      end
    end
  end
end
