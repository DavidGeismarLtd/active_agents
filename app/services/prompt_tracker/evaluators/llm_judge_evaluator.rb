# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Uses an LLM to evaluate another LLM's response.
    #
    # This evaluator sends the original prompt and response to a "judge" LLM
    # and asks it to score the response based on custom instructions.
    #
    # @example Evaluate with custom instructions
    #   evaluator = LlmJudgeEvaluator.new(llm_response, {
    #     judge_model: "gpt-4o",
    #     custom_instructions: "Evaluate if the response is helpful and professional"
    #   })
    #   evaluation = evaluator.evaluate  # Uses RubyLLM with structured outputs
    #
    # @example Custom evaluation with specific focus
    #   evaluator = LlmJudgeEvaluator.new(llm_response, {
    #     judge_model: "claude-3-5-sonnet-20241022",
    #     custom_instructions: "Focus on technical correctness for a senior developer audience"
    #   })
    #   evaluation = evaluator.evaluate
    #
    class LlmJudgeEvaluator
      attr_reader :llm_response, :config

      # Default configuration
      # Note: Using gpt-4o because it supports structured outputs
      # gpt-4 (non-turbo) does NOT support structured outputs
      DEFAULT_CONFIG = {
        judge_model: "gpt-4o",
        custom_instructions: "Evaluate the quality and appropriateness of the response"
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          judge_model: { type: :string },
          custom_instructions: { type: :string },
          threshold_score: { type: :integer }
        }
      end

      # Process raw parameters from form based on schema
      # Delegates to BaseEvaluator for consistency
      def self.process_params(raw_params)
        BaseEvaluator.process_params_with_schema(raw_params, param_schema)
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "LLM Judge",
          description: "Uses an LLM to evaluate response quality based on custom instructions",
          icon: "robot",
          default_config: DEFAULT_CONFIG
        }
      end

      def initialize(llm_response, config = {})
        @llm_response = llm_response
        # Convert string keys to symbol keys to ensure proper merging with DEFAULT_CONFIG
        # Use symbolize_keys to handle nested hashes and ensure clean merge
        symbolized_config = config.is_a?(Hash) ? config.deep_symbolize_keys : {}
        @config = DEFAULT_CONFIG.merge(symbolized_config)
      end

      # Evaluate the response using an LLM judge with structured output
      #
      # This method uses RubyLLM with structured schemas to guarantee valid JSON responses.
      # No more regex parsing or fragile text extraction!
      #
      # @return [Evaluation] the created evaluation
      #
      # @example Evaluate with RubyLLM (automatic)
      #   evaluation = evaluator.evaluate
      #
      def evaluate
        # Generate the evaluation prompt
        judge_prompt = build_judge_prompt

        # Check if we should use mock mode
        if use_mock_mode?
          parsed = generate_mock_evaluation
        else
          # Build RubyLLM schema for structured output
          schema = build_schema

          # Call the judge LLM with structured output
          chat = RubyLLM.chat(model: config[:judge_model]).with_schema(schema)
          response = chat.ask(judge_prompt)

          # Response content is already a structured hash!
          # Convert to hash with indifferent access to handle both string and symbol keys
          parsed = response.content.with_indifferent_access
        end

        # Calculate if passed (score >= threshold, default 70)
        score = parsed[:overall_score]
        threshold = config[:threshold_score] || 70
        passed = score >= threshold

        # Create the evaluation
        Evaluation.create!(
          llm_response: llm_response,
          evaluator_type: self.class.name,
          evaluator_config_id: config[:evaluator_config_id],
          score: score,
          score_min: 0,
          score_max: 100,
          passed: passed,
          feedback: parsed[:feedback],
          evaluation_context: config[:evaluation_context] || "tracked_call",
          prompt_test_run_id: config[:prompt_test_run_id],
          metadata: {
            judge_model: config[:judge_model],
            custom_instructions: config[:custom_instructions],
            judge_prompt: judge_prompt,
            raw_judge_response: use_mock_mode? ? "MOCK_RESPONSE" : response.raw.to_s,
            used_structured_output: true,
            mock_mode: use_mock_mode?,
            threshold_score: threshold
          }
        )
      end

      private

      # Build RubyLLM schema for structured output
      #
      # @return [Class] a RubyLLM::Schema subclass
      def build_schema
        LlmJudgeSchema.simple_schema
      end

      # Build the prompt to send to the judge LLM
      #
      # @return [String] the evaluation prompt
      def build_judge_prompt
        <<~PROMPT
          You are an expert evaluator of AI-generated responses. Please evaluate the following LLM response.

          ORIGINAL PROMPT:
          #{llm_response.rendered_prompt}

          LLM RESPONSE TO EVALUATE:
          #{llm_response.response_text}

          EVALUATION INSTRUCTIONS:
          #{config[:custom_instructions]}

          Please provide your evaluation with:
          - overall_score: A number from 0 to 100
          - feedback: Detailed explanation of your score

          Your response will be automatically structured as JSON.
        PROMPT
      end

      # Check if we should use mock mode
      #
      # @return [Boolean] true if mock mode is enabled
      def use_mock_mode?
        ENV["PROMPT_TRACKER_USE_REAL_LLM"] != "true"
      end

      # Generate a mock evaluation for testing
      #
      # @return [Hash] mock evaluation data
      def generate_mock_evaluation
        # Generate realistic mock scores (0-100)
        overall_score = rand(0..100)

        {
          overall_score: overall_score,
          feedback: "MOCK EVALUATION: This is a simulated evaluation. In production, this would be generated by #{config[:judge_model]}."
        }
      end
    end
  end
end
