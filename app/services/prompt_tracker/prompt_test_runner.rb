# frozen_string_literal: true

module PromptTracker
  # Service for running a single prompt test.
  #
  # Executes a test by:
  # 1. Rendering the prompt with test variables
  # 2. Calling the LLM API (via provided block)
  # 3. Running configured evaluators (both binary and scored)
  # 4. Recording the result
  #
  # @example Run a test with a block
  #   runner = PromptTestRunner.new(test, version)
  #   test_run = runner.run! do |rendered_prompt|
  #     OpenAI::Client.new.chat(
  #       messages: [{ role: "user", content: rendered_prompt }],
  #       model: "gpt-4"
  #     )
  #   end
  #
  # @example Run a test with default LLM call
  #   runner = PromptTestRunner.new(test, version, metadata: { ci_run: true })
  #   test_run = runner.run!  # Uses model_config from test
  #
  class PromptTestRunner
    attr_reader :test, :prompt_version, :metadata, :test_run

    # Initialize the test runner
    #
    # @param test [Test] the test to run
    # @param prompt_version [PromptVersion] the version to test
    # @param metadata [Hash] additional metadata for the test run
    def initialize(test, prompt_version, metadata: {})
      @test = test
      @prompt_version = prompt_version
      @metadata = metadata || {}
      @test_run = nil
    end

    # Backward compatibility alias
    def prompt_test
      @test
    end

    # Run the test synchronously (for backward compatibility)
    #
    # @yield [rendered_prompt] optional block to execute LLM call
    # @yieldparam rendered_prompt [String] the rendered prompt
    # @yieldreturn [Object] the LLM response object
    # @return [TestRun] the test run result
    def run!(&block)
      start_time = Time.current
      # Create test run record
      @test_run = TestRun.create!(
        test: test,
        status: "running",
        metadata: metadata
      )

      # Execute the LLM call
      llm_response = execute_llm_call(&block)

      # Run evaluators
      evaluator_results = run_evaluators(llm_response)

      # Calculate pass/fail
      passed = determine_pass_fail(evaluator_results)

      # Update test run
      execution_time = ((Time.current - start_time) * 1000).to_i
      update_test_run_success(
        llm_response: llm_response,
        evaluator_results: evaluator_results,
        passed: passed,
        execution_time_ms: execution_time
      )

      @test_run.reload
    end

    # Run the test asynchronously (evaluators run in background)
    #
    # This method:
    # 1. Creates test run with "running" status
    # 2. Executes LLM call synchronously
    # 3. Enqueues background job to run evaluators
    # 4. Returns test run immediately (still in "running" state)
    #
    # @yield [rendered_prompt] optional block to execute LLM call
    # @yieldparam rendered_prompt [String] the rendered prompt
    # @yieldreturn [Object] the LLM response object
    # @return [TestRun] the test run result (in "running" state)
    def run_async!(&block)
      start_time = Time.current

      # Create test run record
      @test_run = TestRun.create!(
        test: test,
        status: "running",
        metadata: metadata.merge(async: true, started_at: start_time.iso8601)
      )

      # Execute the LLM call synchronously
      llm_response = execute_llm_call(&block)

      # Update test run with LLM response and execution time
      execution_time = ((Time.current - start_time) * 1000).to_i
      @test_run.update!(
        llm_response: llm_response,
        execution_time_ms: execution_time
      )

      # Enqueue background job to run evaluators
      RunEvaluatorsJob.perform_later(@test_run.id)

      @test_run
    end

    private

    # Execute the LLM call
    #
    # @yield [rendered_prompt] optional block to execute LLM call
    # @return [LlmResponse] the LLM response record
    def execute_llm_call(&block)
      # Render the template
      renderer = TemplateRenderer.new(prompt_version.template)
      rendered_prompt = renderer.render(prompt_test.template_variables)

      # Get model config from version (tests use the version's model config)
      model_config = prompt_version.model_config.with_indifferent_access
      provider = model_config[:provider] || "openai"
      model = model_config[:model] || "gpt-4"

      # If block provided, use it; otherwise use LlmCallService
      if block_given?
        # Call the provided block
        llm_api_response = block.call(rendered_prompt)

        # Extract token usage from response
        tokens = extract_token_usage(llm_api_response)

        # Create LlmResponse record manually
        llm_response = LlmResponse.create!(
          prompt_version: prompt_version,
          rendered_prompt: rendered_prompt,
          variables_used: prompt_test.template_variables,
          provider: provider,
          model: model,
          response_text: extract_response_text(llm_api_response),
          tokens_prompt: tokens[:prompt],
          tokens_completion: tokens[:completion],
          tokens_total: tokens[:total],
          status: "success",
          response_metadata: { test_run: true }
        )

        # Calculate and update cost
        if tokens[:total] && tokens[:total] > 0
          cost = calculate_cost(provider, model, tokens[:prompt], tokens[:completion])
          llm_response.update!(cost_usd: cost) if cost
        end

        llm_response
      else
        # Use LlmCallService (requires block in production)
        # For tests, we'll create a mock response
        raise NotImplementedError, "Block required for LLM call"
      end
    end

    # Run all configured evaluators
    #
    # @param llm_response [LlmResponse] the LLM response to evaluate
    # @return [Array<Hash>] array of evaluator results
    def run_evaluators(llm_response)
      # Get evaluator configs, ordered by priority
      evaluator_configs = prompt_test.evaluator_configs.enabled.order(priority: :desc)
      results = []

      evaluator_configs.each do |config|
        evaluator_type = config.evaluator_type
        evaluator_config = config.config || {}

        # Build evaluator from class name
        evaluator_class = evaluator_type.constantize
        evaluator = evaluator_class.new(llm_response, evaluator_config)

        # Check if this is an LLM judge evaluator that needs a block
        evaluation = if evaluator.is_a?(PromptTracker::Evaluators::LlmJudgeEvaluator)
          # Call with block to generate LLM judge response (real or mock)
          evaluator.evaluate do |judge_prompt|
            if use_real_llm?
              Rails.logger.info "🚀 Using REAL LLM Judge API"
              call_real_llm_judge(judge_prompt, evaluator_config)
            else
              Rails.logger.info "🎭 Using MOCK LLM Judge response"
              generate_mock_judge_response(judge_prompt, evaluator_config)
            end
          end
        else
          # Regular evaluators don't need a block
          evaluator.evaluate
        end

        # Get passed status from evaluation
        passed = evaluation.passed

        results << {
          evaluator_type: evaluator_type,
          score: evaluation.score,
          passed: passed,
          feedback: evaluation.feedback
        }
      end

      results
    end

    # Determine if test passed
    #
    # All evaluators (both binary and scored) must pass for the test to pass.
    # Binary evaluators are checked first (higher priority) and always run.
    # Scored evaluators must meet their threshold.
    #
    # @param evaluator_results [Array<Hash>] evaluator results
    # @return [Boolean] true if test passed
    def determine_pass_fail(evaluator_results)
      # All evaluators must pass (both binary and scored)
      evaluator_results.all? { |r| r[:passed] }
    end

    # Update test run with success
    #
    # @param llm_response [LlmResponse] the LLM response
    # @param evaluator_results [Array<Hash>] evaluator results
    # @param passed [Boolean] whether test passed
    # @param execution_time_ms [Integer] execution time in milliseconds
    def update_test_run_success(llm_response:, evaluator_results:, passed:, execution_time_ms:)
      passed_evaluators = evaluator_results.count { |r| r[:passed] }
      failed_evaluators = evaluator_results.count { |r| !r[:passed] }

      @test_run.update!(
        llm_response: llm_response,
        status: passed ? "passed" : "failed",
        passed: passed,
        evaluator_results: evaluator_results,
        passed_evaluators: passed_evaluators,
        failed_evaluators: failed_evaluators,
        total_evaluators: evaluator_results.length,
        execution_time_ms: execution_time_ms,
        cost_usd: llm_response.cost_usd
      )
    end

    # Update test run with error
    #
    # @param error [StandardError] the error that occurred
    # @param execution_time_ms [Integer] execution time in milliseconds
    def update_test_run_error(error, execution_time_ms)
      @test_run.update!(
        status: "error",
        passed: false,
        error_message: "#{error.class}: #{error.message}",
        execution_time_ms: execution_time_ms
      )
    end

    # Check if real LLM API calls should be used
    #
    # @return [Boolean] true if PROMPT_TRACKER_USE_REAL_LLM is set to 'true'
    def use_real_llm?
      ENV["PROMPT_TRACKER_USE_REAL_LLM"] == "true"
    end

    # Call real LLM API for judge evaluation
    #
    # @param judge_prompt [String] the prompt sent to the judge LLM
    # @param evaluator_config [Hash] the evaluator configuration
    # @return [String] judge response text
    def call_real_llm_judge(judge_prompt, evaluator_config)
      config = evaluator_config.with_indifferent_access
      judge_model = config[:judge_model] || "gpt-4"

      # Determine provider from model name
      provider = if judge_model.start_with?("gpt-", "o1-")
        "openai"
      elsif judge_model.start_with?("claude-")
        "anthropic"
      elsif judge_model.start_with?("gemini-")
        "google"
      else
        "openai" # Default to OpenAI
      end

      response = LlmClientService.call(
        provider: provider,
        model: judge_model,
        prompt: judge_prompt,
        temperature: 0.3 # Lower temperature for more consistent evaluations
      )

      response[:text]
    end

    # Generate a mock judge response for testing
    #
    # @param judge_prompt [String] the prompt sent to the judge LLM
    # @param evaluator_config [Hash] the evaluator configuration
    # @return [String] mock judge response with scores
    def generate_mock_judge_response(judge_prompt, evaluator_config)
      criteria = evaluator_config["criteria"] || evaluator_config[:criteria] || [ "overall" ]
      score_max = evaluator_config["score_max"] || evaluator_config[:score_max] || 100

      # Generate mock scores for each criterion (80-95% of max)
      criterion_scores = criteria.map do |criterion|
        score = rand(80..95) * score_max / 100.0
        "#{criterion}: #{score.round(1)}/#{score_max}"
      end.join("\n")

      # Calculate overall score (average of criteria)
      overall_score = (rand(80..95) * score_max / 100.0).round(1)

      # Return a structured response that the judge evaluator can parse
      <<~RESPONSE
        EVALUATION RESULTS:

        #{criterion_scores}

        Overall Score: #{overall_score}/#{score_max}

        Feedback: This is a mock evaluation for testing purposes. In production, this would be replaced with an actual LLM judge evaluation. The response meets the expected criteria and demonstrates good quality.

        Reasoning: The mock evaluator assigns high scores to simulate a passing test. In a real scenario, the LLM judge would analyze the response based on the specified criteria and provide detailed feedback.
      RESPONSE
    end

    # Extract response text from LLM API response
    #
    # @param llm_api_response [Object] the LLM API response
    # @return [String] the response text
    def extract_response_text(llm_api_response)
      # Handle different response formats
      if llm_api_response.is_a?(String)
        llm_api_response
      elsif llm_api_response.is_a?(RubyLLM::Message)
        # RubyLLM::Message object
        llm_api_response.content
      elsif llm_api_response.respond_to?(:dig)
        # OpenAI format
        llm_api_response.dig("choices", 0, "message", "content") ||
          llm_api_response.dig(:choices, 0, :message, :content) ||
          llm_api_response.to_s
      else
        llm_api_response.to_s
      end
    end

    # Extract token usage from LLM API response
    #
    # @param llm_api_response [Object] the LLM API response
    # @return [Hash] hash with :prompt, :completion, :total keys
    def extract_token_usage(llm_api_response)
      # Handle RubyLLM::Message
      if llm_api_response.is_a?(RubyLLM::Message)
        return {
          prompt: llm_api_response.input_tokens,
          completion: llm_api_response.output_tokens,
          total: (llm_api_response.input_tokens || 0) + (llm_api_response.output_tokens || 0)
        }
      end

      return { prompt: nil, completion: nil, total: nil } unless llm_api_response.respond_to?(:dig)

      # OpenAI format
      {
        prompt: llm_api_response.dig("usage", "prompt_tokens") || llm_api_response.dig(:usage, :prompt_tokens),
        completion: llm_api_response.dig("usage", "completion_tokens") || llm_api_response.dig(:usage, :completion_tokens),
        total: llm_api_response.dig("usage", "total_tokens") || llm_api_response.dig(:usage, :total_tokens)
      }
    end

    # Calculate cost based on provider, model, and token usage
    #
    # @param provider [String] the LLM provider
    # @param model [String] the model name
    # @param prompt_tokens [Integer] number of prompt tokens
    # @param completion_tokens [Integer] number of completion tokens
    # @return [Float, nil] cost in USD or nil if pricing not available
    def calculate_cost(provider, model, prompt_tokens, completion_tokens)
      return nil unless prompt_tokens && completion_tokens

      # Pricing per 1M tokens (as of 2024)
      pricing = case provider.to_s.downcase
      when "openai"
        case model.to_s.downcase
        when /gpt-4o/
          { prompt: 2.50, completion: 10.00 }  # GPT-4o: $2.50/$10 per 1M tokens
        when /gpt-4-turbo/, /gpt-4-1106/, /gpt-4-0125/
          { prompt: 10.00, completion: 30.00 }  # GPT-4 Turbo: $10/$30 per 1M tokens
        when /gpt-4-32k/
          { prompt: 60.00, completion: 120.00 }  # GPT-4 32K: $60/$120 per 1M tokens
        when /gpt-4/
          { prompt: 30.00, completion: 60.00 }  # GPT-4: $30/$60 per 1M tokens
        when /gpt-3.5-turbo/
          { prompt: 0.50, completion: 1.50 }  # GPT-3.5 Turbo: $0.50/$1.50 per 1M tokens
        else
          nil
        end
      when "anthropic"
        case model.to_s.downcase
        when /claude-3-opus/
          { prompt: 15.00, completion: 75.00 }  # Claude 3 Opus: $15/$75 per 1M tokens
        when /claude-3-sonnet/
          { prompt: 3.00, completion: 15.00 }  # Claude 3 Sonnet: $3/$15 per 1M tokens
        when /claude-3-haiku/
          { prompt: 0.25, completion: 1.25 }  # Claude 3 Haiku: $0.25/$1.25 per 1M tokens
        else
          nil
        end
      else
        nil
      end

      return nil unless pricing

      # Calculate cost: (tokens / 1,000,000) * price_per_million
      prompt_cost = (prompt_tokens / 1_000_000.0) * pricing[:prompt]
      completion_cost = (completion_tokens / 1_000_000.0) * pricing[:completion]

      prompt_cost + completion_cost
    end
  end
end
