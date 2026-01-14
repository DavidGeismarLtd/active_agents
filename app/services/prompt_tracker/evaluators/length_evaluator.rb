# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates response based on length criteria.
    #
    # Scores responses based on whether they fall within expected length ranges.
    # Useful for ensuring responses are not too short or too long.
    #
    # @example Evaluate with default config
    #   evaluator = LengthEvaluator.new(response_text)
    #   evaluation = evaluator.evaluate
    #
    # @example Evaluate with custom length ranges
    #   evaluator = LengthEvaluator.new(response_text, {
    #     min_length: 50,
    #     max_length: 500
    #   })
    #   evaluation = evaluator.evaluate
    #
    class LengthEvaluator < BaseNormalizedEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        min_length: 10,      # Minimum acceptable length
        max_length: 2000     # Maximum acceptable length
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          min_length: { type: :integer },
          max_length: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Length Validator",
          description: "Validates response length against min/max ranges",
          icon: "rulers",
          default_config: DEFAULT_CONFIG
        }
      end

      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config))
      end

      def evaluate_score
        length = response_text.length

        # Within acceptable range: pass (100)
        if length >= config[:min_length] && length <= config[:max_length]
          return 100
        end

        # Outside acceptable range: fail (0)
        0
      end

      def generate_feedback
        length = response_text.length

        if length < config[:min_length]
          "Response is too short (#{length} chars). Minimum: #{config[:min_length]} chars."
        elsif length > config[:max_length]
          "Response is too long (#{length} chars). Maximum: #{config[:max_length]} chars."
        else
          "Response length is acceptable (#{length} chars). Range: #{config[:min_length]}-#{config[:max_length]} chars."
        end
      end

      def metadata
        super.merge(
          response_length: response_text.length,
          min_length: config[:min_length],
          max_length: config[:max_length]
        )
      end

      # Pass if length is within acceptable range (min to max)
      def passed?
        length = response_text.length
        length >= config[:min_length] && length <= config[:max_length]
      end
    end
  end
end
