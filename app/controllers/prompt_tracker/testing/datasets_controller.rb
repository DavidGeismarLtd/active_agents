# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing datasets for PromptVersions in the Testing section
    #
    # Datasets are collections of test data (variable values) that can be
    # used to run tests at scale.
    #
    # This controller inherits all CRUD logic from DatasetsControllerBase.
    #
    class DatasetsController < DatasetsControllerBase
      private

      # Set the testable (PromptVersion) and related instance variables
      def set_testable
        @version = PromptVersion.find(params[:prompt_version_id])
        @prompt = @version.prompt
        @testable = @version
      end
    end
  end
end
