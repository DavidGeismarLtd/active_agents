# frozen_string_literal: true

module PromptTracker
  module TestRunners
    class AgentVersionRunner < Base
      def run
        start_time = Time.current
        execution_params = build_execution_params
        executor = build_api_executor

        Rails.logger.info "[AgentVersionRunner] Step 1: Executing LLM call..."
        output_data = executor.execute(execution_params)
        Rails.logger.info "[AgentVersionRunner] Step 1: DONE"

        test_run.update!(output_data: output_data)

        Rails.logger.info "[AgentVersionRunner] Step 2: Running evaluators..."
        evaluator_results = run_evaluators(output_data)
        Rails.logger.info "[AgentVersionRunner] Step 2: DONE"

        passed = evaluator_results.empty? || evaluator_results.all? { |r| r[:passed] }

        Rails.logger.info "[AgentVersionRunner] Step 3: Calculating cost..."
        cost = calculate_cost(output_data)
        Rails.logger.info "[AgentVersionRunner] Step 3: DONE"

        execution_time = ((Time.current - start_time) * 1000).to_i
        Rails.logger.info "[AgentVersionRunner] Step 4: Updating results..."
        update_test_run_results(
          passed: passed,
          execution_time_ms: execution_time,
          evaluator_results: evaluator_results,
          cost_usd: cost
        )
        Rails.logger.info "[AgentVersionRunner] Step 4: DONE"
      end

      private

      def build_execution_params
        if conversational_mode?
          build_conversational_params
        else
          build_single_turn_params
        end
      end

      def build_single_turn_params
        vars = variables
        first_message = render_prompt.presence || vars[:first_user_message]
        {
          system_prompt: testable.system_prompt,
          max_turns: 1,
          interlocutor_prompt: nil,
          first_user_message: first_message,
          mock_function_outputs: vars[:mock_function_outputs]
        }
      end

      def build_conversational_params
        vars = variables
        interlocutor_prompt = vars[:interlocutor_simulation_prompt]
        max_turns = vars[:max_turns] || 5
        if interlocutor_prompt.blank?
          raise ArgumentError, "interlocutor_simulation_prompt is required"
        end
        first_message = render_prompt
        {
          system_prompt: render_system_prompt,
          max_turns: max_turns.to_i,
          interlocutor_prompt: interlocutor_prompt,
          first_user_message: first_message,
          mock_function_outputs: vars[:mock_function_outputs]
        }
      end

      def conversational_mode?
        variables[:interlocutor_simulation_prompt].present?
      end

      def build_api_executor
        ConversationTestHandlerFactory.build(
          model_config: model_config,
          use_real_llm: use_real_llm,
          testable: testable
        )
      end

      def model_config
        @model_config ||= testable.model_config&.with_indifferent_access || {}
      end

      def render_prompt
        testable.render(variables)
      end

      def render_system_prompt
        vars = variables.except(:interlocutor_simulation_prompt, :max_turns)
        template = testable.system_prompt.presence || testable.user_prompt
        render_template(template, vars)
      end

      def render_template(template, vars)
        return template if vars.empty? || template.blank?
        result = template.dup
        vars.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
          result.gsub!("{{ #{key} }}", value.to_s)
        end
        result
      end

      def calculate_cost(output_data)
        return nil unless use_real_llm
        tokens = output_data["tokens"]
        return nil unless tokens
        prompt_tokens = tokens["prompt_tokens"]
        completion_tokens = tokens["completion_tokens"]
        return nil unless prompt_tokens && completion_tokens
        model_name = output_data["model"] || model_config["model"]
        return nil unless model_name
        LlmClients::RubyLlmService.with_dynamic_config do |_llm|
          model_info = RubyLLM.models.find(model_name)
          return nil unless model_info
          input_price = model_info.input_price_per_million
          output_price = model_info.output_price_per_million
          return nil unless input_price && output_price
          (prompt_tokens * input_price / 1_000_000.0) +
            (completion_tokens * output_price / 1_000_000.0)
        end
      end
    end
  end
end
