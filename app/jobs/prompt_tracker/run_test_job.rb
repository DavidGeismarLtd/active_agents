# frozen_string_literal: true

module PromptTracker
  # Background job to run a single test (prompt version or assistant).
  #
  # This job:
  # 1. Loads an existing TestRun (created by controller with "running" status)
  # 2. Detects test type (prompt version or assistant)
  # 3. Routes to appropriate runner (PromptTestRunner or AssistantTestRunner)
  # 4. Executes the test
  # 5. Updates the test run with results
  # 6. Broadcasts completion via Turbo Streams
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

      # Route to appropriate runner based on testable type
      if testable.is_a?(PromptVersion)
        run_prompt_test(test_run, test, testable, use_real_llm)
      elsif testable.is_a?(Openai::Assistant)
        run_assistant_test(test_run, test, testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end

      Rails.logger.info "✅ RunTestJob completed for test_run #{test_run_id}"
    end

    private

    # Run a prompt version test
    #
    # @param test_run [TestRun] the test run
    # @param test [Test] the test
    # @param version [PromptVersion] the prompt version
    # @param use_real_llm [Boolean] whether to use real LLM API
    def run_prompt_test(test_run, test, version, use_real_llm)
      start_time = Time.current

      llm_response = execute_llm_call(test, version, test_run, use_real_llm)

      # Run evaluators
      evaluator_results = run_evaluators(test, llm_response, test_run)

      # Determine if test passed (all evaluators must pass)
      passed = evaluator_results.all? { |r| r[:passed] }

      # Calculate execution time
      execution_time = ((Time.current - start_time) * 1000).to_i

      # Update test run with results
      update_test_run_success(
        test_run: test_run,
        llm_response: llm_response,
        evaluator_results: evaluator_results,
        passed: passed,
        execution_time_ms: execution_time
      )
    end

    # Run an assistant test
    #
    # @param test_run [TestRun] the test run
    # @param test [Test] the test
    # @param assistant [Openai::Assistant] the assistant
    def run_assistant_test(test_run, test, assistant)
      # Assistant tests can run with either dataset_row or custom_variables
      start_time = Time.current

      # Extract test scenario from dataset row OR custom variables
      if test_run.dataset_row.present?
        # Dataset mode: extract from dataset row
        row_data = test_run.dataset_row.row_data.with_indifferent_access
        interlocutor_prompt = row_data[:interlocutor_simulation_prompt] || row_data["interlocutor_simulation_prompt"]
        max_turns = row_data[:max_turns] || row_data["max_turns"] || 5
      elsif test_run.metadata.dig("custom_variables").present?
        # Custom mode: extract from metadata
        custom_vars = test_run.metadata["custom_variables"].with_indifferent_access
        interlocutor_prompt = custom_vars[:user_prompt] || custom_vars["user_prompt"]
        max_turns = custom_vars[:max_turns] || custom_vars["max_turns"] || 3
      else
        raise ArgumentError, "Assistant test requires either dataset_row or custom_variables"
      end

      raise ArgumentError, "interlocutor_simulation_prompt is required" if interlocutor_prompt.blank?

      # Run the conversation
      conversation_runner = Openai::ConversationRunner.new(
        assistant_id: assistant.assistant_id,
        interlocutor_simulation_prompt: interlocutor_prompt,
        max_turns: max_turns
      )

      conversation_result = conversation_runner.run!

      # Store conversation data
      test_run.update!(conversation_data: conversation_result)

      # Run evaluators
      evaluator_results = run_assistant_evaluators(test, test_run)

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

    # Execute the LLM call
    #
    # @param test [PromptTest] the test to run
    # @param version [PromptVersion] the version to test
    # @param test_run [PromptTestRun] the test run (contains dataset_row if applicable)
    # @param use_real_llm [Boolean] whether to use real LLM API
    # @return [LlmResponse] the LLM response record
    def execute_llm_call(test, version, test_run, use_real_llm)
      # Determine which variables to use
      template_vars = determine_template_variables(test_run)

      # Render the user_prompt with variables
      renderer = TemplateRenderer.new(version.user_prompt)
      rendered_prompt = renderer.render(template_vars)

      # Get model config from version (tests use the version's model config)
      model_config = version.model_config.with_indifferent_access
      provider = model_config[:provider] || "openai"
      model = model_config[:model] || "gpt-4"

      # Call LLM (real or mock) with timing
      start_time = Time.current
      if use_real_llm
        llm_api_response = call_real_llm(rendered_prompt, model_config)
      else
        llm_api_response = generate_mock_llm_response(rendered_prompt, model_config)
      end
      response_time_ms = ((Time.current - start_time) * 1000).round

      # Extract token usage and response text
      tokens = extract_token_usage(llm_api_response)
      response_text = extract_response_text(llm_api_response)

      # Calculate cost using RubyLLM's model registry
      cost = calculate_cost_from_response(llm_api_response)

      # Create LlmResponse record (marked as test run to skip auto-evaluation)
      llm_response = LlmResponse.create!(
        prompt_version: version,
        rendered_prompt: rendered_prompt,
        variables_used: template_vars,
        provider: provider,
        model: model,
        response_text: response_text,
        response_time_ms: response_time_ms,
        tokens_prompt: tokens[:prompt],
        tokens_completion: tokens[:completion],
        tokens_total: tokens[:total],
        cost_usd: cost,
        status: "success",
        is_test_run: true,
        response_metadata: { test_run: true }
      )

      llm_response
    end

    # Determine which template variables to use for this test run
    #
    # @param test_run [TestRun] the test run
    # @return [Hash] the template variables to use
    def determine_template_variables(test_run)
      if test_run.dataset_row.present?
        # Use dataset row data
        test_run.dataset_row.row_data
      elsif test_run.metadata["custom_variables"].present?
        # Use custom variables from modal (for single runs)
        test_run.metadata["custom_variables"]
      else
        # Fallback to empty hash (no variables)
        {}
      end
    end

    # Call real LLM API
    #
    # @param rendered_prompt [String] the rendered prompt
    # @param model_config [Hash] the model configuration
    # @return [RubyLLM::Message] LLM API response
    def call_real_llm(rendered_prompt, model_config)
      config = model_config.with_indifferent_access
      provider = config[:provider] || "openai"
      model = config[:model] || "gpt-4"
      temperature = config[:temperature] || 0.7
      max_tokens = config[:max_tokens]

      Rails.logger.info "🔧 Calling REAL LLM: #{provider}/#{model}"

      LlmClientService.call(
        provider: provider,
        model: model,
        prompt: rendered_prompt,
        temperature: temperature,
        max_tokens: max_tokens
      )[:raw] # Return raw RubyLLM::Message
    end

    # Generate a mock LLM response for testing
    #
    # @param rendered_prompt [String] the rendered prompt
    # @param model_config [Hash] the model configuration
    # @return [Hash] mock LLM response in OpenAI format
    def generate_mock_llm_response(rendered_prompt, model_config)
      provider = model_config["provider"] || model_config[:provider] || "openai"

      Rails.logger.info "🎭 Generating MOCK LLM response for #{provider}"

      # Generate a realistic mock response based on the prompt
      mock_text = "This is a mock response to: #{rendered_prompt.truncate(100)}\n\n"
      mock_text += "In a production environment, this would be replaced with an actual API call to #{provider}.\n"
      mock_text += "The response would be generated by the configured model and would address the prompt appropriately."

      # Return in OpenAI-like format for compatibility
      {
        "choices" => [
          {
            "message" => {
              "content" => mock_text
            }
          }
        ]
      }
    end

    # Run evaluators for prompt tests
    #
    # @param test [Test] the test
    # @param llm_response [LlmResponse] the LLM response to evaluate
    # @param test_run [TestRun] the test run to associate evaluations with
    # @return [Array<Hash>] array of evaluator results
    def run_evaluators(test, llm_response, test_run)
      evaluator_configs = test.evaluator_configs.enabled.order(:created_at)
      results = []

      evaluator_configs.each do |config|
        evaluator_key = config.evaluator_key.to_sym
        evaluator_config = config.config || {}

        # Add test_run context to evaluator config
        evaluator_config = evaluator_config.merge(
          evaluation_context: "test_run",
          test_run_id: test_run.id
        )

        # Build and run evaluator
        evaluator = EvaluatorRegistry.build(evaluator_key, llm_response, evaluator_config)

        # All evaluators now use RubyLLM directly - no block needed!
        # Evaluation is created with correct context and test_run association
        evaluation = evaluator.evaluate

        results << {
          evaluator_key: evaluator_key.to_s,
          score: evaluation.score,
          passed: evaluation.passed,
          feedback: evaluation.feedback
        }
      end

      results
    end

    # Run evaluators for assistant tests
    #
    # @param test [Test] the test
    # @param test_run [TestRun] the test run with conversation_data
    # @return [Array<Hash>] array of evaluator results
    def run_assistant_evaluators(test, test_run)
      evaluator_configs = test.evaluator_configs.enabled.order(:created_at)
      results = []

      evaluator_configs.each do |config|
        evaluator_type = config.evaluator_type
        evaluator_config = config.config || {}

        # Add evaluator_config_id to the config
        evaluator_config = evaluator_config.merge(
          evaluator_config_id: config.id,
          evaluation_context: "test_run"
        )

        # Build and run the evaluator
        evaluator_class = evaluator_type.constantize
        evaluator = evaluator_class.new(test_run, evaluator_config)
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

    # Update test run with success
    #
    # @param test_run [PromptTestRun] the test run to update
    # @param llm_response [LlmResponse] the LLM response
    # @param evaluator_results [Array<Hash>] evaluator results
    # @param passed [Boolean] whether test passed
    # @param execution_time_ms [Integer] execution time in milliseconds
    def update_test_run_success(test_run:, llm_response:, evaluator_results:, passed:, execution_time_ms:)
      passed_evaluators = evaluator_results.count { |r| r[:passed] }
      failed_evaluators = evaluator_results.count { |r| !r[:passed] }

      test_run.update!(
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

    # Broadcast Turbo Stream updates when test completes

    # Extract response text from LLM API response
    #
    # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
    # @return [String] the response text
    def extract_response_text(llm_api_response)
      # Real LLM returns RubyLLM::Message
      return llm_api_response.content if llm_api_response.respond_to?(:content)

      # Mock LLM returns Hash
      llm_api_response.dig("choices", 0, "message", "content") ||
        llm_api_response.dig(:choices, 0, :message, :content) ||
        llm_api_response.to_s
    end

    # Extract token usage from LLM API response
    #
    # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
    # @return [Hash] hash with :prompt, :completion, :total keys
    def extract_token_usage(llm_api_response)
      # Real LLM returns RubyLLM::Message
      if llm_api_response.respond_to?(:input_tokens)
        return {
          prompt: llm_api_response.input_tokens,
          completion: llm_api_response.output_tokens,
          total: (llm_api_response.input_tokens || 0) + (llm_api_response.output_tokens || 0)
        }
      end

      # Mock LLM returns Hash (no token usage)
      { prompt: nil, completion: nil, total: nil }
    end

    # Calculate cost using RubyLLM's model registry
    #
    # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
    # @return [Float, nil] cost in USD or nil if pricing not available
    def calculate_cost_from_response(llm_api_response)
      # Mock LLM responses don't have token info
      return nil unless llm_api_response.respond_to?(:input_tokens)
      return nil unless llm_api_response.input_tokens && llm_api_response.output_tokens

      # Use RubyLLM's model registry to get pricing information
      model_info = RubyLLM.models.find(llm_api_response.model_id)
      return nil unless model_info&.input_price_per_million && model_info&.output_price_per_million

      # Calculate cost: (tokens / 1,000,000) * price_per_million
      input_cost = llm_api_response.input_tokens * model_info.input_price_per_million / 1_000_000.0
      output_cost = llm_api_response.output_tokens * model_info.output_price_per_million / 1_000_000.0

      input_cost + output_cost
    end
  end
end
