# frozen_string_literal: true

module PromptTracker
  module Public
    # Public API for triggering task agent executions
    #
    # This controller provides a public endpoint for triggering task agents via API.
    # Authentication is handled via API key in the Authorization header.
    #
    # @example Trigger a task agent
    #   POST /api/task_agents/:slug/trigger
    #   Authorization: Bearer YOUR_API_KEY
    #   Content-Type: application/json
    #
    #   {
    #     "variables": {
    #       "source_url": "https://example.com",
    #       "topic": "AI agents"
    #     }
    #   }
    #
    class TaskAgentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :find_agent
      before_action :authenticate_api_key!

      # GET /api/task_agents/:slug/runs/:id
      def show_run
        task_run = @agent.task_runs.find(params[:id])

        response = {
          id: task_run.id,
          status: task_run.status,
          trigger_type: task_run.trigger_type,
          execution_mode: task_run.execution_mode,
          variables_used: task_run.variables_used,
          output_summary: task_run.output_summary,
          error_message: task_run.error_message,
          iterations_count: task_run.iterations_count,
          llm_calls_count: task_run.llm_calls_count,
          function_calls_count: task_run.function_calls_count,
          total_cost_usd: task_run.total_cost_usd,
          started_at: task_run.started_at,
          completed_at: task_run.completed_at,
          created_at: task_run.created_at
        }

        if task_run.output_files.attached?
          response[:output_files] = task_run.output_files.map do |file|
            {
              filename: file.filename.to_s,
              content_type: file.content_type,
              byte_size: file.byte_size,
              download_url: Rails.application.routes.url_helpers.rails_blob_path(file, disposition: :attachment, only_path: true)
            }
          end
        end

        render json: response
      end

      # POST /api/task_agents/:slug/trigger
      def trigger
        unless @agent.agent_type_task?
          render json: {
            error: "Agent is not a task agent",
            agent_type: @agent.agent_type
          }, status: :unprocessable_entity
          return
        end

        # Merge default variables with runtime overrides
        default_variables = @agent.task_config[:variables] || {}
        runtime_variables = params[:variables]&.to_unsafe_h || {}
        merged_variables = default_variables.merge(runtime_variables)

        # Create a task run and enqueue the job
        task_run = @agent.task_runs.create!(
          status: "queued",
          trigger_type: "api",
          variables_used: merged_variables
        )

        ExecuteTaskAgentJob.perform_later(@agent.id, task_run.id)

        render json: {
          task_run_id: task_run.id,
          status: task_run.status,
          trigger_type: task_run.trigger_type,
          variables_used: task_run.variables_used,
          created_at: task_run.created_at,
          run_url: deployed_agent_task_run_url(@agent.slug, task_run)
        }, status: :created
      end

      private

      def find_agent
        @agent = DeployedAgent.find_by(slug: params[:slug])

        return if @agent

        render json: { error: "Agent not found" }, status: :not_found
        false
      end

      def authenticate_api_key!
        auth_header = request.headers["Authorization"]

        unless auth_header&.start_with?("Bearer ")
          render json: { error: "Missing or invalid Authorization header" }, status: :unauthorized
          return false
        end

        api_key = auth_header.sub("Bearer ", "")

        return if @agent.verify_api_key(api_key)

        render json: { error: "Invalid API key" }, status: :unauthorized
        false
      end
    end
  end
end
