# frozen_string_literal: true

module PromptTracker
  # Background job for running LLM judge evaluations without requiring an EvaluatorConfig.
  #
  # This job is used for ad-hoc LLM judge evaluations triggered from the manual
  # evaluation form. Unlike EvaluationJob, it doesn't require a saved EvaluatorConfig,
  # making it suitable for one-off evaluations with custom configurations.
  #
  # @example Schedule an LLM judge evaluation
  #   LlmJudgeEvaluationJob.perform_later(response_id, config)
  #
  class LlmJudgeEvaluationJob < ApplicationJob
    queue_as :default

    # Performs the LLM judge evaluation
    #
    # @param llm_response_id [Integer] ID of the response to evaluate
    # @param config [Hash] Configuration for the LLM judge
    # @option config [String] :judge_model The LLM model to use as judge
    # @option config [Array<String>] :criteria Criteria to evaluate
    # @option config [String] :custom_instructions Additional instructions
    # @option config [Integer] :score_min Minimum score (default: 0)
    # @option config [Integer] :score_max Maximum score (default: 100)
    # @return [void]
    def perform(llm_response_id, config)
      llm_response = LlmResponse.find(llm_response_id)
      evaluator_key = :llm_judge

      # Build the evaluator with the provided config
      # Pass response_text (String) as the evaluated data
      # Include llm_response in config for evaluation record creation
      evaluator = EvaluatorRegistry.build(
        evaluator_key,
        llm_response.response_text,
        config.merge(llm_response: llm_response)
      )

      # Run the evaluator - it now calls RubyLLM directly!
      # No block needed - the evaluator handles the LLM API call internally
      evaluation = evaluator.evaluate

      # Update metadata with job info
      evaluation.update!(
        metadata: (evaluation.metadata || {}).merge(
          job_id: job_id,
          executed_at: Time.current,
          manual_evaluation: true,
          config: config
        )
      )

      Rails.logger.info(
        "LLM Judge evaluation completed for response #{llm_response_id}: " \
        "Score #{evaluation.score}/#{config[:score_max]}"
      )
    end
  end
end
