# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing tests for OpenAI Assistants in the Testing section
      class AssistantTestsController < ApplicationController
        before_action :set_assistant
        before_action :set_test, only: [ :show, :edit, :update, :destroy, :run, :load_more_runs ]

        # GET /testing/openai/assistants/:assistant_id/tests
        def index
          @tests = @assistant.tests.order(created_at: :desc)
        end

        # POST /testing/openai/assistants/:assistant_id/tests/run_all
        def run_all
          enabled_tests = @assistant.tests.enabled

          if enabled_tests.empty?
            redirect_to testing_openai_assistant_path(@assistant),
                        alert: "No enabled tests to run."
            return
          end

          run_mode = params[:run_mode] || "dataset"

          if run_mode == "dataset"
            run_all_with_dataset(enabled_tests)
          else
            run_all_with_custom_variables(enabled_tests)
          end
        end

        # GET /testing/openai/assistants/:assistant_id/tests/:id
        def show
          @recent_runs = @test.recent_runs(10)
        end

        # GET /testing/openai/assistants/:assistant_id/tests/new
        def new
          @test = @assistant.tests.build
        end

        # POST /testing/openai/assistants/:assistant_id/tests
        def create
          @test = @assistant.tests.build(test_params)

          if @test.save
            respond_to do |format|
              format.html do
                redirect_to testing_openai_assistant_test_path(@assistant, @test),
                            notice: "Test created successfully."
              end
              format.turbo_stream do
                redirect_to testing_openai_assistant_path(@assistant),
                            notice: "Test created successfully.",
                            status: :see_other
              end
            end
          else
            render :new, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/tests/:id/edit
        def edit
        end

        # PATCH/PUT /testing/openai/assistants/:assistant_id/tests/:id
        def update
          if @test.update(test_params)
            respond_to do |format|
              format.html do
                redirect_to testing_openai_assistant_test_path(@assistant, @test),
                            notice: "Test updated successfully."
              end
              format.turbo_stream do
                redirect_to testing_openai_assistant_path(@assistant),
                            notice: "Test updated successfully.",
                            status: :see_other
              end
            end
          else
            render :edit, status: :unprocessable_entity
          end
        end

        # DELETE /testing/openai/assistants/:assistant_id/tests/:id
        def destroy
          @test.destroy
          redirect_to testing_openai_assistant_tests_path(@assistant),
                      notice: "Test deleted successfully."
        end

        # POST /testing/openai/assistants/:assistant_id/tests/:id/run
        def run
          run_mode = params[:run_mode] || "dataset"

          if run_mode == "dataset"
            run_with_dataset(@test)
          else
            run_with_custom_variables(@test)
          end
        end

        # GET /testing/openai/assistants/:assistant_id/tests/:id/load_more_runs
        # Load additional test runs for progressive loading
        def load_more_runs
          offset = params[:offset].present? ? params[:offset].to_i : 5
          limit = params[:limit].present? ? params[:limit].to_i : 5

          @additional_runs = @test.test_runs
                                  .includes(:evaluations)
                                  .order(created_at: :desc)
                                  .offset(offset)
                                  .limit(limit)

          @total_runs_count = @test.test_runs.count
          @next_offset = offset + limit

          respond_to do |format|
            format.turbo_stream
          end
        end

        private

        def set_assistant
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
        end

        def set_test
          @test = @assistant.tests.find(params[:id])
        end

        def test_params
          permitted = params.require(:test).permit(
            :name,
            :description,
            :enabled,
            :metadata,
            :evaluator_configs
          )

          # Parse JSON strings to hashes/arrays
          [ :metadata, :evaluator_configs ].each do |key|
            if permitted[key].is_a?(String)
              permitted[key] = JSON.parse(permitted[key])
            end
          end

          permitted
        end

        # Check if real LLM API calls should be used
        def use_real_llm?
          ENV["PROMPT_TRACKER_USE_REAL_LLM"] == "true"
        end

        # Run a single test with a dataset
        def run_with_dataset(test)
          dataset_id = params[:dataset_id]

          unless dataset_id.present?
            redirect_to testing_openai_assistant_test_path(@assistant, test),
                        alert: "Please select a dataset."
            return
          end

          dataset = @assistant.datasets.find(dataset_id)

          # Create test runs for each dataset row
          dataset.dataset_rows.each do |row|
            test_run = TestRun.create!(
              test: test,
              dataset: dataset,
              dataset_row: row,
              status: "running",
              metadata: { triggered_by: "manual", user: "web_ui", run_mode: "dataset" }
            )

            RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
          end

          redirect_to testing_openai_assistant_test_path(@assistant, test),
                      notice: "Test queued with #{dataset.dataset_rows.count} scenario(s)."
        end

        # Run a single test with custom variables
        def run_with_custom_variables(test)
          user_prompt = params[:user_prompt]
          max_turns = params[:max_turns].present? ? params[:max_turns].to_i : 3

          unless user_prompt.present?
            redirect_to testing_openai_assistant_test_path(@assistant, test),
                        alert: "Please provide a user prompt."
            return
          end

          # Create a test run with custom variables
          test_run = TestRun.create!(
            test: test,
            status: "running",
            metadata: {
              triggered_by: "manual",
              user: "web_ui",
              run_mode: "custom",
              custom_variables: { user_prompt: user_prompt, max_turns: max_turns }
            }
          )

          RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)

          redirect_to testing_openai_assistant_test_path(@assistant, test),
                      notice: "Test queued with custom scenario."
        end

        # Run all tests with a dataset
        def run_all_with_dataset(tests)
          dataset_id = params[:dataset_id]

          unless dataset_id.present?
            redirect_to testing_openai_assistant_path(@assistant),
                        alert: "Please select a dataset."
            return
          end

          dataset = @assistant.datasets.find(dataset_id)
          total_runs = 0

          # Create test runs for each test × each dataset row
          tests.each do |test|
            dataset.dataset_rows.each do |row|
              test_run = TestRun.create!(
                test: test,
                dataset: dataset,
                dataset_row: row,
                status: "running",
                metadata: { triggered_by: "run_all", user: "web_ui", run_mode: "dataset" }
              )

              RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
              total_runs += 1
            end
          end

          redirect_to testing_openai_assistant_path(@assistant),
                      notice: "Queued #{total_runs} test run(s) across #{tests.count} test(s)."
        end

        # Run all tests with custom variables
        def run_all_with_custom_variables(tests)
          user_prompt = params[:user_prompt]
          max_turns = params[:max_turns].present? ? params[:max_turns].to_i : 3

          unless user_prompt.present?
            redirect_to testing_openai_assistant_path(@assistant),
                        alert: "Please provide a user prompt."
            return
          end

          total_runs = 0

          # Create test runs for each test
          tests.each do |test|
            test_run = TestRun.create!(
              test: test,
              status: "running",
              metadata: {
                triggered_by: "run_all",
                user: "web_ui",
                run_mode: "custom",
                custom_variables: { user_prompt: user_prompt, max_turns: max_turns }
              }
            )

            RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
            total_runs += 1
          end

          redirect_to testing_openai_assistant_path(@assistant),
                      notice: "Queued #{total_runs} test run(s) with custom scenario."
        end
      end
    end
  end
end
