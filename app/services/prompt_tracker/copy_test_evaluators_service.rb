# frozen_string_literal: true

module PromptTracker
  # Service for copying evaluator configurations from tests to monitoring.
  #
  # This service finds all evaluator_configs from all PromptTests for a given
  # PromptVersion and copies them to the PromptVersion's evaluator_configs
  # (for monitoring/auto-evaluation on tracked calls).
  #
  # @example Copy evaluators from tests to monitoring
  #   result = CopyTestEvaluatorsService.call(prompt_version: version)
  #   if result[:success]
  #     puts "Copied #{result[:copied_count]} evaluators"
  #   else
  #     puts "Error: #{result[:error]}"
  #   end
  #
  class CopyTestEvaluatorsService
    # Result object for service call
    Result = Struct.new(:success, :copied_count, :skipped_count, :error, keyword_init: true) do
      def success?
        success
      end
    end

    # Copy evaluator configs from tests to monitoring
    #
    # @param prompt_version [PromptVersion] the prompt version to copy evaluators to
    # @return [Result] result object with success status and counts
    def self.call(prompt_version:)
      new(prompt_version).call
    end

    attr_reader :prompt_version

    def initialize(prompt_version)
      @prompt_version = prompt_version
    end

    # Execute the copy operation
    #
    # @return [Result] result object with success status and counts
    def call
      copied_count = 0
      skipped_count = 0

      # Get all evaluator configs from all tests for this version
      test_evaluator_configs = collect_test_evaluator_configs

      # If no test evaluators found, return early
      if test_evaluator_configs.empty?
        return Result.new(
          success: true,
          copied_count: 0,
          skipped_count: 0,
          error: nil
        )
      end

      # Get existing monitoring evaluator types to avoid duplicates
      existing_evaluator_types = prompt_version.evaluator_configs.pluck(:evaluator_type)

      # Copy each unique evaluator config
      test_evaluator_configs.each do |test_config|
        # Skip if this evaluator type already exists in monitoring
        if existing_evaluator_types.include?(test_config.evaluator_type)
          skipped_count += 1
          next
        end

        # Create a copy for monitoring
        prompt_version.evaluator_configs.create!(
          evaluator_type: test_config.evaluator_type,
          config: test_config.config.deep_dup,
          enabled: true
        )

        copied_count += 1
        existing_evaluator_types << test_config.evaluator_type
      end

      Result.new(
        success: true,
        copied_count: copied_count,
        skipped_count: skipped_count,
        error: nil
      )
    rescue StandardError => e
      Rails.logger.error("Failed to copy test evaluators: #{e.message}")
      Result.new(
        success: false,
        copied_count: 0,
        skipped_count: 0,
        error: e.message
      )
    end

    private

    # Collect all unique evaluator configs from all tests
    #
    # @return [Array<EvaluatorConfig>] unique evaluator configs by evaluator_type
    def collect_test_evaluator_configs
      # Get all tests for this version
      tests = prompt_version.tests

      # Get all evaluator configs from all tests
      all_configs = tests.flat_map(&:evaluator_configs)

      # Return unique configs by evaluator_type (first occurrence wins)
      all_configs.uniq(&:evaluator_type)
    end
  end
end
