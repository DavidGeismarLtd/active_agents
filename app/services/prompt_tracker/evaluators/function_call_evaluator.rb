# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates if the assistant called expected functions during a conversation.
    #
    # This evaluator checks conversation_data for tool_calls and validates that
    # the expected functions were invoked, optionally checking arguments.
    #
    # @example Check if a specific function was called
    #   evaluator = FunctionCallEvaluator.new(conversation_data, {
    #     expected_functions: ["get_weather"],
    #     require_all: true
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Check if any of several functions was called
    #   evaluator = FunctionCallEvaluator.new(conversation_data, {
    #     expected_functions: ["get_weather", "get_forecast"],
    #     require_all: false  # Pass if ANY function is called
    #   })
    #
    class FunctionCallEvaluator < BaseNormalizedEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        expected_functions: [],      # Array of function names that should be called
        require_all: true,           # If true, ALL functions must be called. If false, ANY.
        check_arguments: false,      # If true, also validate function arguments
        expected_arguments: {},      # Map of function_name => expected arguments hash
        threshold_score: 80          # Score threshold for passing
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          expected_functions: { type: :array },
          require_all: { type: :boolean },
          check_arguments: { type: :boolean },
          expected_arguments: { type: :json },
          threshold_score: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Function Call",
          description: "Checks if the assistant called expected functions during the conversation",
          icon: "gear",
          default_config: DEFAULT_CONFIG,
          category: :conversation
        }
      end

      # Initialize the evaluator
      #
      # @param data [Hash] the normalized data with messages array
      # @param config [Hash] configuration options
      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      # Calculate score based on function calls
      #
      # @return [Integer] score from 0-100
      def evaluate_score
        return 100 if expected_functions.empty?

        matched_functions = matching_functions

        if config[:require_all]
          # Score based on percentage of expected functions called (with matching args if enabled)
          (matched_functions.length.to_f / expected_functions.length * 100).round
        else
          # Pass (100) if ANY expected function was called, otherwise 0
          matched_functions.any? ? 100 : 0
        end
      end

      # Generate feedback explaining the evaluation result
      #
      # @return [String] feedback text
      def generate_feedback
        called = extract_called_functions
        expected = expected_functions
        matched = matching_functions
        arg_failures = argument_failures

        if expected.empty?
          "No expected functions specified - evaluation passed by default."
        elsif config[:require_all]
          missing = expected - matched
          if missing.empty?
            "✓ All expected functions were called: #{expected.join(', ')}"
          else
            feedback = "✗ Missing function calls: #{missing.join(', ')}. " \
                       "Called: #{called.empty? ? 'none' : called.join(', ')}"
            if arg_failures.any?
              feedback += ". Argument mismatches: #{arg_failures.join('; ')}"
            end
            feedback
          end
        else
          if matched.any?
            "✓ Expected function(s) called: #{matched.join(', ')}"
          else
            feedback = "✗ None of the expected functions were called. " \
                       "Expected one of: #{expected.join(', ')}. " \
                       "Called: #{called.empty? ? 'none' : called.join(', ')}"
            if arg_failures.any?
              feedback += ". Argument mismatches: #{arg_failures.join('; ')}"
            end
            feedback
          end
        end
      end

      # Add metadata about function calls
      #
      # @return [Hash] metadata
      def metadata
        called = extract_called_functions
        super.merge(
          "expected_functions" => expected_functions,
          "called_functions" => called,
          "matched_functions" => matching_functions,
          "require_all" => config[:require_all],
          "check_arguments" => config[:check_arguments],
          "argument_failures" => argument_failures,
          "threshold" => config[:threshold_score] || 80,
          "all_tool_calls" => extract_all_tool_calls
        )
      end

      # Custom pass/fail logic based on threshold
      #
      # @return [Boolean] true if score >= threshold
      def passed?
        threshold = config[:threshold_score] || 80
        evaluate_score >= threshold
      end

      private

      # Get expected functions from config
      #
      # @return [Array<String>] array of function names
      def expected_functions
        Array(config[:expected_functions]).map(&:to_s)
      end

      # Get expected arguments from config
      #
      # @return [Hash] map of function_name => expected arguments
      def expected_arguments
        args = config[:expected_arguments] || {}
        return {} unless args.is_a?(Hash)

        args.transform_keys(&:to_s)
      end

      # NOTE: messages is now inherited from BaseConversationalEvaluator

      # Extract all function names that were called during the conversation
      #
      # @return [Array<String>] unique function names that were called
      def extract_called_functions
        extract_all_tool_calls.map { |tc| tc[:function_name] }.compact.uniq
      end

      # Find expected functions that were called and (optionally) have matching arguments
      #
      # @return [Array<String>] function names that match expectations
      def matching_functions
        @matching_functions ||= begin
          called = extract_called_functions

          if config[:check_arguments]
            # Only count functions that have matching arguments
            expected_functions.select do |func_name|
              next false unless called.include?(func_name)

              # If no expected arguments for this function, just check it was called
              func_expected_args = expected_arguments[func_name]
              next true if func_expected_args.nil? || func_expected_args.empty?

              # Check if any call to this function has matching arguments
              function_calls_with_args(func_name).any? do |actual_args|
                arguments_match?(func_expected_args, actual_args)
              end
            end
          else
            # Just check function names without argument validation
            expected_functions.select { |f| called.include?(f) }
          end
        end
      end

      # Get argument failures for reporting
      #
      # @return [Array<String>] descriptions of argument mismatches
      def argument_failures
        return [] unless config[:check_arguments]

        @argument_failures ||= begin
          failures = []
          called = extract_called_functions

          expected_functions.each do |func_name|
            next unless called.include?(func_name)

            func_expected_args = expected_arguments[func_name]
            next if func_expected_args.nil? || func_expected_args.empty?

            # Check if any call matches
            calls = function_calls_with_args(func_name)
            next if calls.any? { |actual| arguments_match?(func_expected_args, actual) }

            # No matching call found
            failures << "#{func_name}: expected #{func_expected_args.inspect}, got #{calls.first&.inspect || 'no args'}"
          end

          failures
        end
      end

      # Get all argument hashes for calls to a specific function
      #
      # @param func_name [String] function name
      # @return [Array<Hash>] array of argument hashes
      def function_calls_with_args(func_name)
        extract_all_tool_calls
          .select { |tc| tc[:function_name] == func_name }
          .map { |tc| tc[:arguments] || {} }
      end

      # Check if expected arguments are a subset of actual arguments
      #
      # @param expected [Hash] expected arguments
      # @param actual [Hash] actual arguments from the call
      # @return [Boolean] true if all expected key-values are present in actual
      def arguments_match?(expected, actual)
        return true if expected.nil? || expected.empty?
        return false if actual.nil?

        expected.all? do |key, expected_value|
          actual_value = actual[key.to_s] || actual[key.to_sym]
          if expected_value.is_a?(Hash) && actual_value.is_a?(Hash)
            arguments_match?(expected_value, actual_value)
          else
            actual_value.to_s == expected_value.to_s
          end
        end
      end

      # Extract all tool calls from the conversation
      #
      # Handles two different data structures:
      # 1. Nested structure (Chat Completions API): {id:, type:, function: {name:, arguments:}}
      # 2. Flat structure (Response API): {id:, type:, function_name:, arguments:}
      #
      # @return [Array<Hash>] array of tool call details
      def extract_all_tool_calls
        @all_tool_calls ||= messages.flat_map do |msg|
          tool_calls = msg["tool_calls"] || msg[:tool_calls] || []
          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type],
              # Try flat structure first (Response API), then nested structure (Chat Completions)
              function_name: tc["function_name"] || tc[:function_name] ||
                             tc.dig("function", "name") || tc.dig(:function, :name),
              # Try flat structure first (Response API), then nested structure (Chat Completions)
              arguments: parse_arguments(
                tc["arguments"] || tc[:arguments] ||
                tc.dig("function", "arguments") || tc.dig(:function, :arguments)
              )
            }
          end
        end
      end

      # Parse function arguments (may be JSON string or hash)
      #
      # @param arguments [String, Hash, nil] the arguments
      # @return [Hash, nil] parsed arguments
      def parse_arguments(arguments)
        return nil if arguments.nil?
        return arguments if arguments.is_a?(Hash)

        JSON.parse(arguments)
      rescue JSON::ParserError
        { raw: arguments }
      end
    end
  end
end
