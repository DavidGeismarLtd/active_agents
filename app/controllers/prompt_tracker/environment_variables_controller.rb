# frozen_string_literal: true

module PromptTracker
  # Controller for managing shared environment variables
  class EnvironmentVariablesController < ApplicationController
    before_action :set_environment_variable, only: [ :show, :edit, :update, :destroy ]

    # GET /environment_variables
    def index
      @environment_variables = EnvironmentVariable.ordered_by_name

      if params[:q].present?
        @environment_variables = @environment_variables.search(params[:q])
      end

      @environment_variables = @environment_variables.page(params[:page]).per(20)
    end

    # GET /environment_variables/:id
    def show
      @functions = @environment_variable.function_definitions.order(:name)
    end

    # GET /environment_variables/new
    def new
      @environment_variable = EnvironmentVariable.new
    end

    # GET /environment_variables/:id/edit
    def edit
    end

    # POST /environment_variables
    def create
      @environment_variable = EnvironmentVariable.new(environment_variable_params)

      if @environment_variable.save
        respond_to do |format|
          format.html do
            flash[:notice] = "Environment variable created successfully"
            redirect_to environment_variables_path
          end
          format.json { render json: @environment_variable, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @environment_variable.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /environment_variables/:id
    def update
      if @environment_variable.update(environment_variable_params)
        respond_to do |format|
          format.html do
            flash[:notice] = "Environment variable updated successfully"
            redirect_to environment_variables_path
          end
          format.json { render json: @environment_variable }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @environment_variable.errors, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /environment_variables/:id
    def destroy
      if @environment_variable.in_use?
        flash[:alert] = "Cannot delete environment variable that is in use by #{@environment_variable.usage_count} function(s)"
        redirect_to environment_variables_path
      else
        @environment_variable.destroy
        flash[:notice] = "Environment variable deleted successfully"
        redirect_to environment_variables_path
      end
    end

    private

    def set_environment_variable
      @environment_variable = EnvironmentVariable.find(params[:id])
    end

    def environment_variable_params
      params.require(:environment_variable).permit(:name, :key, :value, :description)
    end
  end
end
