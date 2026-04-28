# frozen_string_literal: true

module PromptTracker
  module Internal
    # Receives execution events from containerized agent runtimes.
    #
    # Events are authenticated with a per-run callback token.
    # This endpoint is NOT part of the public API - it is only called
    # by agent containers running on the same host/network.
    #
    # @example Container reports a status update
    #   POST /internal/task_run_events
    #   X-Callback-Token: <token>
    #   { task_run_id: 123, event_type: "status_update", data: { status: "completed", output: "Done" } }
    #
    class TaskRunEventsController < ActionController::API
      before_action :authenticate_callback
      before_action :set_task_run

      # POST /internal/task_run_events
      def create
        case params[:event_type]
        when "status_update"
          handle_status_update(params[:data])
        when "llm_response"
          handle_llm_response(params[:data])
        when "function_execution"
          handle_function_execution(params[:data])
        when "plan_update"
          handle_plan_update(params[:data])
        when "log"
          handle_log(params[:data])
        else
          head :unprocessable_entity
          return
        end

        head :ok
      end

      private

      def authenticate_callback
        token = request.headers["X-Callback-Token"]
        expected = CallbackTokenStore.get(params[:task_run_id])

        unless token.present? && expected.present? &&
               ActiveSupport::SecurityUtils.secure_compare(token, expected)
          head :unauthorized
        end
      end

      def set_task_run
        @task_run = TaskRun.find(params[:task_run_id])
      end

      def handle_status_update(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)

        case data["status"]
        when "running"
          @task_run.start! unless @task_run.status_running?
        when "completed"
          @task_run.complete!(output: data["output"])
        when "failed"
          @task_run.fail!(error: data["error"])
        end

        broadcast_summary_cards
      end

      def handle_llm_response(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)

        agent_version = @task_run.deployed_agent.agent_version
        model_config = agent_version.model_config || {}

        prompt_tokens = data["prompt_tokens"]
        completion_tokens = data["completion_tokens"]
        total_tokens = [ prompt_tokens, completion_tokens ].compact.sum
        total_tokens = nil if total_tokens == 0 && prompt_tokens.nil? && completion_tokens.nil?

        @task_run.llm_responses.create!(
          agent_version: agent_version,
          deployed_agent: @task_run.deployed_agent,
          task_run: @task_run,
          provider: model_config["provider"] || "unknown",
          model: data["model"] || model_config["model"] || "unknown",
          rendered_prompt: data["rendered_prompt"] || data["text"] || "",
          response_text: data["text"],
          tokens_prompt: prompt_tokens,
          tokens_completion: completion_tokens,
          tokens_total: total_tokens,
          cost_usd: data["cost_usd"],
          tool_calls: data["tool_calls"] || [],
          tools_used: data["tools_used"] || [],
          context: data["context"] || {},
          status: "success"
        )

        @task_run.increment_iteration! if data["context"]&.dig("new_iteration")
        broadcast_timeline
        broadcast_summary_cards
      end

      def handle_function_execution(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)

        fn_def = nil
        if data["function_name"].present?
          fn_def = @task_run.deployed_agent.function_definitions.find_by(name: data["function_name"])
        end

        @task_run.function_executions.create!(
          function_definition: fn_def,
          deployed_agent: @task_run.deployed_agent,
          function_name: data["function_name"],
          arguments: data["arguments"] || {},
          result: data["result"],
          success: data["success"] != false,
          error_message: data["error_message"],
          execution_time_ms: data["execution_time_ms"],
          executed_at: Time.current
        )

        broadcast_timeline
        broadcast_summary_cards
      end

      def handle_plan_update(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)

        incoming_plan = data["plan"]
        Rails.logger.info "[TaskRunEventsController] plan_update RECEIVED for task_run #{@task_run.id} — keys=#{incoming_plan&.keys.inspect}, status=#{incoming_plan&.dig('status')}, steps=#{(incoming_plan&.dig('steps') || []).size}"

        metadata = @task_run.metadata || {}
        metadata["plan"] = incoming_plan
        @task_run.update!(metadata: metadata)

        @task_run.reload
        Rails.logger.info "[TaskRunEventsController] plan_update PERSISTED — db metadata.keys=#{@task_run.metadata.keys.inspect}, db plan present?=#{!@task_run.metadata['plan'].nil?}, db steps=#{(@task_run.metadata.dig('plan', 'steps') || []).size}"

        broadcast_execution_plan
        broadcast_planning_phase
      end

      def handle_log(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)

        metadata = @task_run.metadata || {}
        logs = metadata["logs"] || []
        logs << {
          "level" => data["level"] || "info",
          "message" => data["message"],
          "timestamp" => Time.current.iso8601
        }
        metadata["logs"] = logs
        @task_run.update!(metadata: metadata)
      end

      # Turbo Stream broadcasts to keep the UI in sync

      def broadcast_summary_cards
        @task_run.reload
        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{@task_run.id}",
          target: "summary_cards",
          partial: "prompt_tracker/task_runs/summary_cards",
          locals: {
            task_run: @task_run,
            llm_responses: @task_run.llm_responses,
            function_executions: @task_run.function_executions
          }
        )
      rescue StandardError => e
        Rails.logger.error "[TaskRunEventsController] Failed to broadcast summary: #{e.message}"
      end

      def broadcast_timeline
        @task_run.reload
        llm_responses = @task_run.llm_responses.order(created_at: :asc)
        function_executions = @task_run.function_executions.order(created_at: :asc)

        timeline = TaskRunsController.new.send(:build_timeline, llm_responses, function_executions)

        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{@task_run.id}",
          target: "execution_timeline",
          partial: "prompt_tracker/task_runs/timeline",
          locals: { timeline: timeline, task_run: @task_run }
        )
      rescue StandardError => e
        Rails.logger.error "[TaskRunEventsController] Failed to broadcast timeline: #{e.message}"
      end

      def broadcast_planning_phase
        @task_run.reload
        llm_responses = @task_run.llm_responses.order(created_at: :asc)

        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{@task_run.id}",
          target: "planning_phase_card",
          partial: "prompt_tracker/task_runs/planning_phase",
          locals: {
            task_run: @task_run,
            llm_responses: llm_responses,
            agent: @task_run.deployed_agent
          }
        )
      rescue StandardError => e
        Rails.logger.error "[TaskRunEventsController] Failed to broadcast planning: #{e.message}"
      end

      # The task-run show page actually renders _execution_plan.html.erb (id=execution_plan).
      # This broadcast pushes step-status updates to that div live during the run.
      def broadcast_execution_plan
        @task_run.reload

        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{@task_run.id}",
          target: "execution_plan",
          partial: "prompt_tracker/task_runs/execution_plan",
          locals: { task_run: @task_run }
        )
      rescue StandardError => e
        Rails.logger.error "[TaskRunEventsController] Failed to broadcast execution_plan: #{e.message}"
      end
    end
  end
end
