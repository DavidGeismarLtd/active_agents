# frozen_string_literal: true

module PromptTracker
  # Service for automatically evaluating LLM responses.
  #
  # This service runs when a new LLM response is created and executes
  # all enabled evaluators configured for the prompt. It handles:
  # - Running independent evaluators first
  # - Running dependent evaluators only if dependencies are met
  # - Executing sync evaluators immediately
  # - Scheduling async evaluators as background jobs
  #
  # @example Manually trigger auto-evaluation
  #   AutoEvaluationService.evaluate(llm_response)
  #
  # @example Auto-evaluation is triggered automatically
  #   # When a response is created, after_create callback triggers evaluation
  #   response = LlmResponse.create!(...)
  #   # AutoEvaluationService.evaluate(response) is called automatically
  #
  class AutoEvaluationService
    # Evaluates a response using all configured evaluators
    #
    # @param llm_response [LlmResponse] the response to evaluate
    # @param context [String] evaluation context: 'tracked_call', 'test_run', or 'manual'
    # @return [void]
    def self.evaluate(llm_response, context: "tracked_call")
      new(llm_response, context: context).evaluate
    end

    # Initialize the service
    #
    # @param llm_response [LlmResponse] the response to evaluate
    # @param context [String] evaluation context
    def initialize(llm_response, context: "tracked_call")
      @llm_response = llm_response
      @prompt_version = llm_response.prompt_version
      @evaluation_context = context
    end

    # Runs all configured evaluators for this response
    #
    # @return [void]
    def evaluate
      return unless @prompt_version

      # Run all enabled evaluators in order
      @prompt_version.evaluator_configs.enabled.order(:created_at).each do |config|
        run_evaluation(config)
      end
    end

    private

    # Runs a single evaluator
    #
    # @param config [EvaluatorConfig] the evaluator configuration
    # @return [void]
    def run_evaluation(config)
      evaluator = config.build_evaluator(@llm_response)
      result = evaluator.evaluate

      create_evaluation(config, result)
    rescue StandardError => e
      Rails.logger.error("Auto-evaluation failed for #{config.evaluator_key}: #{e.message}")
    end

    # Creates an evaluation record from evaluator result
    #
    # @param config [EvaluatorConfig] the evaluator configuration
    # @param evaluation [Evaluation] the evaluation record created by the evaluator
    # @return [void]
    def create_evaluation(config, evaluation)
      # The evaluator already created the evaluation via EvaluationService
      # Just update metadata with context and config reference
      evaluation.update!(
        evaluation_context: @evaluation_context,
        metadata: (evaluation.metadata || {}).merge(
          evaluator_config_id: config.id
        )
      )
    end
  end
end
