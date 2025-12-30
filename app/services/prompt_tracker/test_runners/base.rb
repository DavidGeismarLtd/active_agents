# frozen_string_literal: true

module PromptTracker
  module TestRunners
    # Base class for all test runners.
    #
    # Test runners are responsible for executing tests for different testable types
    # (PromptVersion, Openai::Assistant, etc.). Each testable type has its own runner
    # that inherits from this base class.
    #
    # The job routes to the appropriate runner based on the testable type using
    # convention-based naming:
    # - PromptVersion → PromptTracker::TestRunners::PromptVersionRunner
    # - Openai::Assistant → PromptTracker::TestRunners::Openai::AssistantRunner
    #
    # @example Create a custom runner
    #   class MyCustomRunner < Base
    #     def run
    #       # Your custom test execution logic
    #       update_test_run_success(
    #         test_run: test_run,
    #         passed: true,
    #         execution_time_ms: 100
    #       )
    #     end
    #   end
    #
    class Base
      attr_reader :test_run, :test, :testable, :options

      # Initialize a new test runner
      #
      # @param test_run [TestRun] the test run to execute
      # @param test [Test] the test being run
      # @param testable [Object] the testable object (PromptVersion, Assistant, etc.)
      # @param options [Hash] additional options (e.g., use_real_llm)
      def initialize(test_run:, test:, testable:, **options)
        @test_run = test_run
        @test = test
        @testable = testable
        @options = options
      end

      # Execute the test run
      #
      # This method must be implemented by subclasses
      #
      # @return [void]
      # @raise [NotImplementedError] if not implemented by subclass
      def run
        raise NotImplementedError, "#{self.class.name} must implement #run"
      end

      protected

      # Determine which template variables to use for this test run
      #
      # @return [Hash] the template variables to use
      def determine_template_variables
        if test_run.dataset_row.present?
          # Use dataset row data
          test_run.dataset_row.row_data
        elsif test_run.metadata["custom_variables"].present?
          # Use custom variables from modal (for single runs)
          test_run.metadata["custom_variables"]
        else
          # Fallback to empty hash (no variables)
          {}
        end
      end

      # Update test run with success
      #
      # @param test_run [TestRun] the test run to update
      # @param passed [Boolean] whether test passed
      # @param execution_time_ms [Integer] execution time in milliseconds
      # @param additional_attributes [Hash] additional attributes to update
      def update_test_run_success(test_run:, passed:, execution_time_ms:, **additional_attributes)
        test_run.update!(
          status: passed ? "passed" : "failed",
          passed: passed,
          execution_time_ms: execution_time_ms,
          **additional_attributes
        )
      end

      # Extract response text from LLM API response
      #
      # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
      # @return [String] the response text
      def extract_response_text(llm_api_response)
        # Real LLM returns RubyLLM::Message
        return llm_api_response.content if llm_api_response.respond_to?(:content)

        # Mock LLM returns Hash
        llm_api_response.dig("choices", 0, "message", "content") ||
          llm_api_response.dig(:choices, 0, :message, :content) ||
          llm_api_response.to_s
      end

      # Extract token usage from LLM API response
      #
      # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
      # @return [Hash] hash with :prompt, :completion, :total keys
      def extract_token_usage(llm_api_response)
        # Real LLM returns RubyLLM::Message
        if llm_api_response.respond_to?(:input_tokens)
          return {
            prompt: llm_api_response.input_tokens,
            completion: llm_api_response.output_tokens,
            total: (llm_api_response.input_tokens || 0) + (llm_api_response.output_tokens || 0)
          }
        end

        # Mock LLM returns Hash (no token usage)
        { prompt: nil, completion: nil, total: nil }
      end

      # Calculate cost using RubyLLM's model registry
      #
      # @param llm_api_response [RubyLLM::Message, Hash] the LLM API response
      # @return [Float, nil] cost in USD or nil if pricing not available
      def calculate_cost_from_response(llm_api_response)
        # Mock LLM responses don't have token info
        return nil unless llm_api_response.respond_to?(:input_tokens)
        return nil unless llm_api_response.input_tokens && llm_api_response.output_tokens

        # Use RubyLLM's model registry to get pricing information
        model_info = RubyLLM.models.find(llm_api_response.model_id)
        return nil unless model_info&.input_price_per_million && model_info&.output_price_per_million

        # Calculate cost: (tokens / 1,000,000) * price_per_million
        input_cost = llm_api_response.input_tokens * model_info.input_price_per_million / 1_000_000.0
        output_cost = llm_api_response.output_tokens * model_info.output_price_per_million / 1_000_000.0

        input_cost + output_cost
      end
    end
  end
end
