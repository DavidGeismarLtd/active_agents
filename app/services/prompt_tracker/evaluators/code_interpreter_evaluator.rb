# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates whether the model properly used code interpreter during a response.
    #
    # This evaluator checks if code was executed, optionally verifying language,
    # execution success, output patterns, and file creation.
    #
    # @example Verify code interpreter was used
    #   evaluator = CodeInterpreterEvaluator.new(conversation_data, {
    #     require_code_execution: true,
    #     require_successful_execution: true
    #   })
    #   evaluation = evaluator.evaluate
    #
    # @example Verify output matches expected patterns
    #   evaluator = CodeInterpreterEvaluator.new(conversation_data, {
    #     output_patterns: ["mean", "std"],
    #     expected_language: "python"
    #   })
    #
    class CodeInterpreterEvaluator < BaseEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        require_code_execution: true,      # Must execute code at least once
        expected_language: nil,             # Optional: "python", "javascript", etc.
        require_successful_execution: true, # Execution must complete without error
        output_patterns: [],                # Regex patterns the output should match
        require_all_patterns: false,        # If true, ALL patterns must match
        expect_files_created: false,        # Should create files
        min_code_lines: 0,                  # Minimum lines of code executed
        threshold_score: 80
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          require_code_execution: { type: :boolean },
          expected_language: { type: :string },
          require_successful_execution: { type: :boolean },
          output_patterns: { type: :array },
          require_all_patterns: { type: :boolean },
          expect_files_created: { type: :boolean },
          min_code_lines: { type: :integer },
          threshold_score: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "Code Interpreter",
          description: "Verifies that the model executed code and optionally checks output/files",
          icon: "code",
          default_config: DEFAULT_CONFIG,
          category: :tool_use
        }
      end

      # Initialize the evaluator
      #
      # @param data [Hash] the normalized data with code_interpreter_results
      # @param config [Hash] configuration options
      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      # Calculate score based on code interpreter usage
      #
      # @return [Float] score from 0-100
      def evaluate_score
        return 100 unless config[:require_code_execution]
        return 0 if code_interpreter_results.empty?

        score_components = []

        # Base score for using code interpreter (30 points)
        score_components << 30

        # Score for successful execution (20 points)
        if config[:require_successful_execution]
          score_components << (all_executions_successful? ? 20 : 0)
        else
          score_components << 20
        end

        # Score for language match (15 points)
        if config[:expected_language].present?
          score_components << (language_matches? ? 15 : 0)
        else
          score_components << 15
        end

        # Score for output patterns (20 points)
        if output_patterns.any?
          pattern_score = calculate_pattern_match_score
          score_components << (pattern_score * 0.2)
        else
          score_components << 20
        end

        # Score for files created (10 points)
        if config[:expect_files_created]
          score_components << (any_files_created? ? 10 : 0)
        else
          score_components << 10
        end

        # Score for minimum code lines (5 points)
        if config[:min_code_lines].to_i > 0
          score_components << (meets_min_code_lines? ? 5 : 0)
        else
          score_components << 5
        end

        score_components.sum.round(2)
      end

      # Generate feedback about code interpreter results
      #
      # @return [String] feedback text
      def generate_feedback
        if code_interpreter_results.empty?
          return config[:require_code_execution] ? "✗ Code interpreter was not used." : "Code interpreter was not used (not required)."
        end

        feedback_parts = [
          "Code Interpreter Evaluation Results:",
          "Executions: #{code_interpreter_results.count}",
          "Languages: #{all_languages.uniq.join(', ').presence || 'Unknown'}",
          "Total code lines: #{total_code_lines}"
        ]

        feedback_parts << "Successful: #{successful_executions.count}/#{code_interpreter_results.count}"

        if config[:expected_language].present?
          feedback_parts << "Expected language: #{config[:expected_language]} (#{language_matches? ? 'matched' : 'not matched'})"
        end

        if output_patterns.any?
          matched = matched_patterns
          feedback_parts << "Output patterns matched: #{matched.count}/#{output_patterns.count}"
        end

        if config[:expect_files_created]
          feedback_parts << "Files created: #{all_files_created.count}"
        end

        feedback_parts << (passed? ? "✓ Code interpreter requirements met." : "✗ Some requirements not met.")
        feedback_parts.join("\n")
      end

      # Add metadata about code interpreter details
      #
      # @return [Hash] metadata
      def metadata
        super.merge(
          "execution_count" => code_interpreter_results.count,
          "successful_count" => successful_executions.count,
          "languages" => all_languages.uniq,
          "total_code_lines" => total_code_lines,
          "files_created" => all_files_created,
          "matched_patterns" => matched_patterns,
          "expected_language" => config[:expected_language],
          "output_patterns" => output_patterns
        )
      end

      # Determine if evaluation passed
      #
      # @return [Boolean] true if requirements met
      def passed?
        evaluate_score >= (config[:threshold_score] || 80)
      end

      private

      # Get output patterns from config
      #
      # @return [Array<String>] output patterns to match
      def output_patterns
        @output_patterns ||= Array(config[:output_patterns]).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      # Get all languages from code interpreter results
      #
      # @return [Array<String>] languages used
      def all_languages
        @all_languages ||= code_interpreter_results.filter_map { |ci| ci[:language] }
      end

      # Get all code outputs concatenated
      #
      # @return [String] all outputs combined
      def all_outputs
        @all_outputs ||= code_interpreter_results.filter_map { |ci| ci[:output] }.join("\n")
      end

      # Get all code executed
      #
      # @return [Array<String>] all code snippets
      def all_code
        @all_code ||= code_interpreter_results.filter_map { |ci| ci[:code] }
      end

      # Get all files created
      #
      # @return [Array<String>] file identifiers
      def all_files_created
        @all_files_created ||= code_interpreter_results.flat_map { |ci| ci[:files_created] || [] }
      end

      # Get successful executions (no error)
      #
      # @return [Array<Hash>] successful execution results
      def successful_executions
        @successful_executions ||= code_interpreter_results.select do |ci|
          (ci[:status] == "completed" || ci[:status].nil?) && ci[:error].nil?
        end
      end

      # Check if all executions were successful
      #
      # @return [Boolean] true if all successful
      def all_executions_successful?
        successful_executions.count == code_interpreter_results.count
      end

      # Check if expected language was used
      #
      # @return [Boolean] true if language matches
      def language_matches?
        expected = config[:expected_language]&.downcase
        return true if expected.nil?

        all_languages.any? { |lang| lang&.downcase == expected }
      end

      # Check if any files were created
      #
      # @return [Boolean] true if files created
      def any_files_created?
        all_files_created.any?
      end

      # Check if minimum code lines requirement is met
      #
      # @return [Boolean] true if met
      def meets_min_code_lines?
        total_code_lines >= config[:min_code_lines].to_i
      end

      # Calculate total lines of code executed
      #
      # @return [Integer] total lines
      def total_code_lines
        @total_code_lines ||= all_code.sum { |code| code.to_s.lines.count }
      end

      # Find which output patterns were matched
      #
      # @return [Array<String>] matched patterns
      def matched_patterns
        @matched_patterns ||= output_patterns.select do |pattern|
          pattern_matches_output?(pattern)
        end
      end

      # Check if a pattern matches the output
      #
      # @param pattern [String] the pattern (regex or string)
      # @return [Boolean] true if matches
      def pattern_matches_output?(pattern)
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        all_outputs.match?(regex)
      rescue RegexpError
        # Fall back to simple string match if invalid regex
        all_outputs.downcase.include?(pattern.downcase)
      end

      # Calculate score for pattern matching
      #
      # @return [Float] score 0-100
      def calculate_pattern_match_score
        return 100 if output_patterns.empty?

        matched_count = matched_patterns.count
        total_count = output_patterns.count

        if config[:require_all_patterns]
          matched_count == total_count ? 100 : (matched_count.to_f / total_count * 100)
        else
          matched_count > 0 ? 100 : 0
        end
      end
    end
  end
end
