# frozen_string_literal: true

module PromptTracker
  module Testing
    # Base controller for managing tests across different testable types
    #
    # This controller contains all shared logic for CRUD operations on tests.
    # Subclasses only need to implement:
    # - `set_testable` to set @testable (and any related instance variables)
    # - `testable_path` to return the path to the testable's show page
    # - `test_path` to return the path to a specific test's show page
    #
    # Supported testable types:
    # - PromptTracker::PromptVersion
    # - PromptTracker::Openai::Assistant
    #
    class TestsControllerBase < ApplicationController
      before_action :set_testable
      before_action :set_test, only: [ :update, :destroy, :run, :load_more_runs ]

      # Make path helpers available to views
      helper_method :load_more_runs_path, :test_path, :run_test_path, :datasets_path

      # GET /tests
      def index
        @tests = @testable.tests.order(created_at: :desc)
      end

      # POST /tests/run_all
      # Runs all enabled tests of a specific test_mode (if provided)
      #
      # @param test_mode [String] optional - "single_turn" or "conversational" to filter tests
      def run_all
        enabled_tests = @testable.tests.enabled

        # Filter by test_mode if specified (e.g., from "Run All Single-Turn" or "Run All Conversational" buttons)
        if params[:test_mode].present?
          enabled_tests = enabled_tests.where(test_mode: params[:test_mode])
        end

        if enabled_tests.empty?
          redirect_to testable_path,
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

      # POST /tests
      def create
        @test = @testable.tests.build(test_params)

        if @test.save
          respond_to do |format|
            format.html do
              redirect_to testable_path,
                          notice: "Test created successfully."
            end
            format.turbo_stream do
              redirect_to testable_path,
                          notice: "Test created successfully.",
                          status: :see_other
            end
          end
        else
          render :new, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /tests/:id
      def update
        if @test.update(test_params)
          respond_to do |format|
            format.html do
              redirect_to testable_path,
                          notice: "Test updated successfully."
            end
            format.turbo_stream do
              redirect_to testable_path,
                          notice: "Test updated successfully.",
                          status: :see_other
            end
          end
        else
          redirect_to testable_path,
                      alert: "Failed to update test: #{@test.errors.full_messages.join(', ')}"
        end
      end

      # DELETE /tests/:id
      def destroy
        @test.destroy
        redirect_to testable_path,
                    notice: "Test deleted successfully."
      end

      # POST /tests/:id/run
      def run
        run_mode = params[:run_mode] || "dataset"

        if run_mode == "dataset"
          run_with_dataset(@test)
        else
          run_with_custom_variables(@test)
        end
      end

      # GET /tests/:id/load_more_runs
      # Load additional test runs for progressive loading
      def load_more_runs
        offset = params[:offset].present? ? params[:offset].to_i : 5
        limit = params[:limit].present? ? params[:limit].to_i : 5

        @additional_runs = @test.test_runs
                                .includes(:evaluations, :human_evaluations)
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

      # Override view lookup to use shared tests views
      # This makes both TestsController and AssistantTestsController
      # look for views in app/views/prompt_tracker/testing/tests/
      def _prefixes
        @_prefixes ||= super + [ "prompt_tracker/testing/tests" ]
      end

      # Abstract method to be implemented by subclasses
      # Must set @testable instance variable
      def set_testable
        raise NotImplementedError, "Subclasses must implement #set_testable"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to the testable's show page (for redirects)
      def testable_path
        raise NotImplementedError, "Subclasses must implement #testable_path"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to a specific test's show page
      # @param test [Test] the test to get the path for
      def test_path(test)
        raise NotImplementedError, "Subclasses must implement #test_path"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to the tests index page
      def tests_index_path
        raise NotImplementedError, "Subclasses must implement #tests_index_path"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to load more runs for a specific test
      # @param test [Test] the test to get the path for
      # @param offset [Integer] the offset for pagination
      # @param limit [Integer] the limit for pagination
      def load_more_runs_path(test, offset:, limit:)
        raise NotImplementedError, "Subclasses must implement #load_more_runs_path"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to run a specific test
      # @param test [Test] the test to get the path for
      def run_test_path(test)
        raise NotImplementedError, "Subclasses must implement #run_test_path"
      end

      # Abstract method to be implemented by subclasses
      # Returns the path to the datasets index page
      def datasets_path
        raise NotImplementedError, "Subclasses must implement #datasets_path"
      end

      def set_test
        @test = @testable.tests.find(params[:id])
      end

      def test_params
        permitted = params.require(:test).permit(
          :name,
          :description,
          :enabled,
          :test_mode,
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

        # Get required variable names for custom run validation.
        #
        # For Assistants:
        #   - Always uses Dataset::CONVERSATIONAL_FIELDS (interlocutor_simulation_prompt, etc.)
        #
        # For PromptVersions:
        #   - In "single" execution mode: uses the testable's variables_schema
        #   - In "conversation" execution mode: requires both variables_schema and
        #     conversational fields so custom runs and conversational datasets share
        #     the same shape.
        #
        # @param execution_mode [String, Symbol] "single" or "conversation"
        # @return [Array<String>] required variable names
        def required_custom_run_variables(execution_mode: "single")
          # Assistants always operate in conversational mode and re-use dataset
          # conversational fields for both datasets and custom runs.
          if @testable.is_a?(PromptTracker::Openai::Assistant)
            return Dataset::CONVERSATIONAL_FIELDS
              .select { |v| v["required"] }
              .map { |v| v["name"] }
          end

          # PromptVersions: start from their own variables_schema
          base_required = (@testable.variables_schema || [])
            .select { |v| v["required"] }
            .map { |v| v["name"] }

          # In conversational execution mode, also require conversational fields
          if execution_mode.to_s == "conversation"
            conversational_required = Dataset::CONVERSATIONAL_FIELDS
              .select { |v| v["required"] }
              .map { |v| v["name"] }
            (base_required + conversational_required).uniq
          else
            base_required
          end
        end

      # Run a single test with a dataset
      def run_with_dataset(test)
        dataset_id = params[:dataset_id]

        unless dataset_id.present?
          redirect_to testable_path,
                      alert: "Please select a dataset."
          return
        end

          dataset = @testable.datasets.find(dataset_id)
          execution_mode = dataset.conversational? ? "conversation" : "single"

          # Create test runs for each dataset row
          dataset.dataset_rows.each do |row|
            test_run = TestRun.create!(
              test: test,
              dataset: dataset,
              dataset_row: row,
              status: "running",
              metadata: {
                triggered_by: "manual",
                user: "web_ui",
                run_mode: "dataset",
                execution_mode: execution_mode
              }
            )

          RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
        end

        redirect_to testable_path,
                    notice: "Test queued with #{dataset.dataset_rows.count} scenario(s)."
      end

        # Run a single test with custom variables
        def run_with_custom_variables(test)
          custom_vars = params[:custom_variables] || {}
          execution_mode = (params[:execution_mode].presence || "single").to_s

          # Validate required variables based on testable type and execution mode
          required_vars = required_custom_run_variables(execution_mode: execution_mode)
          missing_vars = required_vars.select { |var| custom_vars[var].blank? }

          if missing_vars.any?
            redirect_to testable_path,
                        alert: "Please provide: #{missing_vars.map(&:humanize).join(', ')}"
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
              execution_mode: execution_mode,
              custom_variables: custom_vars
            }
          )

          RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)

          redirect_to testable_path,
                      notice: "Test queued with custom scenario."
        end

        # Run all tests with a dataset
        def run_all_with_dataset(tests)
          dataset_id = params[:dataset_id]

          unless dataset_id.present?
            redirect_to testable_path,
                        alert: "Please select a dataset."
            return
          end

          dataset = @testable.datasets.find(dataset_id)
          total_runs = 0
          execution_mode = dataset.conversational? ? "conversation" : "single"

          # Create test runs for each test × each dataset row
          tests.each do |test|
            dataset.dataset_rows.each do |row|
              test_run = TestRun.create!(
                test: test,
                dataset: dataset,
                dataset_row: row,
                status: "running",
                metadata: {
                  triggered_by: "run_all",
                  user: "web_ui",
                  run_mode: "dataset",
                  execution_mode: execution_mode
                }
              )

              RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
              total_runs += 1
            end
          end

          redirect_to testable_path,
                      notice: "Queued #{total_runs} test run(s) across #{tests.count} test(s)."
        end

        # Run all tests with custom variables
        def run_all_with_custom_variables(tests)
          custom_vars = params[:custom_variables] || {}
          execution_mode = (params[:execution_mode].presence || "single").to_s

          # Validate required variables based on testable type and execution mode
          required_vars = required_custom_run_variables(execution_mode: execution_mode)
          missing_vars = required_vars.select { |var| custom_vars[var].blank? }

          if missing_vars.any?
            redirect_to testable_path,
                        alert: "Please provide: #{missing_vars.map(&:humanize).join(', ')}"
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
                execution_mode: execution_mode,
                custom_variables: custom_vars
              }
            )

            RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
            total_runs += 1
          end

          redirect_to testable_path,
                      notice: "Queued #{total_runs} test run(s) with custom scenario."
        end
    end
  end
end
