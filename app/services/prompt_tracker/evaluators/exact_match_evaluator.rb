# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates LLM responses by checking if they exactly match expected text.
    #
    # This evaluator is designed for binary evaluation mode where responses
    # must exactly match a specific expected output to pass. It supports
    # options for case sensitivity and whitespace trimming.
    #
    # @example Case-insensitive match with trimming
    #   evaluator = ExactMatchEvaluator.new(response_text, {
    #     expected_text: "Hello World",
    #     case_sensitive: false,
    #     trim_whitespace: true
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Strict exact match
    #   evaluator = ExactMatchEvaluator.new(response_text, {
    #     expected_text: "Hello World",
    #     case_sensitive: true,
    #     trim_whitespace: false
    #   })
    #   evaluation = evaluator.evaluate
    #
    class ExactMatchEvaluator < BaseNormalizedEvaluator
      DEFAULT_CONFIG = {
        expected_text: "",      # The exact text to match
        case_sensitive: false,  # Whether matching is case-sensitive
        trim_whitespace: true   # Whether to trim whitespace before comparing
      }.freeze

      # Compatible API types
      def self.compatible_with_apis
        [ :openai_chat_completions, :anthropic_messages ]
      end

      # Parameter schema for form processing
      def self.param_schema
        {
          expected_text: { type: :string },
          case_sensitive: { type: :boolean },
          trim_whitespace: { type: :boolean }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Exact Match",
          description: "Checks if response exactly matches expected text (typically used in binary mode)",
          icon: "check-circle",
          default_config: DEFAULT_CONFIG
        }
      end

      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config))
      end

      def evaluate_score
        # For scored mode: return 100 if passed, 0 if failed
        passed? ? 100 : 0
      end

      def generate_feedback
        if passed?
          "✓ Response exactly matches expected output"
        else
          expected_preview = expected_normalized.length > 100 ? "#{expected_normalized[0..100]}..." : expected_normalized
          actual_preview = actual_normalized.length > 100 ? "#{actual_normalized[0..100]}..." : actual_normalized

          "✗ Response does not match expected output.\n\nExpected: \"#{expected_preview}\"\n\nActual: \"#{actual_preview}\""
        end
      end

      # For binary mode evaluation
      # @return [Boolean] true if evaluation passes
      def passed?
        expected_normalized == actual_normalized
      end

      private

      # Get the normalized expected text
      # @return [String] normalized expected text
      def expected_normalized
        normalize_text(config[:expected_text] || "")
      end

      # Get the normalized actual response text
      # @return [String] normalized actual text
      def actual_normalized
        normalize_text(response_text)
      end

      # Normalize text based on config options
      # @param text [String] the text to normalize
      # @return [String] normalized text
      def normalize_text(text)
        result = text.to_s
        result = result.strip if config[:trim_whitespace]
        result = result.downcase unless config[:case_sensitive]
        result
      end
    end
  end
end
