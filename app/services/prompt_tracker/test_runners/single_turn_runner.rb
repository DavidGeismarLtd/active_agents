# frozen_string_literal: true

module PromptTracker
  module TestRunners
    # Test runner for single-turn PromptVersion tests.
    #
    # This runner handles all single-turn tests regardless of provider
    # (OpenAI, Anthropic, OpenAI Responses API, etc.) by routing through
    # LlmClientService which handles provider-specific logic.
    #
    # Flow:
    # 1. Render the prompt template with variables from dataset row
    # 2. Call LLM via LlmClientService (handles all providers)
    # 3. Run evaluators on the response
    # 4. Update the test run with results
    #
    # @example Run a single-turn test
    #   runner = SingleTurnRunner.new(
    #     test_run: test_run,
    #     test: test,
    #     testable: prompt_version,
    #     use_real_llm: true
    #   )
    #   runner.run
    #
    class SingleTurnRunner < Base
      # Execute the single-turn test
      #
      # @return [void]
      def run
        start_time = Time.current

        # Get model configuration from prompt version
        model_config = testable.model_config&.with_indifferent_access || {}
        provider = model_config[:provider] || "openai"
        model = model_config[:model] || "gpt-4o"
        temperature = model_config[:temperature] || 0.7

        # Render the prompt with variables
        rendered_prompt = render_prompt

        # Call LLM
        llm_response = call_llm(
          provider: provider,
          model: model,
          rendered_prompt: rendered_prompt,
          temperature: temperature,
          model_config: model_config
        )

        # Create LlmResponse record and link to test run
        llm_response_record = create_llm_response_record(
          rendered_prompt: rendered_prompt,
          llm_response: llm_response,
          model: model,
          provider: provider
        )

        # Link LlmResponse to test run
        test_run.update!(llm_response: llm_response_record)

        # Run evaluators on response text
        evaluator_results = run_evaluators(llm_response[:text])

        # Calculate pass/fail
        passed = evaluator_results.empty? || evaluator_results.all? { |r| r[:passed] }

        # Update test run
        execution_time = ((Time.current - start_time) * 1000).to_i
        update_test_run_results(
          passed: passed,
          execution_time_ms: execution_time,
          evaluator_results: evaluator_results,
          extra_metadata: {
            provider: provider,
            model: model,
            rendered_prompt: rendered_prompt
          }
        )
      end

      private

      # Render the prompt template with variables
      #
      # @return [String] the rendered prompt
      def render_prompt
        testable.render(variables)
      end

      # Call the LLM via LlmClientService
      #
      # @param provider [String] the LLM provider
      # @param model [String] the model name
      # @param rendered_prompt [String] the rendered prompt
      # @param temperature [Float] the temperature
      # @param model_config [Hash] full model configuration
      # @return [Hash] LLM response with :text, :usage, :model, :raw keys
      def call_llm(provider:, model:, rendered_prompt:, temperature:, model_config:)
        if use_real_llm
          LlmClientService.call(
            provider: provider,
            model: model,
            prompt: rendered_prompt,
            system_prompt: testable.system_prompt,
            temperature: temperature,
            tools: model_config[:tools]
          )
        else
          # Mock response for testing
          {
            text: "Mock LLM response for testing",
            usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
            model: model,
            raw: {}
          }
        end
      end

      # Create an LlmResponse record
      #
      # @param rendered_prompt [String] the rendered prompt
      # @param llm_response [Hash] the LLM response
      # @param model [String] the model name
      # @param provider [String] the provider name
      # @return [LlmResponse] the created record
      def create_llm_response_record(rendered_prompt:, llm_response:, model:, provider:)
        LlmResponse.create!(
          prompt_version: testable,
          rendered_prompt: rendered_prompt,
          response_text: llm_response[:text],
          tokens_prompt: llm_response.dig(:usage, :prompt_tokens),
          tokens_completion: llm_response.dig(:usage, :completion_tokens),
          response_time_ms: 0, # Will be updated by test run
          model: model,
          provider: provider,
          status: "success",
          is_test_run: true,
          response_metadata: {
            test_run_id: test_run.id
          }
        )
      end
    end
  end
end
