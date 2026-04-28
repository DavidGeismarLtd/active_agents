# frozen_string_literal: true

module PromptTracker
  # Persistence + broadcasting wrapper around the pure-Ruby
  # AgentRuntime::Planning state machine.
  #
  # The state-mutation logic (creating plans, updating step status, etc.)
  # lives in PromptTracker::AgentRuntime::Planning so it can run inside the
  # containerized agent runtime without ActiveRecord. This service handles
  # the Rails-side concerns: reading from / writing to TaskRun.metadata and
  # broadcasting Turbo Stream updates.
  #
  # @example Creating a plan
  #   PlanningService.create_plan(task_run, {
  #     goal: "Gather and summarize tech news",
  #     steps: ["Search AI news", "Search cloud news", "Create summary"]
  #   })
  class PlanningService
    STEP_STATUSES = AgentRuntime::Planning::STEP_STATUSES
    PLAN_STATUSES = AgentRuntime::Planning::PLAN_STATUSES

    class << self
      def create_plan(task_run, args)
        Rails.logger.info "[PlanningService] 📋 Creating plan for task run #{task_run.id}"
        result = AgentRuntime::Planning.create_plan(load_plan(task_run), normalize(args))

        if result["success"]
          save_plan!(task_run, result["plan"])
          broadcast_plan_update(task_run, "created")
          symbolize_result(result)
        else
          symbolize_result(result)
        end
      end

      def get_plan(task_run)
        symbolize_result(AgentRuntime::Planning.get_plan(load_plan(task_run)))
      end

      def update_step(task_run, args)
        plan = load_plan(task_run)
        result = AgentRuntime::Planning.update_step(plan, normalize(args))

        if result["success"]
          save_plan!(task_run, plan)
          broadcast_plan_update(task_run, "step_updated", step_id: result["step"]["id"])
        end

        symbolize_result(result)
      end

      def add_step(task_run, args)
        plan = load_plan(task_run)
        result = AgentRuntime::Planning.add_step(plan, normalize(args))

        if result["success"]
          save_plan!(task_run, plan)
          broadcast_plan_update(task_run, "step_added", step_id: result["step"]["id"])
        end

        symbolize_result(result)
      end

      def mark_task_complete(task_run, args)
        plan = load_plan(task_run)
        result = AgentRuntime::Planning.mark_task_complete(plan, normalize(args))

        if result["success"]
          save_plan!(task_run, plan)
          task_run.update!(output_summary: result["summary"])
          broadcast_plan_update(task_run, "completed")
        end

        symbolize_result(result)
      end

      def mark_plan_failed(task_run, args)
        plan = load_plan(task_run)
        return { success: false, error: "No plan exists" } unless plan

        error_message = args[:error_message] || args["error_message"]
        return { success: false, error: "error_message is required" } if error_message.blank?

        plan["status"] = "failed"
        plan["completion_summary"] = "Failed: #{error_message}"
        plan["updated_at"] = Time.current.iso8601

        save_plan!(task_run, plan)
        broadcast_plan_update(task_run, "failed")

        { success: true, error_message: error_message, plan_status: "failed" }
      end

      # Force-fail any in-progress steps and mark the plan failed.
      # Used when timeout / max iterations hits with an incomplete plan.
      def force_failure!(task_run, reason)
        plan = load_plan(task_run)
        return unless plan

        AgentRuntime::Planning.force_failure(plan, reason)
        task_run.output_summary = plan["completion_summary"]
        save_plan!(task_run, plan)
        broadcast_plan_update(task_run, "failed")
      end

      def broadcast_plan_update(task_run, event_type, extra_data = {})
        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{task_run.id}",
          target: "execution_plan",
          partial: "prompt_tracker/task_runs/execution_plan",
          locals: { task_run: task_run, event: event_type }.merge(extra_data)
        )
      rescue StandardError => e
        Rails.logger.error "[PlanningService] Failed to broadcast plan update: #{e.message}"
      end

      private

      def load_plan(task_run)
        task_run.metadata&.dig("plan")
      end

      def save_plan!(task_run, plan)
        task_run.metadata ||= {}
        task_run.metadata["plan"] = plan
        task_run.save!
      end

      # Normalize argument keys to strings since Planning module uses string keys.
      def normalize(args)
        return {} if args.nil?
        return args if args.is_a?(Hash) && args.keys.all? { |k| k.is_a?(String) }
        args.to_h.transform_keys(&:to_s)
      end

      # Convert string-keyed result hash to symbol-keyed for backward compat
      # with existing callers that use `result[:success]`, `result[:plan]`, etc.
      def symbolize_result(result)
        result.transform_keys(&:to_sym)
      end
    end
  end
end
