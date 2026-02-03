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
      before_action :set_row, only: [ :update, :destroy, :edit_modal ]

      # GET /datasets/:dataset_id/rows/:id/edit_modal
      # Returns just the edit modal HTML for lazy-loading
      def edit_modal
        index = @dataset.dataset_rows.where("id <= ?", @row.id).count

        # Determine update path based on testable type
        if @dataset.testable.is_a?(PromptTracker::PromptVersion)
          prompt_version = @dataset.testable
          prompt = prompt_version.prompt
          update_path = PromptTracker::Engine.routes.url_helpers.testing_prompt_prompt_version_dataset_dataset_row_path(prompt, prompt_version, @dataset, @row)
        elsif @dataset.testable.is_a?(PromptTracker::Openai::Assistant)
          assistant = @dataset.testable
          update_path = PromptTracker::Engine.routes.url_helpers.testing_openai_assistant_dataset_dataset_row_path(assistant, @dataset, @row)
        end

        render partial: "prompt_tracker/testing/datasets/edit_row_modal",
               locals: { row: @row, index: index, dataset: @dataset, update_path: update_path },
               layout: false
      end

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

      # Override view lookup to use shared dataset_rows views
      # This makes both DatasetRowsController and Openai::DatasetRowsController
      # look for views in app/views/prompt_tracker/testing/dataset_rows/
      def _prefixes
        @_prefixes ||= super + [ "prompt_tracker/testing/dataset_rows" ]
      end

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
        permitted = params.require(:dataset_row).permit(:source, row_data: {}, metadata: {})

        # Handle mock_function_outputs - comes as nested hash from per-function input fields
        if permitted[:row_data] && permitted[:row_data][:mock_function_outputs].present?
          mock_outputs = permitted[:row_data][:mock_function_outputs]

          # Convert to hash and filter out empty values
          if mock_outputs.is_a?(ActionController::Parameters) || mock_outputs.is_a?(Hash)
            filtered = mock_outputs.to_h.reject { |_k, v| v.blank? }
            # Set to nil if all values were empty, otherwise use filtered hash
            permitted[:row_data][:mock_function_outputs] = filtered.present? ? filtered : nil
          end
        end

        permitted
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
