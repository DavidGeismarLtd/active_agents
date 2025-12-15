# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing dataset rows
    #
    # Handles CRUD operations for individual rows within a dataset
    #
    class DatasetRowsController < ApplicationController
      before_action :set_dataset
      before_action :set_row, only: [ :update, :destroy ]

      # POST /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:dataset_id/rows
      def create
        @row = @dataset.dataset_rows.build(row_params)

        if @row.save
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      notice: "Row added successfully."
        else
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      alert: "Failed to add row: #{@row.errors.full_messages.join(', ')}"
        end
      end

      # PATCH/PUT /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:dataset_id/rows/:id
      def update
        if @row.update(row_params)
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      notice: "Row updated successfully."
        else
          redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                      alert: "Failed to update row: #{@row.errors.full_messages.join(', ')}"
        end
      end

      # DELETE /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:dataset_id/rows/:id
      def destroy
        @row.destroy
        redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                    notice: "Row deleted successfully."
      end

      # POST /testing/prompts/:prompt_id/versions/:prompt_version_id/datasets/:dataset_id/rows/generate
      def generate
        # This will be implemented in the LLM generation task
        redirect_to testing_prompt_prompt_version_dataset_path(@prompt, @version, @dataset),
                    alert: "LLM generation not yet implemented."
      end

      private

      def set_dataset
        @version = PromptVersion.find(params[:prompt_version_id])
        @prompt = @version.prompt
        @dataset = @version.datasets.find(params[:dataset_id])
      end

      def set_row
        @row = @dataset.dataset_rows.find(params[:id])
      end

      def row_params
        params.require(:dataset_row).permit(:source, row_data: {}, metadata: {})
      end
    end
  end
end
