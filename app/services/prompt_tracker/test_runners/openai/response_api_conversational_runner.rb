# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      # Test runner for PromptVersion testables using Response API in conversational mode.
      #
      # This runner:
      # 1. Extracts test scenario from dataset row or custom variables
      # 2. Runs a multi-turn conversation using ResponseApiConversationRunner
      # 3. Runs evaluators on the conversation
      # 4. Updates the test run with results
      #
      # @example Run a conversational test
      #   runner = ResponseApiConversationalRunner.new(
      #     test_run: test_run,
      #     test: test,
      #     testable: prompt_version
      #   )
      #   runner.run
      #
      class ResponseApiConversationalRunner < Base
        # Execute the conversational test
        #
        # @return [void]
        def run
          start_time = Time.current

          # Extract test scenario from dataset row OR custom variables
          interlocutor_prompt, max_turns = extract_test_scenario

          # Get model configuration from prompt version
          model_config = testable.model_config.with_indifferent_access
          model = model_config[:model] || "gpt-4o"
          tools = extract_tools(model_config)

          # Render the system prompt with variables
          system_prompt = render_system_prompt

          # Run the conversation
          conversation_runner = PromptTracker::Openai::ResponseApiConversationRunner.new(
            model: model,
            system_prompt: system_prompt,
            interlocutor_simulation_prompt: interlocutor_prompt,
            max_turns: max_turns,
            tools: tools,
            temperature: model_config[:temperature] || 0.7
          )

          conversation_result = conversation_runner.run!

          # Build unified output_data structure
          output_data = {
            "rendered_prompt" => system_prompt,
            "model" => model,
            "provider" => "openai_responses",
            "messages" => conversation_result.messages,
            "total_turns" => conversation_result.total_turns,
            "status" => conversation_result.status,
            "tools_used" => tools.map(&:to_s),
            "previous_response_id" => conversation_result.previous_response_id,
            "metadata" => conversation_result.metadata
          }

          # Store in output_data
          test_run.update!(output_data: output_data)

          # Run evaluators
          evaluator_results = run_evaluators(output_data)

          # Calculate pass/fail
          passed = evaluator_results.all? { |r| r[:passed] }

          # Update test run
          execution_time = ((Time.current - start_time) * 1000).to_i
          update_test_run_results(
            passed: passed,
            execution_time_ms: execution_time,
            evaluator_results: evaluator_results,
            extra_metadata: {
              model: model,
              tools: tools,
              total_turns: conversation_result.total_turns
            }
          )
        end

        private

        # Extract test scenario from dataset row or custom variables
        #
        # @return [Array<String, Integer>] interlocutor_prompt and max_turns
        def extract_test_scenario
          vars = variables

          interlocutor_prompt = vars[:interlocutor_simulation_prompt]
          max_turns = vars[:max_turns] || 5

          if interlocutor_prompt.blank?
            raise ArgumentError, "interlocutor_simulation_prompt is required for conversational tests"
          end

          [ interlocutor_prompt, max_turns.to_i ]
        end

        # Extract tools from model config
        #
        # @param model_config [Hash] the model configuration
        # @return [Array<Symbol>] array of tool symbols
        def extract_tools(model_config)
          tools = model_config[:tools] || []
          tools.map(&:to_sym)
        end

        # Render the system prompt with variables
        #
        # @return [String] the rendered system prompt
        def render_system_prompt
          vars = variables.except(:interlocutor_simulation_prompt, :max_turns)

          # Use the prompt version's system prompt template
          # Fall back to user_prompt if system_prompt is not set
          template = testable.system_prompt.presence || testable.user_prompt

          # Simple variable substitution
          render_template(template, vars)
        end

        # Render a template with variables
        #
        # @param template [String] the template string
        # @param vars [Hash] the variables to substitute
        # @return [String] the rendered string
        def render_template(template, vars)
          return template if vars.empty?

          result = template.dup
          vars.each do |key, value|
            result.gsub!("{{#{key}}}", value.to_s)
            result.gsub!("{{ #{key} }}", value.to_s)
          end
          result
        end
      end
    end
  end
end
