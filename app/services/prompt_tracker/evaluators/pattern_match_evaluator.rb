# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates LLM responses by checking if they match regex patterns.
    #
    # This evaluator is designed for binary evaluation mode where responses
    # must match specific patterns to pass. It can be configured to require
    # all patterns to match or just any pattern.
    #
    # @example Require all patterns to match
    #   evaluator = PatternMatchEvaluator.new(response_text, {
    #     patterns: ["/Hello/", "/world/i"],
    #     match_all: true
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Require any pattern to match
    #   evaluator = PatternMatchEvaluator.new(response_text, {
    #     patterns: ["/greeting/i", "/hello/i", "/hi/i"],
    #     match_all: false
    #   })
    #   evaluation = evaluator.evaluate
    #
    class PatternMatchEvaluator < BaseEvaluator
      DEFAULT_CONFIG = {
        patterns: [],      # Array of regex pattern strings (e.g., ["/Hello/", "/world/i"])
        match_all: true    # true = all must match, false = any must match
      }.freeze

      # Compatible API types
      def self.compatible_with_apis
        [ :openai_chat_completions, :anthropic_messages ]
      end

      # Parameter schema for form processing
      def self.param_schema
        {
          patterns: { type: :array },
          match_all: { type: :boolean }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Pattern Match",
          description: "Checks if response matches regex patterns (typically used in binary mode)",
          icon: "regex",
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
        return "⚠ No patterns configured" if patterns.empty?

        matched_patterns = []
        failed_patterns = []

        patterns.each do |pattern_str|
          pattern = parse_pattern(pattern_str)
          if response_text.match?(pattern)
            matched_patterns << pattern_str
          else
            failed_patterns << pattern_str
          end
        end

        if failed_patterns.empty?
          "✓ All #{patterns.length} pattern#{patterns.length > 1 ? 's' : ''} matched successfully"
        elsif config[:match_all]
          "✗ Failed to match #{failed_patterns.length} pattern#{failed_patterns.length > 1 ? 's' : ''}: #{failed_patterns.join(', ')}"
        else
          "✗ No patterns matched. Tried: #{patterns.join(', ')}"
        end
      end

      # For binary mode evaluation
      # @return [Boolean] true if evaluation passes
      def passed?
        if config[:match_all]
          all_patterns_match?
        else
          any_pattern_matches?
        end
      end

      private

      # Get the list of patterns from config
      # @return [Array<String>] array of pattern strings
      def patterns
        Array(config[:patterns])
      end

      # Parse a pattern string into a Regexp
      # Supports formats: "/pattern/flags" or plain "pattern"
      # @param pattern_str [String] the pattern string
      # @return [Regexp] the compiled regex
      def parse_pattern(pattern_str)
        # Check if pattern is in /pattern/flags format
        if pattern_str =~ %r{\A/(.*)/([imx]*)\z}
          pattern_body = ::Regexp.last_match(1)
          flags_str = ::Regexp.last_match(2)

          # Convert flags string to Regexp options
          flags = 0
          flags |= Regexp::IGNORECASE if flags_str.include?("i")
          flags |= Regexp::MULTILINE if flags_str.include?("m")
          flags |= Regexp::EXTENDED if flags_str.include?("x")

          Regexp.new(pattern_body, flags)
        else
          # Plain string - treat as literal pattern
          Regexp.new(Regexp.escape(pattern_str))
        end
      end

      # Check if all patterns match
      # @return [Boolean] true if all patterns match
      def all_patterns_match?
        return false if patterns.empty?

        patterns.all? do |pattern_str|
          pattern = parse_pattern(pattern_str)
          response_text.match?(pattern)
        end
      end

      # Check if any pattern matches
      # @return [Boolean] true if at least one pattern matches
      def any_pattern_matches?
        return false if patterns.empty?

        patterns.any? do |pattern_str|
          pattern = parse_pattern(pattern_str)
          response_text.match?(pattern)
        end
      end
    end
  end
end
