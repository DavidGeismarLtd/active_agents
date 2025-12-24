# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing OpenAI Assistants in the Testing section
      class AssistantsController < ApplicationController
        before_action :set_assistant, only: [ :show, :edit, :update, :destroy, :sync ]

        # GET /testing/openai/assistants
        # List all assistants with search and filtering
        def index
          @assistants = PromptTracker::Openai::Assistant.includes(:tests, :datasets).order(created_at: :desc)

          # Search by name or description
          if params[:q].present?
            query = "%#{params[:q]}%"
            @assistants = @assistants.where("name LIKE ? OR description LIKE ?", query, query)
          end

          # Filter by category
          if params[:category].present?
            @assistants = @assistants.where(category: params[:category])
          end

          # Sort
          case params[:sort]
          when "name"
            @assistants = @assistants.order(name: :asc)
          when "tests"
            @assistants = @assistants.left_joins(:tests)
                                    .group("prompt_tracker_openai_assistants.id")
                                    .order("COUNT(prompt_tracker_tests.id) DESC")
          end

          # Pagination
          @assistants = @assistants.page(params[:page]).per(20)

          # Get all categories for filters
          @categories = PromptTracker::Openai::Assistant.distinct.pluck(:category).compact.sort
        end

        # GET /testing/openai/assistants/:id
        # Show assistant details with tests and recent runs
        def show
          @tests = @assistant.tests.includes(:test_runs).order(created_at: :desc)
          @datasets = @assistant.datasets.includes(:dataset_rows).order(created_at: :desc)

          # Calculate metrics scoped to test runs only
          test_runs = TestRun.where(test: @tests).completed
          @total_test_runs = test_runs.count
          @tests_passing = test_runs.passed.count
          @tests_failing = test_runs.failed.count

          # Get recent test runs
          @recent_runs = test_runs.order(created_at: :desc).limit(10)

          # Calculate average score from evaluations on test runs
          test_evaluations = Evaluation.joins(test_run: :test)
                                       .where(prompt_tracker_tests: { testable_type: "PromptTracker::Openai::Assistant", testable_id: @assistant.id })
          @avg_score = test_evaluations.any? ? test_evaluations.average(:score) : nil
        end

        # GET /testing/openai/assistants/new
        # Form to create a new assistant
        def new
          @assistant = PromptTracker::Openai::Assistant.new
        end

        # POST /testing/openai/assistants
        # Create a new assistant
        def create
          @assistant = PromptTracker::Openai::Assistant.new(assistant_params)

          if @assistant.save
            redirect_to testing_openai_assistant_path(@assistant),
                        notice: "Assistant created successfully."
          else
            render :new, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:id/edit
        # Form to edit an assistant
        def edit
        end

        # PATCH/PUT /testing/openai/assistants/:id
        # Update an assistant
        def update
          if @assistant.update(assistant_params)
            redirect_to testing_openai_assistant_path(@assistant),
                        notice: "Assistant updated successfully."
          else
            render :edit, status: :unprocessable_entity
          end
        end

        # DELETE /testing/openai/assistants/:id
        # Delete an assistant
        def destroy
          @assistant.destroy
          redirect_to testing_openai_assistants_path,
                      notice: "Assistant deleted successfully."
        end

        # POST /testing/openai/assistants/:id/sync
        # Sync assistant metadata from OpenAI API
        def sync
          @assistant.fetch_from_openai!
          redirect_to testing_openai_assistant_path(@assistant),
                      notice: "Assistant synced successfully from OpenAI."
        end

        private

        def set_assistant
          @assistant = PromptTracker::Openai::Assistant.find(params[:id])
        end

        def assistant_params
          params.require(:openai_assistant).permit(:assistant_id, :name, :description, :category)
        end
      end
    end
  end
end
