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

        # Calculate response time
        response_time_ms = ((Time.current - start_time) * 1000).to_i

        # Calculate cost
        prompt_tokens = llm_response.dig(:usage, :prompt_tokens)
        completion_tokens = llm_response.dig(:usage, :completion_tokens)
        cost = calculate_cost(model, prompt_tokens, completion_tokens)

        # Store output in output_data (unified format)
        output_data = {
          "rendered_prompt" => rendered_prompt,
          "model" => model,
          "provider" => provider,
          "messages" => [
            { "role" => "assistant", "content" => llm_response[:text] }
          ],
          "tokens" => {
            "prompt_tokens" => prompt_tokens,
            "completion_tokens" => completion_tokens,
            "total_tokens" => llm_response.dig(:usage, :total_tokens)
          },
          "response_time_ms" => response_time_ms,
          "status" => "completed"
        }

        test_run.update!(output_data: output_data)

        # Run evaluators on response text
        evaluator_results = run_evaluators(llm_response[:text])

        # Calculate pass/fail
        passed = evaluator_results.empty? || evaluator_results.all? { |r| r[:passed] }

        # Update test run with final results
        execution_time = ((Time.current - start_time) * 1000).to_i
        update_test_run_results(
          passed: passed,
          execution_time_ms: execution_time,
          evaluator_results: evaluator_results,
          cost_usd: cost
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

      # Calculate cost using RubyLLM model registry
      #
      # @param model [String] the model name
      # @param prompt_tokens [Integer] number of input tokens
      # @param completion_tokens [Integer] number of output tokens
      # @return [BigDecimal, nil] the calculated cost or nil if pricing unavailable
      def calculate_cost(model, prompt_tokens, completion_tokens)
        return nil unless use_real_llm && prompt_tokens && completion_tokens

        model_info = RubyLLM.models.find(model)
        return nil unless model_info

        input_price = model_info.input_price_per_million
        output_price = model_info.output_price_per_million
        return nil unless input_price && output_price

        input_cost = (prompt_tokens * input_price / 1_000_000.0)
        output_cost = (completion_tokens * output_price / 1_000_000.0)
        input_cost + output_cost
      end
    end
  end
end
