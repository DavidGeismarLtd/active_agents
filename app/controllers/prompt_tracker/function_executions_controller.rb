# frozen_string_literal: true

module PromptTracker
  # Controller for viewing function execution details
  class FunctionExecutionsController < ApplicationController
    before_action :set_execution

    # GET /function_executions/:id
    # Show detailed execution information
    def show
      @function = @execution.function_definition
    end

    private

    def set_execution
      @execution = FunctionExecution.find(params[:id])
    end
  end
end
