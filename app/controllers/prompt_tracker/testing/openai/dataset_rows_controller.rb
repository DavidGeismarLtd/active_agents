# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing dataset rows for OpenAI Assistants
      #
      # Handles CRUD operations for individual rows within an assistant dataset
      #
      class DatasetRowsController < ApplicationController
        before_action :set_dataset
        before_action :set_row, only: [ :update, :destroy ]

        # POST /testing/openai/assistants/:assistant_id/datasets/:dataset_id/rows
        def create
          @row = @dataset.dataset_rows.build(row_params)

          if @row.save
            respond_to do |format|
              format.html { redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset), notice: "Row added successfully." }
              format.turbo_stream { flash.now[:notice] = "Row added successfully." }
            end
          else
            respond_to do |format|
              format.html { redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset), alert: "Failed to add row: #{@row.errors.full_messages.join(', ')}" }
              format.turbo_stream { render turbo_stream: turbo_stream.update("generation-status", partial: "prompt_tracker/shared/alert", locals: { type: "danger", message: "Failed to add row: #{@row.errors.full_messages.join(', ')}" }) }
            end
          end
        end

        # PATCH/PUT /testing/openai/assistants/:assistant_id/datasets/:dataset_id/rows/:id
        def update
          if @row.update(row_params)
            respond_to do |format|
              format.html { redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset), notice: "Row updated successfully." }
              format.turbo_stream { flash.now[:notice] = "Row updated successfully." }
            end
          else
            respond_to do |format|
              format.html { redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset), alert: "Failed to update row: #{@row.errors.full_messages.join(', ')}" }
              format.turbo_stream { render turbo_stream: turbo_stream.update("generation-status", partial: "prompt_tracker/shared/alert", locals: { type: "danger", message: "Failed to update row: #{@row.errors.full_messages.join(', ')}" }) }
            end
          end
        end

        # DELETE /testing/openai/assistants/:assistant_id/datasets/:dataset_id/rows/:id
        def destroy
          @row.destroy
          respond_to do |format|
            format.html { redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset), notice: "Row deleted successfully." }
            format.turbo_stream { flash.now[:notice] = "Row deleted successfully." }
          end
        end

        private

        def set_dataset
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
          @dataset = @assistant.datasets.find(params[:dataset_id])
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
end
