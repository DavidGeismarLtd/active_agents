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
          @row = @dataset.dataset_rows.build(
            row_data: params[:row_data].to_unsafe_h,
            source: "manual"
          )

          if @row.save
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        notice: "Row added successfully."
          else
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        alert: "Failed to add row: #{@row.errors.full_messages.join(', ')}"
          end
        end

        # PATCH/PUT /testing/openai/assistants/:assistant_id/datasets/:dataset_id/rows/:id
        def update
          if @row.update(row_data: params[:row_data].to_unsafe_h)
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        notice: "Row updated successfully."
          else
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        alert: "Failed to update row: #{@row.errors.full_messages.join(', ')}"
          end
        end

        # DELETE /testing/openai/assistants/:assistant_id/datasets/:dataset_id/rows/:id
        def destroy
          @row.destroy
          redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                      notice: "Row deleted successfully."
        end

        private

        def set_dataset
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
          @dataset = @assistant.datasets.find(params[:dataset_id])
        end

        def set_row
          @row = @dataset.dataset_rows.find(params[:id])
        end
      end
    end
  end
end
