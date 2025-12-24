# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing datasets for OpenAI Assistants in the Testing section
      #
      # Datasets for assistants contain conversation scenarios with:
      # - user_prompt: The initial user message
      # - max_turns: Maximum conversation turns (optional)
      #
      class AssistantDatasetsController < ApplicationController
        before_action :set_assistant
        before_action :set_dataset, only: [ :show, :edit, :update, :destroy, :generate_rows ]

        # GET /testing/openai/assistants/:assistant_id/datasets
        def index
          @datasets = @assistant.datasets.includes(:dataset_rows).recent
        end

        # GET /testing/openai/assistants/:assistant_id/datasets/new
        def new
          @dataset = @assistant.datasets.build
          # Set default schema for assistants
          @dataset.schema = [
            { "name" => "user_prompt", "type" => "string", "required" => true },
            { "name" => "max_turns", "type" => "integer", "required" => false }
          ]
        end

        # POST /testing/openai/assistants/:assistant_id/datasets
        def create
          @dataset = @assistant.datasets.build(dataset_params)
          @dataset.created_by = "web_ui" # TODO: Replace with current_user when auth is added

          # Parse schema if it's a JSON string
          if @dataset.schema.is_a?(String)
            @dataset.schema = JSON.parse(@dataset.schema)
          end

          # Ensure schema is set for assistants
          if @dataset.schema.blank?
            @dataset.schema = [
              { "name" => "user_prompt", "type" => "string", "required" => true },
              { "name" => "max_turns", "type" => "integer", "required" => false }
            ]
          end

          if @dataset.save
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        notice: "Dataset created successfully."
          else
            render :new, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/datasets/:id
        def show
          @rows = @dataset.dataset_rows.recent.page(params[:page]).per(50)
        end

        # GET /testing/openai/assistants/:assistant_id/datasets/:id/edit
        def edit
        end

        # PATCH/PUT /testing/openai/assistants/:assistant_id/datasets/:id
        def update
          params_to_update = dataset_params

          # Parse schema if it's a JSON string
          if params_to_update[:schema].is_a?(String)
            params_to_update[:schema] = JSON.parse(params_to_update[:schema])
          end

          if @dataset.update(params_to_update)
            redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                        notice: "Dataset updated successfully."
          else
            render :edit, status: :unprocessable_entity
          end
        end

        # DELETE /testing/openai/assistants/:assistant_id/datasets/:id
        def destroy
          @dataset.destroy
          redirect_to testing_openai_assistant_datasets_path(@assistant),
                      notice: "Dataset deleted successfully."
        end

        # POST /testing/openai/assistants/:assistant_id/datasets/:id/generate_rows
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

          redirect_to testing_openai_assistant_dataset_path(@assistant, @dataset),
                      notice: "Generating #{count} rows in the background. Rows will appear shortly."
        end

        private

        def set_assistant
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
        end

        def set_dataset
          @dataset = @assistant.datasets.find(params[:id])
        end

        def dataset_params
          params.require(:dataset).permit(:name, :description, :schema, metadata: {})
        end
      end
    end
  end
end
