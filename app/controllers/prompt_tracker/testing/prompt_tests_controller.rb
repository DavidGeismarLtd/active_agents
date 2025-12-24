# frozen_string_literal: true

module PromptTracker
  module Testing
    # Controller for managing prompt tests in the Testing section
    class PromptTestsController < ApplicationController
    before_action :set_prompt_version
    before_action :set_test, only: [ :show, :edit, :update, :destroy, :run, :load_more_runs ]

    # GET /prompts/:prompt_id/versions/:prompt_version_id/tests
    def index
      @tests = @version.tests.order(created_at: :desc)
    end

    # POST /prompts/:prompt_id/versions/:prompt_version_id/tests/run_all
    def run_all
      enabled_tests = @version.tests.enabled

      if enabled_tests.empty?
        redirect_to testing_prompt_prompt_version_path(@prompt, @version),
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

    # GET /prompts/:prompt_id/versions/:prompt_version_id/tests/:id
    def show
      @recent_runs = @test.recent_runs(10)
    end

    # GET /prompts/:prompt_id/versions/:prompt_version_id/tests/new
    def new
      @test = @version.tests.build
    end

    # POST /prompts/:prompt_id/versions/:prompt_version_id/tests
    def create
      @test = @version.tests.build(test_params)

      if @test.save
        respond_to do |format|
          format.html do
            redirect_to testing_prompt_prompt_version_prompt_test_path(@prompt, @version, @test), notice: "Test created successfully."
          end
          format.turbo_stream do
            # Redirect using Turbo - flash will be shown on the redirected page
            redirect_to testing_prompt_prompt_version_path(@prompt, @version), notice: "Test created successfully.", status: :see_other
          end
        end
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /prompts/:prompt_id/versions/:prompt_version_id/tests/:id/edit
    def edit
    end

    # PATCH/PUT /prompts/:prompt_id/versions/:prompt_version_id/tests/:id
    def update
      if @test.update(test_params)
        respond_to do |format|
          format.html do
            redirect_to testing_prompt_prompt_version_prompt_test_path(@prompt, @version, @test), notice: "Test updated successfully."
          end
          format.turbo_stream do
            # Redirect using Turbo - flash will be shown on the redirected page
            redirect_to testing_prompt_prompt_version_path(@prompt, @version), notice: "Test updated successfully.", status: :see_other
          end
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /prompts/:prompt_id/versions/:prompt_version_id/tests/:id
    def destroy
      @test.destroy
      redirect_to testing_prompt_prompt_version_prompt_tests_path(@prompt, @version), notice: "Test deleted successfully."
    end

    # POST /prompts/:prompt_id/versions/:prompt_version_id/tests/:id/run
    def run
      run_mode = params[:run_mode] || "dataset"

      if run_mode == "dataset"
        run_with_dataset(@test)
      else
        run_with_custom_variables(@test)
      end
    end

    # GET /prompts/:prompt_id/versions/:prompt_version_id/tests/:id/load_more_runs
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

    def set_prompt_version
      @version = PromptVersion.find(params[:prompt_version_id])
      @prompt = @version.prompt
    end

    def set_test
      @test = @version.tests.find(params[:id])
    end

    def test_params
      permitted = params.require(:test).permit(
        :name,
        :description,
        :enabled,
        :model_config,
        :metadata,
        :evaluator_configs
      )

      # Parse JSON strings to hashes/arrays
      [ :model_config, :metadata, :evaluator_configs ].each do |key|
        if permitted[key].is_a?(String)
          permitted[key] = JSON.parse(permitted[key])
        end
      end

      permitted
    end

    # Check if real LLM API calls should be used
    #
    # @return [Boolean] true if PROMPT_TRACKER_USE_REAL_LLM is set to 'true'
    def use_real_llm?
      ENV["PROMPT_TRACKER_USE_REAL_LLM"] == "true"
    end

    # Call real LLM API
    #
    # @param rendered_prompt [String] the rendered prompt
    # @param model_config [Hash] the model configuration
    # @return [Hash] LLM API response
    def call_real_llm(rendered_prompt, model_config)
      config = model_config.with_indifferent_access
      provider = config[:provider] || "openai"
      model = config[:model] || "gpt-4"
      temperature = config[:temperature] || 0.7
      max_tokens = config[:max_tokens]

      LlmClientService.call(
        provider: provider,
        model: model,
        prompt: rendered_prompt,
        temperature: temperature,
        max_tokens: max_tokens
      )[:raw] # Return raw response in provider format
    end

    # Generate a mock LLM response for testing
    #
    # @param rendered_prompt [String] the rendered prompt
    # @param model_config [Hash] the model configuration
    # @return [Hash] mock LLM response in OpenAI format
    def generate_mock_llm_response(rendered_prompt, model_config)
      provider = model_config["provider"] || model_config[:provider] || "openai"

      # Generate a realistic mock response based on the prompt
      mock_text = "This is a mock response to: #{rendered_prompt.truncate(100)}\n\n"
      mock_text += "In a production environment, this would be replaced with an actual API call to #{provider}.\n"
      mock_text += "The response would be generated by the configured model and would address the prompt appropriately."

      # Return in OpenAI-like format for compatibility
      {
        "choices" => [
          {
            "message" => {
              "content" => mock_text
            }
          }
        ]
      }
    end

    # Run a single test with a dataset
    def run_with_dataset(test)
      dataset_id = params[:dataset_id]

      unless dataset_id.present?
        redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                    alert: "Please select a dataset."
        return
      end

      dataset = @version.datasets.find(dataset_id)
      total_runs = 0

      # Create one test run for each dataset row
      dataset.dataset_rows.each do |row|
        test_run = TestRun.create!(
          test: test,
          dataset: dataset,
          dataset_row: row,
          status: "running",
          metadata: { triggered_by: "manual", user: "web_ui", run_mode: "dataset" }
        )

        # Enqueue background job
        RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
        total_runs += 1
      end

      redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                  notice: "Started #{total_runs} test run#{total_runs > 1 ? 's' : ''} (one per dataset row)!"
    end

    # Run a single test with custom variables
    def run_with_custom_variables(test)
      custom_vars = params[:custom_variables] || {}

      test_run = TestRun.create!(
        test: test,
        status: "running",
        metadata: {
          triggered_by: "manual",
          user: "web_ui",
          run_mode: "single",
          custom_variables: custom_vars
        }
      )

      RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)

      redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                  notice: "Test started in the background!"
    end

    # Run all tests with a dataset
    def run_all_with_dataset(tests)
      dataset_id = params[:dataset_id]

      unless dataset_id.present?
        redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                    alert: "Please select a dataset."
        return
      end

      dataset = @version.datasets.find(dataset_id)
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

      redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                  notice: "Started #{total_runs} test run#{total_runs > 1 ? 's' : ''} (#{tests.count} tests × #{dataset.dataset_rows.count} rows)!"
    end

    # Run all tests with custom variables
    def run_all_with_custom_variables(tests)
      custom_vars = params[:custom_variables] || {}
      total_runs = 0

      tests.each do |test|
        test_run = TestRun.create!(
          test: test,
          status: "running",
          metadata: {
            triggered_by: "run_all",
            user: "web_ui",
            run_mode: "single",
            custom_variables: custom_vars
          }
        )

        RunTestJob.perform_later(test_run.id, use_real_llm: use_real_llm?)
        total_runs += 1
      end

      redirect_to testing_prompt_prompt_version_path(@prompt, @version),
                  notice: "Started #{total_runs} test#{total_runs > 1 ? 's' : ''} in the background!"
    end
    end
  end
end
