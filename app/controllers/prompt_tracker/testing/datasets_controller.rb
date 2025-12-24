# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing datasets in the Testing section
    #
    # Datasets are collections of test data (variable values) that can be
    # used to run tests at scale.
    #
    class DatasetsController < ApplicationController
      before_action :set_prompt_version
      before_action :set_dataset, only: [ :show, :edit, :update, :destroy, :generate_rows ]

      # GET /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets
      def index
        @datasets = @version.datasets.includes(:dataset_rows).recent
      end

      # GET /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/new
      def new
        @dataset = @version.datasets.build
      end

      # POST /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets
      def create
        @dataset = @version.datasets.build(dataset_params)
        @dataset.created_by = "web_ui" # TODO: Replace with current_user when auth is added

        # Parse schema if it's a JSON string
        if @dataset.schema.is_a?(String)
          @dataset.schema = JSON.parse(@dataset.schema)
        end

        if @dataset.save
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      notice: "Dataset created successfully."
        else
          render :new, status: :unprocessable_entity
        end
      end

      # GET /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:id
      def show
        @rows = @dataset.dataset_rows.recent.page(params[:page]).per(50)
      end

      # GET /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:id/edit
      def edit
      end

      # PATCH/PUT /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:id
      def update
        params_to_update = dataset_params

        # Parse schema if it's a JSON string
        if params_to_update[:schema].is_a?(String)
          params_to_update[:schema] = JSON.parse(params_to_update[:schema])
        end

        if @dataset.update(params_to_update)
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      notice: "Dataset updated successfully."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:id
      def destroy
        @dataset.destroy
        redirect_to testing_prompt_prompt_version_datasets_path(@prompt, @version),
                    notice: "Dataset deleted successfully."
      end

      # POST /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:id/generate_rows
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

        redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                    notice: "Generating #{count} rows in the background. Rows will appear shortly."
      end

      private

      def set_prompt_version
        @version = PromptVersion.find(params[:prompt_version_id])
        @prompt = @version.prompt
      end

      def set_dataset
        @dataset = @version.datasets.find(params[:id])
      end

      def dataset_params
        params.require(:dataset).permit(:name, :description, :schema, metadata: {})
      end
    end
  end
end
