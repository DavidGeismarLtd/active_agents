# frozen_string_literal: true

module PromptTracker
  module Evaluators
    # Evaluates whether an OpenAI Assistant used file_search on specified files.
    #
    # This evaluator checks if the assistant searched within the expected files
    # during a conversation by analyzing the run_steps captured during execution.
    #
    # @example Evaluate file search usage
    #   evaluator = FileSearchEvaluator.new(conversation_data, {
    #     expected_files: ["policy.pdf", "guidelines.txt"],
    #     require_all: true,
    #     threshold_score: 100
    #   })
    #   evaluation = evaluator.evaluate
    #
    class FileSearchEvaluator < BaseNormalizedEvaluator
      # Default configuration
      DEFAULT_CONFIG = {
        expected_files: [],
        require_all: true,
        threshold_score: 100
      }.freeze

      # Parameter schema for form processing
      def self.param_schema
        {
          expected_files: { type: :array },
          require_all: { type: :boolean },
          threshold_score: { type: :integer }
        }
      end

      # Metadata for registry auto-discovery
      def self.metadata
        {
          name: "File Search",
          description: "Verifies that the assistant searched within expected files",
          icon: "file-search",
          default_config: DEFAULT_CONFIG,
          category: :assistant
        }
      end

      # Initialize the evaluator
      #
      # @param data [Hash] the normalized data with file_search_results
      # @param config [Hash] configuration options
      def initialize(data, config = {})
        super(data, DEFAULT_CONFIG.merge(config.symbolize_keys))
      end

      # Returns compatible API types - only Assistants API has file_search
      #
      # @return [Array<Symbol>] array containing only Assistants API
      def self.compatible_with_apis
        [ :openai_assistants ]
      end

      # Calculate score based on file search matching
      #
      # @return [Float] score from 0-100
      def evaluate_score
        return 0 if expected_files.empty?
        return 0 if file_search_results.empty?

        matched_files = find_matched_files
        match_percentage = (matched_files.count.to_f / expected_files.count) * 100

        match_percentage.round(2)
      end

      # Generate feedback about file search results
      #
      # @return [String] feedback text
      def generate_feedback
        if expected_files.empty?
          return "No expected files configured for evaluation."
        end

        matched = find_matched_files
        unmatched = expected_files - matched
        searched = searched_file_names

        feedback_parts = [
          "File Search Evaluation Results:",
          "Expected files: #{expected_files.join(', ')}",
          "Files searched: #{searched.any? ? searched.join(', ') : 'None'}",
          "Matched files: #{matched.any? ? matched.join(', ') : 'None'}"
        ]

        if unmatched.any?
          feedback_parts << "Missing files: #{unmatched.join(', ')}"
        end

        if passed?
          feedback_parts << "✓ All required files were searched."
        else
          feedback_parts << "✗ Some expected files were not searched."
        end

        feedback_parts.join("\n")
      end

      # Add metadata about file search details
      #
      # @return [Hash] metadata
      def metadata
        super.merge(
          "expected_files" => expected_files,
          "matched_files" => find_matched_files,
          "searched_files" => searched_file_names,
          "file_search_calls" => file_search_results.count,
          "require_all" => config[:require_all]
        )
      end

      # Determine if evaluation passed based on configuration
      #
      # @return [Boolean] true if requirements met
      def passed?
        return true if expected_files.empty?

        matched = find_matched_files

        if config[:require_all]
          matched.count == expected_files.count
        else
          matched.any?
        end
      end

      private

      # Get expected files from config
      #
      # @return [Array<String>] expected file names or patterns
      def expected_files
        @expected_files ||= Array(config[:expected_files]).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      # Override to use the base class file_search_results accessor
      # which already handles the normalized data format

      # Extract all searched file names from results
      #
      # @return [Array<String>] unique file names that were searched
      def searched_file_names
        @searched_file_names ||= begin
          file_search_results.flat_map do |fs_call|
            results = fs_call[:results] || []
            results.map { |r| r["file_name"] || r[:file_name] }
          end.compact.uniq
        end
      end

      # Find which expected files were actually searched
      #
      # @return [Array<String>] matched file names
      def find_matched_files
        @matched_files ||= expected_files.select do |expected|
          searched_file_names.any? { |searched| file_matches?(searched, expected) }
        end
      end

      # Check if a searched file matches an expected file pattern
      #
      # @param searched [String] the actual file name searched
      # @param expected [String] the expected file name or pattern
      # @return [Boolean] true if match
      def file_matches?(searched, expected)
        return false if searched.nil? || expected.nil?

        # Exact match
        return true if searched == expected

        # Case-insensitive match
        return true if searched.downcase == expected.downcase

        # Partial match (expected is substring of searched)
        return true if searched.downcase.include?(expected.downcase)

        # Pattern match with wildcards (simple glob-style)
        if expected.include?("*")
          pattern = Regexp.new(expected.gsub("*", ".*"), Regexp::IGNORECASE)
          return true if searched.match?(pattern)
        end

        false
      end
    end
  end
end
