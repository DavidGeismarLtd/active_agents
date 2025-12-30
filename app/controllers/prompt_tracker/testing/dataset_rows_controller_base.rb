# frozen_string_literal: true

module PromptTracker
  module Testing
    # Base controller for managing dataset rows across different testable types
    #
    # This controller contains all shared logic for CRUD operations on dataset rows.
    # Subclasses only need to implement:
    # - `set_dataset`: Set @dataset and related instance variables
    # - `redirect_path`: Return the path to redirect to after actions
    #
    # Supported testable types:
    # - PromptTracker::PromptVersion (via DatasetRowsController)
    # - PromptTracker::Openai::Assistant (via Openai::DatasetRowsController)
    #
    class DatasetRowsControllerBase < ApplicationController
      include DatasetsHelper

      before_action :set_dataset
      before_action :set_row, only: [ :update, :destroy ]

      # POST /datasets/:dataset_id/rows
      def create
        @row = @dataset.dataset_rows.build(row_params)

        if @row.save
          respond_to do |format|
            format.html { redirect_to redirect_path, notice: "Row added successfully." }
            format.turbo_stream { flash.now[:notice] = "Row added successfully." }
          end
        else
          respond_to do |format|
            format.html { redirect_to redirect_path, alert: "Failed to add row: #{@row.errors.full_messages.join(', ')}" }
            format.turbo_stream { render_error_turbo_stream("Failed to add row: #{@row.errors.full_messages.join(', ')}") }
          end
        end
      end

      # PATCH/PUT /datasets/:dataset_id/rows/:id
      def update
        if @row.update(row_params)
          respond_to do |format|
            format.html { redirect_to redirect_path, notice: "Row updated successfully." }
            format.turbo_stream { flash.now[:notice] = "Row updated successfully." }
          end
        else
          respond_to do |format|
            format.html { redirect_to redirect_path, alert: "Failed to update row: #{@row.errors.full_messages.join(', ')}" }
            format.turbo_stream { render_error_turbo_stream("Failed to update row: #{@row.errors.full_messages.join(', ')}") }
          end
        end
      end

      # DELETE /datasets/:dataset_id/rows/:id
      def destroy
        @row.destroy
        respond_to do |format|
          format.html { redirect_to redirect_path, notice: "Row deleted successfully." }
          format.turbo_stream { flash.now[:notice] = "Row deleted successfully." }
        end
      end

      # DELETE /datasets/:dataset_id/rows/batch_destroy
      def batch_destroy
        row_ids = params[:row_ids]

        if row_ids.blank?
          respond_to do |format|
            format.html { redirect_to redirect_path, alert: "No rows selected for deletion." }
            format.turbo_stream { render_error_turbo_stream("No rows selected for deletion.") }
          end
          return
        end

        deleted_count = @dataset.dataset_rows.where(id: row_ids).destroy_all.count

        respond_to do |format|
          format.html { redirect_to redirect_path, notice: "#{deleted_count} row(s) deleted successfully." }
          format.turbo_stream { flash.now[:notice] = "#{deleted_count} row(s) deleted successfully." }
        end
      end

      private

      # Abstract method to be implemented by subclasses
      # Must set @dataset instance variable and any related resources
      def set_dataset
        raise NotImplementedError, "Subclasses must implement #set_dataset"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to redirect to after actions
      def redirect_path
        raise NotImplementedError, "Subclasses must implement #redirect_path"
      end

      def set_row
        @row = @dataset.dataset_rows.find(params[:id])
      end

      def row_params
        params.require(:dataset_row).permit(:source, row_data: {}, metadata: {})
      end

      def render_error_turbo_stream(message)
        render turbo_stream: turbo_stream.update(
          "generation-status",
          partial: "prompt_tracker/shared/alert",
          locals: { type: "danger", message: message }
        )
      end
    end
  end
end
