# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing dataset rows for PromptVersions
    #
    # Handles CRUD operations for individual rows within a dataset.
    # Inherits shared logic from DatasetRowsControllerBase.
    #
    class DatasetRowsController < DatasetRowsControllerBase
      private

      def set_dataset
        @version = PromptVersion.find(params[:prompt_version_id])
        @prompt = @version.prompt
        @dataset = @version.datasets.find(params[:dataset_id])
      end

      def redirect_path
        testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset)
      end
    end
  end
end
