# frozen_string_literal: true

module PromptTracker
  module Testing
    # Base controller for managing datasets across different testable types
    #
    # This controller contains all shared logic for CRUD operations on datasets.
    # Subclasses only need to implement `set_testable` to set @testable.
    #
    # Supported testable types:
    # - PromptTracker::PromptVersion
    #
    class DatasetsControllerBase < ApplicationController
      include DatasetsHelper

      before_action :set_testable
      before_action :set_dataset, only: [ :show, :edit, :update, :destroy, :generate_rows ]

      # GET /datasets
      def index
        @datasets = @testable.datasets.includes(:dataset_rows).recent
      end

      # GET /datasets/new
      def new
        @dataset = @testable.datasets.build
      end

      # POST /datasets
      def create
        @dataset = @testable.datasets.build(dataset_params)
        @dataset.created_by = "web_ui" # TODO: Replace with current_user when auth is added

        # Parse schema if it's a JSON string
        if @dataset.schema.is_a?(String)
          @dataset.schema = JSON.parse(@dataset.schema)
        end

        if @dataset.save
          redirect_to dataset_path(@dataset),
                      notice: "Dataset created successfully."
        else
          render :new, status: :unprocessable_entity
        end
      end

      # GET /datasets/:id
      def show
        @rows = @dataset.dataset_rows.recent.page(params[:page]).per(50)
      end

      # GET /datasets/:id/edit
      def edit
      end

      # PATCH/PUT /datasets/:id
      def update
        params_to_update = dataset_params

        # Parse schema if it's a JSON string
        if params_to_update[:schema].is_a?(String)
          params_to_update[:schema] = JSON.parse(params_to_update[:schema])
        end

        if @dataset.update(params_to_update)
          redirect_to dataset_path(@dataset),
                      notice: "Dataset updated successfully."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /datasets/:id
      def destroy
        @dataset.destroy
        redirect_to datasets_index_path(@testable),
                    notice: "Dataset deleted successfully."
      end

      # POST /datasets/:id/generate_rows
      def generate_rows
        count = params[:count].to_i
        instructions = params[:instructions].presence
        model = params[:model].presence

        # Enqueue background job
        GenerateDatasetRowsJob.perform_later(
          @dataset.id,
          count: count,
          instructions: instructions,
          model: model
        )

        redirect_to dataset_path(@dataset),
                    notice: "Generating #{count} rows in the background. Rows will appear shortly."
      end

      private

      # Override view lookup to use shared datasets views
      # This makes both DatasetsController and AssistantDatasetsController
      # look for views in app/views/prompt_tracker/testing/datasets/
      def _prefixes
        @_prefixes ||= super + [ "prompt_tracker/testing/datasets" ]
      end

      # Abstract method to be implemented by subclasses
      # Must set @testable instance variable
      def set_testable
        raise NotImplementedError, "Subclasses must implement #set_testable"
      end

      def set_dataset
        @dataset = @testable.datasets.find(params[:id])
      end

      def dataset_params
        params.require(:dataset).permit(:name, :description, :schema, :dataset_type, metadata: {})
      end
    end
  end
end
