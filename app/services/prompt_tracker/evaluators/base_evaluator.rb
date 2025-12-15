# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Base class for automated evaluators.
    #
    # Automated evaluators analyze LLM responses using rule-based logic
    # and assign scores based on specific criteria.
    #
    # Subclasses should implement:
    # - #evaluate_score: Calculate the numeric score
    # - .metadata: Class method providing evaluator metadata (optional)
    #
    # @example Creating a custom evaluator
    #   class MyEvaluator < BaseEvaluator
    #     def self.metadata
    #       {
    #         name: "My Evaluator",
    #         description: "Evaluates response length",
    #         category: :custom,
    #         icon: "gear"
    #       }
    #     end
    #
    #     def evaluate_score
    #       response_text.length > 100 ? 100 : 50
    #     end
    #   end
    #
    class BaseEvaluator
      attr_reader :llm_response, :config

      # Class Methods for Parameter Schema

      # Define parameter schema for this evaluator
      # Subclasses should override to specify their parameters and types
      #
      # @return [Hash] parameter schema with keys as parameter names and values as type definitions
      # @example
      #   def self.param_schema
      #     {
      #       min_length: { type: :integer },
      #       max_length: { type: :integer },
      #       case_sensitive: { type: :boolean }
      #     }
      #   end
      def self.param_schema
        {}
      end

      # Process raw parameters from form based on schema
      # Converts parameter types according to the evaluator's param_schema
      #
      # @param raw_params [Hash, ActionController::Parameters] raw parameters from form
      # @return [Hash] processed parameters with correct types
      def self.process_params(raw_params)
        process_params_with_schema(raw_params, param_schema)
      end

      # Process raw parameters with a given schema
      # This is a helper method that can be used by evaluators that don't inherit from BaseEvaluator
      # @param raw_params [Hash, ActionController::Parameters] raw parameters from form
      # @param schema [Hash] parameter schema defining types
      # @return [Hash] processed parameters with correct types
      def self.process_params_with_schema(raw_params, schema)
        return {} if raw_params.blank?

        # Convert to hash if it's ActionController::Parameters
        params_hash = raw_params.is_a?(Hash) ? raw_params : raw_params.to_unsafe_h

        processed = {}

        params_hash.each do |key, value|
          key_sym = key.to_sym
          key_str = key.to_s
          param_def = schema[key_sym]

          processed[key_str] = if param_def
            convert_param(value, param_def[:type])
          else
            # Keep as-is if not in schema (allows for flexibility)
            value
          end
        end

        processed
      end

      # Convert a parameter value to the specified type
      #
      # @param value [Object] the raw value from the form
      # @param type [Symbol] the target type (:integer, :boolean, :array, :json, :string, :symbol)
      # @return [Object] the converted value
      def self.convert_param(value, type)
        case type
        when :integer
          value.to_i
        when :boolean
          # Handle various boolean representations from forms
          value == "true" || value == true || value == "1" || value == 1
        when :array
          # Convert textarea input (one per line) to array, or keep array as-is
          if value.is_a?(String)
            value.split("\n").map(&:strip).reject(&:blank?)
          elsif value.is_a?(Array)
            value.reject(&:blank?)
          else
            []
          end
        when :json
          # Parse JSON string, or keep hash as-is
          if value.present? && value.is_a?(String)
            begin
              JSON.parse(value)
            rescue JSON::ParserError => e
              Rails.logger.warn("Failed to parse JSON parameter: #{e.message}")
              nil
            end
          else
            value
          end
        when :string
          value.to_s
        when :symbol
          value.to_sym
        else
          # Unknown type, keep as-is
          value
        end
      end

      # Instance Methods

      # Initialize the evaluator
      #
      # @param llm_response [LlmResponse] the response to evaluate
      # @param config [Hash] optional configuration for the evaluator
      def initialize(llm_response, config = {})
        @llm_response = llm_response
        @config = config
      end

      # Evaluate the response and create an Evaluation record
      # All scores are 0-100
      #
      # @return [Evaluation] the created evaluation
      def evaluate
        score = evaluate_score
        feedback_text = generate_feedback

        Evaluation.create!(
          llm_response: llm_response,
          evaluator_type: self.class.name,
          evaluator_config_id: config[:evaluator_config_id],
          score: score,
          score_min: 0,
          score_max: 100,
          passed: passed?,
          feedback: feedback_text,
          metadata: metadata,
          evaluation_context: config[:evaluation_context] || "tracked_call",
          prompt_test_run_id: config[:prompt_test_run_id]
        )
      end

      # Calculate the overall score (0-100)
      # Subclasses should override this method
      #
      # @return [Numeric] the calculated score (0-100)
      def evaluate_score
        raise NotImplementedError, "Subclasses must implement #evaluate_score"
      end

      # Generate feedback text explaining the score
      # Subclasses can override this method
      #
      # @return [String, nil] feedback text
      def generate_feedback
        nil
      end

      # Get additional metadata for the evaluation
      # Subclasses can override this method
      #
      # @return [Hash] metadata hash
      def metadata
        { config: config }
      end

      # Determine if the evaluation passed
      # Default implementation: normalized score >= 0.8 (80%)
      # Subclasses can override this method for custom pass/fail logic
      #
      # @return [Boolean] true if evaluation passed
      def passed?
        normalized_score >= 0.8
      end

      protected

      # Calculate normalized score (0.0 to 1.0)
      #
      # @return [Float] normalized score
      def normalized_score
        return 0.0 if score_max == score_min

        score = evaluate_score
        (score - score_min) / (score_max - score_min).to_f
      end

      # Helper to get the response text
      #
      # @return [String] the response text
      def response_text
        llm_response.response_text || ""
      end

      # Helper to get the rendered prompt
      #
      # @return [String] the rendered prompt
      def rendered_prompt
        llm_response.rendered_prompt || ""
      end
    end
  end
end
