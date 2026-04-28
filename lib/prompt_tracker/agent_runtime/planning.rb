# frozen_string_literal: true

require "time"

module PromptTracker
  module AgentRuntime
    # Pure-Ruby plan state management for task agents.
    #
    # Operates on plain Hash structures — no ActiveRecord, no Rails. Safe to
    # load inside the containerized agent runtime.
    #
    # A plan is a Hash of the shape:
    #   {
    #     "goal" => "...",
    #     "status" => "pending" | "in_progress" | "completed" | "failed",
    #     "created_at" => iso8601,
    #     "updated_at" => iso8601,
    #     "steps" => [{ "id" => "step_1", "order" => 1, "description" => "...",
    #                   "status" => "pending", "notes" => nil,
    #                   "started_at" => nil, "completed_at" => nil }, ...],
    #     "completion_summary" => nil
    #   }
    #
    # All methods return { "success" => Boolean, ... } and mutate the plan hash
    # in place (except `create_plan` which builds a new one).
    module Planning
      STEP_STATUSES = %w[pending in_progress completed failed skipped].freeze
      PLAN_STATUSES = %w[pending in_progress completed failed].freeze

      module_function

      # Build a new plan from args. Returns { "success" => ..., "plan" => ... }.
      def create_plan(existing_plan, args)
        return { "success" => false, "error" => "Plan already exists. Use get_plan() to view it." } if existing_plan

        goal = args["goal"] || args[:goal]
        steps = args["steps"] || args[:steps]

        return { "success" => false, "error" => "Goal is required" } if blank?(goal)
        return { "success" => false, "error" => "Steps are required" } unless steps.is_a?(Array) && steps.any?

        now = Time.now.utc.iso8601
        plan = {
          "goal" => goal,
          "created_at" => now,
          "updated_at" => now,
          "status" => "in_progress",
          "steps" => steps.map.with_index do |description, i|
            {
              "id" => "step_#{i + 1}",
              "order" => i + 1,
              "description" => description,
              "status" => "pending",
              "notes" => nil,
              "started_at" => nil,
              "completed_at" => nil
            }
          end,
          "completion_summary" => nil
        }

        { "success" => true, "plan" => plan }
      end

      def get_plan(plan)
        return { "success" => false, "error" => "No plan exists" } unless plan

        total = plan["steps"].size
        completed = plan["steps"].count { |s| s["status"] == "completed" }
        pct = total.zero? ? 0 : (completed.to_f / total * 100).round

        {
          "success" => true,
          "plan" => plan,
          "progress_percentage" => pct,
          "completed_steps" => completed,
          "total_steps" => total
        }
      end

      def update_step(plan, args)
        return { "success" => false, "error" => "No plan exists" } unless plan

        step_id = args["step_id"] || args[:step_id]
        status = args["status"] || args[:status]
        notes = args["notes"] || args[:notes]

        return { "success" => false, "error" => "step_id is required" } if blank?(step_id)
        return { "success" => false, "error" => "status is required" } if blank?(status)
        return { "success" => false, "error" => "Invalid status: #{status}" } unless STEP_STATUSES.include?(status)

        step = plan["steps"].find { |s| s["id"] == step_id }
        return { "success" => false, "error" => "Step not found: #{step_id}" } unless step

        now = Time.now.utc.iso8601
        step["status"] = status
        step["notes"] = notes unless blank?(notes)
        step["started_at"] ||= now if status == "in_progress"
        step["completed_at"] = now if %w[completed failed skipped].include?(status)

        plan["updated_at"] = now

        { "success" => true, "step" => step }
      end

      def add_step(plan, args)
        return { "success" => false, "error" => "No plan exists" } unless plan

        description = args["description"] || args[:description]
        after_step_id = args["after_step_id"] || args[:after_step_id]

        return { "success" => false, "error" => "description is required" } if blank?(description)

        insert_index = if blank?(after_step_id)
          plan["steps"].size - 1
        else
          plan["steps"].index { |s| s["id"] == after_step_id }
        end

        return { "success" => false, "error" => "Step not found: #{after_step_id}" } if !blank?(after_step_id) && insert_index.nil?

        new_step = {
          "id" => "step_#{Time.now.to_i}_#{rand(1000)}",
          "order" => insert_index + 2,
          "description" => description,
          "status" => "pending",
          "notes" => nil,
          "started_at" => nil,
          "completed_at" => nil
        }

        plan["steps"].insert(insert_index + 1, new_step)
        plan["steps"].each_with_index { |s, i| s["order"] = i + 1 }
        plan["updated_at"] = Time.now.utc.iso8601

        { "success" => true, "step" => new_step }
      end

      def mark_task_complete(plan, args)
        return { "success" => false, "error" => "No plan exists" } unless plan

        summary = args["summary"] || args[:summary]
        return { "success" => false, "error" => "summary is required" } if blank?(summary)

        plan["status"] = "completed"
        plan["completion_summary"] = summary
        plan["updated_at"] = Time.now.utc.iso8601

        { "success" => true, "summary" => summary, "plan_status" => "completed" }
      end

      # Force-complete any in-progress steps and mark plan failed. Used when
      # timeout or max_iterations hits with an incomplete plan.
      def force_failure(plan, reason)
        return unless plan

        now = Time.now.utc.iso8601
        failed_count = 0
        plan["steps"].each do |step|
          next unless step["status"] == "in_progress"
          step["status"] = "failed"
          step["notes"] = "#{step['notes']}\n\n[Auto-failed: #{reason}]".strip
          step["completed_at"] = now
          failed_count += 1
        end

        plan["status"] = "failed"
        plan["completion_summary"] =
          "Task failed to complete properly. #{reason}. #{failed_count} step(s) were left incomplete."
        plan["updated_at"] = now

        plan
      end

      def self.blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
