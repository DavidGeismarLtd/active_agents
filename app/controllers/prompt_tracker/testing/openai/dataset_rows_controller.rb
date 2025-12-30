# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing dataset rows for OpenAI Assistants
      #
      # Handles CRUD operations for individual rows within an assistant dataset.
      # Inherits shared logic from DatasetRowsControllerBase.
      #
      class DatasetRowsController < DatasetRowsControllerBase
        private

        def set_dataset
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
          @dataset = @assistant.datasets.find(params[:dataset_id])
        end

        def redirect_path
          testing_openai_assistant_dataset_path(@assistant, @dataset)
        end
      end
    end
  end
end
