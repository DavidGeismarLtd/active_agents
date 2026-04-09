# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing datasets for AgentVersions in the Testing section
    #
    # Datasets are collections of test data (variable values) that can be
    # used to run tests at scale.
    #
    # This controller inherits all CRUD logic from DatasetsControllerBase.
    #
    class DatasetsController < DatasetsControllerBase
      # Flat route - no testable context needed
      skip_before_action :set_testable, only: :row_count
      skip_before_action :set_dataset, only: :row_count

      # GET /testing/datasets/:id/row_count
      # Returns JSON with the row count for a dataset (used by run_test_modal JS)
      def row_count
        dataset = Dataset.find_by(id: params[:id])
        if dataset
          render json: { count: dataset.dataset_rows.count }
        else
          render json: { count: 0 }, status: :not_found
        end
      end

      private

      # Set the testable (AgentVersion) and related instance variables
      def set_testable
        @version = AgentVersion.find(params[:agent_version_id])
        @prompt = @version.agent
        @testable = @version
      end
    end
  end
end
