# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing tests for PromptVersions in the Testing section
    #
    # This controller inherits all CRUD logic from TestsControllerBase.
    #
    class TestsController < TestsControllerBase
      private

      # Set the testable (PromptVersion) and related instance variables
      def set_testable
        @version = PromptVersion.find(params[:prompt_version_id])
        @prompt = @version.prompt
        @testable = @version
      end

      # Returns the path to the prompt version's show page
      def testable_path
        testing_prompt_prompt_version_path(@prompt, @version)
      end

      # Returns the path to a specific test's show page
      def test_path(test)
        testing_prompt_version_test_path(@version, test)
      end

      # Returns the path to the tests index page
      def tests_index_path
        testing_prompt_version_tests_path(@version)
      end

      # Returns the path to load more runs for a specific test
      def load_more_runs_path(test, offset:, limit:)
        load_more_runs_testing_prompt_version_test_path(@version, test, offset: offset, limit: limit)
      end

      # Returns the path to run a specific test
      def run_test_path(test)
        run_testing_prompt_version_test_path(@version, test)
      end

      # Returns the path to the datasets index page
      def datasets_path
        testing_prompt_prompt_version_datasets_path(@prompt, @version)
      end
    end
  end
end
