# frozen_string_literal: true

module PromptTracker
  # Controller for viewing task run history
  class TaskRunsController < ApplicationController
    before_action :set_agent
    before_action :set_task_run, only: [ :show, :cancel ]

    # GET /agents/:slug/runs
    def index
      @task_runs = @agent.task_runs
                         .includes(:llm_responses, :function_executions)
                         .order(created_at: :desc)
                         .page(params[:page])
                         .per(20)

      # Apply filters
      @task_runs = @task_runs.where(status: params[:status]) if params[:status].present?
      @task_runs = @task_runs.where(trigger_type: params[:trigger_type]) if params[:trigger_type].present?

      # Statistics
      @total_runs = @agent.task_runs.count
      @successful_runs = @agent.task_runs.status_completed.count
      @failed_runs = @agent.task_runs.status_failed.count
      @running_runs = @agent.task_runs.status_running.count
    end

    # GET /agents/:slug/runs/:id
    def show
      # Get all LLM responses for this task run
      @llm_responses = @task_run.llm_responses.order(created_at: :asc)

      # Get all function executions for this task run
      @function_executions = @task_run.function_executions.order(created_at: :asc)

      # Build timeline of events
      @timeline = build_timeline(@llm_responses, @function_executions)
    end

    # POST /agents/:slug/runs/:id/cancel
    def cancel
      if @task_run.finished?
        redirect_to deployed_agent_task_run_path(@agent.slug, @task_run),
                    alert: "Cannot cancel a #{@task_run.status} task run."
        return
      end

      @task_run.cancel!
      redirect_to deployed_agent_task_run_path(@agent.slug, @task_run),
                  notice: "Task run cancelled successfully."
    end

    private

    def set_agent
      @agent = DeployedAgent.find_by!(slug: params[:deployed_agent_slug])
    end

    def set_task_run
      @task_run = @agent.task_runs.find(params[:id])
    end

    def build_timeline(llm_responses, function_executions)
      # Build flat list of all events
      events = []

      # Add LLM responses with their tool_calls
      llm_responses.each do |response|
        # Extract iteration number from context
        iteration = response.context&.dig("iteration") || 0

        events << {
          type: :llm_response,
          timestamp: response.created_at,
          iteration: iteration,
          data: response
        }
      end

      # Add function executions
      function_executions.each do |execution|
        # Function executions happen DURING an LLM call (RubyLLM's internal loop).
        # The LLM response is tracked AFTER all functions execute.
        # So we find the NEXT LLM response (the one created after this execution).
        next_response = llm_responses
          .select { |r| r.created_at > execution.created_at }
          .min_by(&:created_at)

        # Use the next response's iteration, or default to 1 if this is the first iteration
        iteration = next_response&.context&.dig("iteration") || 1

        events << {
          type: :function_execution,
          timestamp: execution.created_at,
          iteration: iteration,
          data: execution
        }
      end

      # Sort by timestamp
      events.sort_by! { |e| e[:timestamp] }

      # Group events by iteration
      grouped = events.group_by { |e| e[:iteration] }

      # Build hierarchical structure
      iterations = grouped.map do |iteration_num, iteration_events|
        {
          iteration: iteration_num,
          events: iteration_events,
          started_at: iteration_events.first[:timestamp],
          completed_at: iteration_events.last[:timestamp],
          duration_ms: ((iteration_events.last[:timestamp] - iteration_events.first[:timestamp]) * 1000).round(0),
          llm_calls_count: iteration_events.count { |e| e[:type] == :llm_response },
          function_calls_count: iteration_events.count { |e| e[:type] == :function_execution }
        }
      end

      # Sort iterations by iteration number
      iterations.sort_by { |i| i[:iteration] }
    end
  end
end
