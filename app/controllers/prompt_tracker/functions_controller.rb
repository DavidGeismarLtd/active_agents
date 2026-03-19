# frozen_string_literal: true

module PromptTracker
  # Controller for managing the Function Library
  # Provides CRUD operations for code-based functions
  class FunctionsController < ApplicationController
    before_action :set_function, only: [ :show, :edit, :update, :destroy, :test, :deploy, :undeploy ]
    skip_before_action :verify_authenticity_token, only: [ :test, :deploy, :undeploy, :generate_with_ai ]
    # GET /functions
    # List all functions with search and filtering
    def index
      @functions = FunctionDefinition.includes(:function_executions).order(created_at: :desc)

      # Search by name or description
      if params[:q].present?
        @functions = @functions.search(params[:q])
      end

      # Filter by category
      if params[:category].present?
        @functions = @functions.by_category(params[:category])
      end

      # Filter by language
      if params[:language].present?
        @functions = @functions.by_language(params[:language])
      end

      # Filter by tag (JSONB array contains)
      if params[:tag].present?
        @functions = @functions.where("tags @> ?", [ params[:tag] ].to_json)
      end

      # Sort
      case params[:sort]
      when "name"
        @functions = @functions.order(name: :asc)
      when "most_used"
        @functions = @functions.order(execution_count: :desc)
      when "recently_executed"
        @functions = @functions.order(Arel.sql("last_executed_at DESC NULLS LAST"))
      else # "newest" or default
        @functions = @functions.order(created_at: :desc)
      end

      # Pagination
      @functions = @functions.page(params[:page]).per(20)

      # Get filter options
      @categories = FunctionDefinition.distinct.pluck(:category).compact.sort
      @languages = FunctionDefinition.distinct.pluck(:language).compact.sort
      @tags = FunctionDefinition.pluck(:tags).flatten.compact.uniq.sort
    end

    # GET /functions/:id
    # Show function details with execution history
    def show
      @executions = @function.function_executions
                             .order(executed_at: :desc)
                             .page(params[:page])
                             .per(20)

      # Calculate stats from actual executions (not cached counter)
      all_executions = @function.function_executions
      @total_executions = all_executions.count
      @success_rate = all_executions.success_rate
      @avg_execution_time = @function.average_execution_time_ms
    end

    # GET /functions/new
    # New function form
    def new
      @function = FunctionDefinition.new(
        language: "ruby",
        parameters: {
          "type" => "object",
          "properties" => {},
          "required" => []
        }
      )
    end

    # POST /functions
    # Create a new function
    def create
      @function = FunctionDefinition.new(function_params)
      @function.created_by = "web_ui" # TODO: Replace with current_user when auth is added

      if @function.save
        redirect_to function_path(@function),
                    notice: "Function created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /functions/:id/edit
    # Edit function form
    def edit
    end

    # PATCH/PUT /functions/:id
    # Update a function
    def update
      if @function.update(function_params)
        redirect_to function_path(@function),
                    notice: "Function updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /functions/:id
    # Delete a function
    def destroy
      @function.destroy
      redirect_to functions_path,
                  notice: "Function deleted successfully."
    end

    # POST /functions/generate_with_ai
    # Generate function code using AI
    def generate_with_ai
      description = params[:description]
      language = params[:language] || "ruby"

      if description.blank?
        render json: { error: "Description is required" }, status: :unprocessable_entity
        return
      end
      result = FunctionGeneratorService.generate(
        description: description,
        language: language
      )
      render json: result
    rescue StandardError => e
      Rails.logger.error "[FunctionsController] AI generation failed: #{e.message}"
      render json: { error: "Failed to generate function: #{e.message}" }, status: :internal_server_error
    end

    # POST /functions/:id/test
    # Test a function with sample inputs
    def test
      # Check if function is deployed
      unless @function.deployed?
        respond_to do |format|
          format.json do
            render json: {
              success?: false,
              error: "Function must be deployed to AWS Lambda before testing. Click 'Publish to Lambda' first.",
              deployment_status: @function.deployment_status
            }, status: :unprocessable_entity
          end
          format.html do
            flash[:alert] = "Function must be deployed to AWS Lambda before testing. Click 'Publish to Lambda' first."
            redirect_to function_path(@function)
          end
        end
        return
      end

      arguments = JSON.parse(params[:arguments] || "{}")
      result = @function.test(**arguments.symbolize_keys)

      respond_to do |format|
        format.json { render json: result }
        format.html do
          flash[:notice] = "Test executed successfully"
          redirect_to function_path(@function)
        end
      end
    rescue JSON::ParserError => e
      respond_to do |format|
        format.json { render json: { error: "Invalid JSON: #{e.message}" }, status: :unprocessable_entity }
        format.html do
          flash[:alert] = "Invalid JSON: #{e.message}"
          redirect_to function_path(@function)
        end
      end
    end

    # POST /functions/:id/deploy
    # Deploy function to AWS Lambda
    def deploy
      @function.update!(deployment_status: "deploying", deployment_error: nil)

      # Deploy to Lambda with merged environment variables (shared + inline)
      result = CodeExecutor::LambdaAdapter.deploy(
        function_definition: @function,
        code: @function.code,
        environment_variables: @function.merged_environment_variables,
        dependencies: @function.dependencies || []
      )

      if result[:success]
        @function.update!(
          deployment_status: "deployed",
          lambda_function_name: result[:function_name],
          deployed_at: Time.current,
          deployment_error: nil
        )

        respond_to do |format|
          format.html do
            flash[:notice] = "Function successfully deployed to AWS Lambda"
            redirect_to function_path(@function)
          end
          format.json { render json: { success: true, function_name: result[:function_name] } }
        end
      else
        @function.update!(
          deployment_status: "deployment_failed",
          deployment_error: result[:error]
        )

        respond_to do |format|
          format.html do
            flash[:alert] = "Deployment failed: #{result[:error]}"
            redirect_to function_path(@function)
          end
          format.json { render json: { success: false, error: result[:error] }, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /functions/:id/undeploy
    # Remove function from AWS Lambda
    def undeploy
      if @function.lambda_function_name.present?
        result = CodeExecutor::LambdaAdapter.undeploy(@function.lambda_function_name)

        if result[:success]
          @function.update!(
            deployment_status: "not_deployed",
            lambda_function_name: nil,
            deployed_at: nil,
            deployment_error: nil
          )

          flash[:notice] = "Function successfully removed from AWS Lambda"
        else
          flash[:alert] = "Failed to remove function: #{result[:error]}"
        end
      else
        flash[:alert] = "Function is not deployed"
      end

      redirect_to function_path(@function)
    end

    private

    def set_function
      @function = FunctionDefinition.find(params[:id])
    end

    def function_params
      params.require(:function_definition).permit(
        :name,
        :description,
        :code,
        :language,
        :category,
        tags: [],
        parameters: {},
        example_input: {},
        example_output: {},
        environment_variables: {},
        dependencies: {},
        shared_environment_variable_ids: []
      )
    end
  end
end
