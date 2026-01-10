# frozen_string_literal: true

module PromptTracker
  # Helper methods for test-related views.
  #
  # This helper provides URL generation methods that work in both controller
  # and background job contexts by using explicit engine route helpers.
  module TestsHelper
    # Generate the path to run a specific test
    #
    # @param test [PromptTracker::Test] The test to run
    # @return [String] The path to run the test
    # @raise [ArgumentError] if the testable type is unknown
    def run_test_path(test)
      testable = test.testable

      case testable
      when PromptTracker::PromptVersion
        PromptTracker::Engine.routes.url_helpers.run_testing_prompt_version_test_path(testable, test)
      when PromptTracker::Openai::Assistant
        PromptTracker::Engine.routes.url_helpers.run_testing_openai_assistant_test_path(testable, test)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate the path to datasets for a testable
    #
    # @param testable [PromptTracker::PromptVersion, PromptTracker::Openai::Assistant] The testable
    # @return [String] The path to the datasets index
    # @raise [ArgumentError] if the testable type is unknown
    def datasets_path_for_testable(testable)
      case testable
      when PromptTracker::PromptVersion
        PromptTracker::Engine.routes.url_helpers.testing_prompt_prompt_version_datasets_path(testable.prompt, testable)
      when PromptTracker::Openai::Assistant
        PromptTracker::Engine.routes.url_helpers.testing_openai_assistant_datasets_path(testable)
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end

    # Generate the path to load more runs for a test
    #
    # @param test [PromptTracker::Test] The test
    # @param offset [Integer] The offset for pagination
    # @param limit [Integer] The limit for pagination
    # @return [String] The path to load more runs
    # @raise [ArgumentError] if the testable type is unknown
    def load_more_runs_path_for_test(test, offset:, limit:)
      testable = test.testable

      case testable
      when PromptTracker::PromptVersion
        PromptTracker::Engine.routes.url_helpers.load_more_runs_testing_prompt_version_test_path(
          testable, test, offset: offset, limit: limit
        )
      when PromptTracker::Openai::Assistant
        PromptTracker::Engine.routes.url_helpers.load_more_runs_testing_openai_assistant_test_path(
          testable, test, offset: offset, limit: limit
        )
      else
        raise ArgumentError, "Unknown testable type: #{testable.class}"
      end
    end
  end
end
