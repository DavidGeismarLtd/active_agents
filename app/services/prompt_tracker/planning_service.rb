# frozen_string_literal: true

module PromptTracker
  # Service for managing task agent execution plans
  #
  # Plans are stored in TaskRun.metadata[:plan] as JSONB and provide:
  # - Structured goal tracking
  # - Step-by-step progress monitoring
  # - Explicit completion signals
  # - Real-time UI updates via Turbo Streams
  #
  # @example Creating a plan
  #   PlanningService.create_plan(task_run, {
  #     goal: "Gather and summarize tech news",
  #     steps: ["Search AI news", "Search cloud news", "Create summary"]
  #   })
  #
  # @example Updating a step
  #   PlanningService.update_step(task_run, {
  #     step_id: "step_1",
  #     status: "completed",
  #     notes: "Found 21,667 articles"
  #   })
  #
  class PlanningService
    # Step statuses
    STEP_STATUSES = %w[pending in_progress completed failed skipped].freeze
    PLAN_STATUSES = %w[pending in_progress completed failed].freeze

    class << self
      # Create a new execution plan
      #
      # @param task_run [TaskRun] The task run to create a plan for
      # @param args [Hash] Plan arguments
      # @option args [String] :goal Clear statement of what to achieve
      # @option args [Array<String>] :steps List of step descriptions
      # @return [Hash] { success: Boolean, plan: Hash, error: String }
      def create_plan(task_run, args)
        Rails.logger.info "[PlanningService] 📋 Creating plan for task run #{task_run.id}"
        Rails.logger.info "[PlanningService] 📋 Args: #{args.inspect}"

        if task_run.metadata&.dig("plan")
          return {
            success: false,
            error: "Plan already exists. Use get_plan() to view it, update_step() to update steps, or add_step() to add new steps."
          }
        end

        goal = args[:goal] || args["goal"]
        steps = args[:steps] || args["steps"]

        return { success: false, error: "Goal is required" } unless goal.present?
        return { success: false, error: "Steps are required" } unless steps.is_a?(Array) && steps.any?

        plan_data = {
          goal: goal,
          created_at: Time.current.iso8601,
          updated_at: Time.current.iso8601,
          status: "in_progress",
          steps: steps.map.with_index do |description, i|
            {
              id: "step_#{i + 1}",
              order: i + 1,
              description: description,
              status: "pending",
              notes: nil,
              started_at: nil,
              completed_at: nil
            }
          end,
          completion_summary: nil
        }

        task_run.metadata ||= {}
        task_run.metadata["plan"] = plan_data
        task_run.save!

        Rails.logger.info "[PlanningService] ✅ Plan created with #{steps.size} steps"
        Rails.logger.info "[PlanningService] ✅ Goal: #{goal}"

        broadcast_plan_update(task_run, "created")

        { success: true, plan: plan_data }
      end

      # Get the current plan
      #
      # @param task_run [TaskRun] The task run
      # @return [Hash] { success: Boolean, plan: Hash, progress_percentage: Integer }
      def get_plan(task_run)
        plan = task_run.metadata&.dig("plan")
        return { success: false, error: "No plan exists" } unless plan

        completed_steps = plan["steps"].count { |s| s["status"] == "completed" }
        total_steps = plan["steps"].size
        progress_percentage = total_steps.zero? ? 0 : (completed_steps.to_f / total_steps * 100).round

        {
          success: true,
          plan: plan,
          progress_percentage: progress_percentage,
          completed_steps: completed_steps,
          total_steps: total_steps
        }
      end

      # Update a step's status and notes
      #
      # @param task_run [TaskRun] The task run
      # @param args [Hash] Update arguments
      # @option args [String] :step_id Step ID (e.g., "step_1")
      # @option args [String] :status New status (pending, in_progress, completed, failed, skipped)
      # @option args [String] :notes Optional notes about the step
      # @return [Hash] { success: Boolean, step: Hash, error: String }
      def update_step(task_run, args)
        Rails.logger.info "[PlanningService] 🔄 Updating step for task run #{task_run.id}"
        Rails.logger.info "[PlanningService] 🔄 Args: #{args.inspect}"

        plan = task_run.metadata&.dig("plan")
        return { success: false, error: "No plan exists" } unless plan

        step_id = args[:step_id] || args["step_id"]
        status = args[:status] || args["status"]
        notes = args[:notes] || args["notes"]

        return { success: false, error: "step_id is required" } unless step_id.present?
        return { success: false, error: "status is required" } unless status.present?
        return { success: false, error: "Invalid status: #{status}" } unless STEP_STATUSES.include?(status)

        step = plan["steps"].find { |s| s["id"] == step_id }
        return { success: false, error: "Step not found: #{step_id}" } unless step

        # Update step
        step["status"] = status
        step["notes"] = notes if notes.present?
        step["started_at"] ||= Time.current.iso8601 if status == "in_progress"
        step["completed_at"] = Time.current.iso8601 if %w[completed failed skipped].include?(status)

        plan["updated_at"] = Time.current.iso8601
        task_run.save!

        Rails.logger.info "[PlanningService] ✅ Step updated: #{step_id} → #{status}"
        Rails.logger.info "[PlanningService] ✅ Notes: #{notes}" if notes.present?

        broadcast_plan_update(task_run, "step_updated", step_id: step_id)

        { success: true, step: step }
      end

      # Add a new step to the plan
      #
      # @param task_run [TaskRun] The task run
      # @param args [Hash] Step arguments
      # @option args [String] :description Step description
      # @option args [String] :after_step_id Optional - insert after this step
      # @return [Hash] { success: Boolean, step: Hash, error: String }
      def add_step(task_run, args)
        plan = task_run.metadata&.dig("plan")
        return { success: false, error: "No plan exists" } unless plan

        description = args[:description] || args["description"]
        after_step_id = args[:after_step_id] || args["after_step_id"]

        return { success: false, error: "description is required" } unless description.present?

        # Find insertion point
        insert_index = if after_step_id.present?
          plan["steps"].index { |s| s["id"] == after_step_id }
        else
          plan["steps"].size - 1
        end

        return { success: false, error: "Step not found: #{after_step_id}" } if after_step_id.present? && insert_index.nil?

        # Create new step
        new_step = {
          id: "step_#{Time.current.to_i}_#{rand(1000)}",
          order: insert_index + 2,
          description: description,
          status: "pending",
          notes: nil,
          started_at: nil,
          completed_at: nil
        }

        plan["steps"].insert(insert_index + 1, new_step)

        # Reorder steps
        plan["steps"].each_with_index do |step, i|
          step["order"] = i + 1
        end

        plan["updated_at"] = Time.current.iso8601
        task_run.save!

        broadcast_plan_update(task_run, "step_added", step_id: new_step["id"])

        { success: true, step: new_step }
      end

      # Mark the task as complete
      #
      # @param task_run [TaskRun] The task run
      # @param args [Hash] Completion arguments
      # @option args [String] :summary Completion summary
      # @return [Hash] { success: Boolean, summary: String, error: String }
      def mark_task_complete(task_run, args)
        Rails.logger.info "[PlanningService] 🎉 Marking task complete for task run #{task_run.id}"
        Rails.logger.info "[PlanningService] 🎉 Args: #{args.inspect}"

        plan = task_run.metadata&.dig("plan")
        return { success: false, error: "No plan exists" } unless plan

        summary = args[:summary] || args["summary"]
        return { success: false, error: "summary is required" } unless summary.present?

        plan["status"] = "completed"
        plan["completion_summary"] = summary
        plan["updated_at"] = Time.current.iso8601

        task_run.output_summary = summary
        task_run.save!

        Rails.logger.info "[PlanningService] ✅ Task marked as complete"
        Rails.logger.info "[PlanningService] ✅ Summary: #{summary[0..100]}..."

        broadcast_plan_update(task_run, "completed")

        { success: true, summary: summary, plan_status: "completed" }
      end

      # Mark the plan as failed
      #
      # @param task_run [TaskRun] The task run
      # @param args [Hash] Failure arguments
      # @option args [String] :error_message Error message
      # @return [Hash] { success: Boolean, error_message: String }
      def mark_plan_failed(task_run, args)
        plan = task_run.metadata&.dig("plan")
        return { success: false, error: "No plan exists" } unless plan

        error_message = args[:error_message] || args["error_message"]
        return { success: false, error: "error_message is required" } unless error_message.present?

        plan["status"] = "failed"
        plan["completion_summary"] = "Failed: #{error_message}"
        plan["updated_at"] = Time.current.iso8601

        task_run.save!

        broadcast_plan_update(task_run, "failed")

        { success: true, error_message: error_message, plan_status: "failed" }
      end

      private

      # Broadcast plan updates to the UI via Turbo Streams
      #
      # @param task_run [TaskRun] The task run
      # @param event_type [String] Event type (created, step_updated, completed, etc.)
      # @param extra_data [Hash] Additional data to pass to the partial
      def broadcast_plan_update(task_run, event_type, extra_data = {})
        Turbo::StreamsChannel.broadcast_replace_to(
          "task_run_#{task_run.id}",
          target: "execution_plan",
          partial: "prompt_tracker/task_runs/execution_plan",
          locals: { task_run: task_run, event: event_type }.merge(extra_data)
        )
      rescue StandardError => e
        Rails.logger.error "[PlanningService] Failed to broadcast plan update: #{e.message}"
        # Don't fail the operation if broadcasting fails
      end
    end
  end
end
