# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing tests for OpenAI Assistants in the Testing section
      #
      # This controller inherits all CRUD logic from TestsControllerBase.
      #
      class AssistantTestsController < TestsControllerBase
        private

        # Set the testable (Assistant) and related instance variables
        def set_testable
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
          @testable = @assistant
        end

        # Returns the path to the assistant's show page
        def testable_path
          testing_openai_assistant_path(@assistant)
        end

        # Returns the path to a specific test's show page
        def test_path(test)
          testing_openai_assistant_test_path(@assistant, test)
        end

        # Returns the path to the tests index page
        def tests_index_path
          testing_openai_assistant_tests_path(@assistant)
        end

        # Returns the path to load more runs for a specific test
        def load_more_runs_path(test, offset:, limit:)
          load_more_runs_testing_openai_assistant_test_path(@assistant, test, offset: offset, limit: limit)
        end

        # Returns the path to run a specific test
        def run_test_path(test)
          run_testing_openai_assistant_test_path(@assistant, test)
        end

        # Returns the path to the datasets index page
        def datasets_path
          testing_openai_assistant_datasets_path(@assistant)
        end
      end
    end
  end
end
