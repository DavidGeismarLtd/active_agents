# frozen_string_literal: true

module PromptTracker
  module TestRunners
    # Unified test runner for PromptVersion testables.
    #
    # This runner handles both single-turn and conversational tests by:
    # 1. Determining execution mode from test.conversational?
    # 2. Building execution parameters based on mode
    # 3. Routing to appropriate API executor based on provider
    # 4. Running evaluators on the output
    # 5. Updating test run with results
    #
    # Single-turn mode:
    # - Renders prompt template with variables
    # - Makes one LLM call
    # - Evaluates the response
    #
    # Conversational mode:
    # - Uses interlocutor simulation prompt
    # - Runs multi-turn conversation
    # - Evaluates the full conversation
    #
    # @example Run a single-turn test
    #   runner = PromptVersionRunner.new(
    #     test_run: test_run,
    #     test: test,
    #     testable: prompt_version,
    #     use_real_llm: true
    #   )
    #   runner.run
    #
    class PromptVersionRunner < Base
        # Execute the test
        #
        # @return [void]
        def run
          start_time = Time.current

          # Build execution parameters based on execution mode
          execution_params = build_execution_params

          # Get appropriate executor for this provider
          executor = build_api_executor

          # Execute and get output_data
          output_data = executor.execute(execution_params)

          # Store output
          test_run.update!(output_data: output_data)

          # Run evaluators
          evaluated_data = conversational_mode? ? output_data : output_data.dig("messages", 0, "content")
          evaluator_results = run_evaluators(evaluated_data)

        # Calculate pass/fail
        passed = evaluator_results.empty? || evaluator_results.all? { |r| r[:passed] }

        # Calculate cost
        cost = calculate_cost(output_data)

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

        # Build execution parameters based on execution mode.
        #
        # Execution mode is primarily driven by the TestRun metadata
        # ("execution_mode" key). If not present, it falls back to the
        # Test model's conversational? predicate for backward compatibility.
        #
        # @return [Hash] execution parameters for the executor
        def build_execution_params
          if conversational_mode?
            build_conversational_params
          else
            build_single_turn_params
          end
        end

      # Build parameters for single-turn execution
      #
      # @return [Hash] single-turn execution params
      def build_single_turn_params
        {
          mode: :single_turn,
          system_prompt: testable.system_prompt,
          max_turns: 1,
          interlocutor_prompt: nil,
          first_user_message: render_prompt
        }
      end

        # Build parameters for conversational execution
        #
        # @return [Hash] conversational execution params
        def build_conversational_params
          vars = variables
          interlocutor_prompt = vars[:interlocutor_simulation_prompt]
          max_turns = vars[:max_turns] || 5

          if interlocutor_prompt.blank?
            raise ArgumentError, "interlocutor_simulation_prompt is required for conversational tests"
          end

          {
            mode: :conversational,
            system_prompt: render_system_prompt,
            max_turns: max_turns.to_i,
            interlocutor_prompt: interlocutor_prompt,
            first_user_message: render_prompt
          }
        end

        # Determine if this run should use conversational mode.
        #
        # Priority:
        # 1. TestRun.metadata["execution_mode"] when present ("conversation" / "single")
        # 2. Fallback to Test#conversational? for legacy callers
        #
        # @return [Boolean]
        def conversational_mode?
          mode = test_run.metadata && test_run.metadata["execution_mode"]
          return test.conversational? if mode.blank?

          mode.to_s == "conversation" || mode.to_s == "conversational"
        end

      # Build the appropriate API executor based on provider
      #
      # @return [ApiExecutors::Base] the executor instance
      def build_api_executor
        provider = model_config[:provider] || "openai"

        executor_class = case provider.to_s
        when "openai_responses"
          ApiExecutors::Openai::ResponseApiExecutor
        else
          # All other providers (openai, anthropic, google, etc.) use completion API
          ApiExecutors::CompletionApiExecutor
        end

        executor_class.new(
          model_config: model_config,
          use_real_llm: use_real_llm,
          testable: testable
        )
      end

      # Get model configuration from testable
      #
      # @return [HashWithIndifferentAccess] model config
      def model_config
        @model_config ||= testable.model_config&.with_indifferent_access || {}
      end

      # Render the prompt template with variables
      #
      # @return [String] the rendered prompt
      def render_prompt
        testable.render(variables)
      end

      # Render the system prompt with variables (for conversational mode)
      #
      # @return [String] the rendered system prompt
      def render_system_prompt
        vars = variables.except(:interlocutor_simulation_prompt, :max_turns)
        template = testable.system_prompt.presence || testable.user_prompt
        render_template(template, vars)
      end

      # Render a template with variable substitution
      #
      # @param template [String] the template string
      # @param vars [Hash] the variables to substitute
      # @return [String] the rendered string
      def render_template(template, vars)
        return template if vars.empty? || template.blank?

        result = template.dup
        vars.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
          result.gsub!("{{ #{key} }}", value.to_s)
        end
        result
      end

      # Calculate cost from output_data
      #
      # @param output_data [Hash] the output data with token info
      # @return [BigDecimal, nil] the calculated cost or nil
      def calculate_cost(output_data)
        return nil unless use_real_llm

        tokens = output_data["tokens"]
        return nil unless tokens

        prompt_tokens = tokens["prompt_tokens"]
        completion_tokens = tokens["completion_tokens"]
        return nil unless prompt_tokens && completion_tokens

        model_name = output_data["model"] || model_config[:model]
        return nil unless model_name

        model_info = RubyLLM.models.find(model_name)
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
