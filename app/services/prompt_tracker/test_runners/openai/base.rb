# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Openai
      # Base class for OpenAI-related test runners.
      #
      # Extends TestRunners::Base with OpenAI-specific functionality.
      # All common functionality (variables, run_evaluators, update_test_run_results)
      # is inherited from the parent class.
      #
      # Subclasses must implement:
      # - #run - Execute the test
      #
      # @example Create a new runner
      #   class MyRunner < Base
      #     def run
      #       # Run the test
      #     end
      #   end
      #
      class Base < TestRunners::Base
        # OpenAI-specific methods can be added here if needed
      end
    end
  end
end
