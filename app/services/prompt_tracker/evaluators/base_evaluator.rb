# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Abstract base class for all automated evaluators.
    #
    # This class provides the core evaluation infrastructure:
    # - Creates Evaluation records (single responsibility)
    # - Defines the evaluator interface
    # - Provides parameter schema processing
    #
    # Do NOT inherit from this class directly. Instead, inherit from:
    # - SingleResponse::BaseSingleResponseEvaluator (for single-turn text evaluations)
    # - Conversational::BaseConversationalEvaluator (for multi-turn conversation evaluations)
    # - Conversational::BaseAssistantsApiEvaluator (for Assistants API-specific evaluations)
    #
    # Legacy aliases are available for backward compatibility:
    # - BaseChatCompletionEvaluator -> SingleResponse::BaseSingleResponseEvaluator
    # - BaseConversationalEvaluator -> Conversational::BaseConversationalEvaluator
    # - BaseAssistantsApiEvaluator -> Conversational::BaseAssistantsApiEvaluator
    #
    # Subclasses must implement:
    # - #evaluate_score: Calculate the numeric score (0-100)
    # - .api_type: Class method returning :chat_completion, :conversational, or :assistants_api
    # - .metadata: Class method providing evaluator metadata
    #
    # Subclasses can optionally override:
    # - #generate_feedback: Generate feedback text
    # - #metadata: Add custom metadata
    # - #passed?: Custom pass/fail logic
    #
    class BaseEvaluator
      attr_reader :config

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

      # Class Methods for API Type (Legacy - transitioning to compatible_with_apis)

      # Returns the API type this evaluator works with
      # @deprecated Use compatible_with_apis instead
      #
      # @return [Symbol] :chat_completion, :conversational, or :assistants_api
      def self.api_type
        raise NotImplementedError, "Subclasses must implement .api_type"
      end

      # Class Methods for API Compatibility (New V2 Architecture)

      # Returns which APIs this evaluator is compatible with.
      #
      # This is the new architecture for evaluator compatibility.
      # Subclasses should override this to specify which API types they support.
      # Use :all to indicate compatibility with all APIs.
      #
      # @return [Array<Symbol>] array of API type symbols from ApiTypes
      # @example
      #   def self.compatible_with_apis
      #     [ApiTypes::OPENAI_CHAT_COMPLETION, ApiTypes::OPENAI_RESPONSE_API]
      #   end
      #
      # @example All APIs
      #   def self.compatible_with_apis
      #     [:all]
      #   end
      def self.compatible_with_apis
        # Default: derive from legacy api_type for backward compatibility
        case api_type
        when :chat_completion
          [ ApiTypes::OPENAI_CHAT_COMPLETION, ApiTypes::ANTHROPIC_MESSAGES ]
        when :conversational
          [ ApiTypes::OPENAI_RESPONSE_API, ApiTypes::OPENAI_ASSISTANTS_API ]
        when :assistants_api
          [ ApiTypes::OPENAI_ASSISTANTS_API ]
        else
          [ :all ]
        end
      end

      # Check if evaluator is compatible with a specific API type
      #
      # @param api_type [Symbol] the API type to check
      # @return [Boolean] true if compatible
      def self.compatible_with_api?(api_type)
        compatible_with_apis.include?(api_type) || compatible_with_apis.include?(:all)
      end

      # Returns the evaluator category: :single_response or :conversational
      #
      # This determines whether the evaluator expects:
      # - :single_response - a single normalized response hash
      # - :conversational - a conversation with messages array
      #
      # @return [Symbol] :single_response or :conversational
      def self.category
        # Default: derive from legacy api_type for backward compatibility
        case api_type
        when :chat_completion
          :single_response
        else
          :conversational
        end
      end

      # Class Methods for Compatibility (Legacy - will be removed)

      # Returns array of testable classes this evaluator is compatible with
      # @deprecated Use compatible_with_apis instead
      #
      # @return [Array<Class>] array of compatible testable classes
      def self.compatible_with
        raise NotImplementedError, "Subclasses must implement .compatible_with"
      end

      # Check if this evaluator is compatible with a given testable
      # @deprecated Use compatible_with_api? instead
      #
      # @param testable [Object] the testable to check compatibility with
      # @return [Boolean] true if compatible
      def self.compatible_with?(testable)
        compatible_with.any? { |klass| testable.is_a?(klass) }
      end

      # Instance Methods

      # Initialize the evaluator
      # Subclasses should call super(config) after setting their own instance variables
      #
      # @param config [Hash] configuration for the evaluator
      def initialize(config = {})
        @config = config
      end

      # Evaluate and create an Evaluation record
      # This is the ONLY place where Evaluation.create! should be called
      # All scores are 0-100
      #
      # @return [Evaluation] the created evaluation
      def evaluate
        score = evaluate_score
        feedback_text = generate_feedback

        Evaluation.create!(
          llm_response: config[:llm_response],
          test_run: config[:test_run],
          evaluator_type: self.class.name,
          evaluator_config_id: config[:evaluator_config_id],
          score: score,
          score_min: 0,
          score_max: 100,
          passed: passed?,
          feedback: feedback_text,
          metadata: metadata,
          evaluation_context: config[:evaluation_context] || "tracked_call"
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

      private

      # Calculate normalized score (0.0 to 1.0)
      # Used by default #passed? implementation
      #
      # @return [Float] normalized score
      def normalized_score
        score = evaluate_score
        score / 100.0  # All scores are 0-100
      end

      # Score range helpers (for backward compatibility)
      def score_min
        0
      end

      def score_max
        100
      end
    end
  end
end
