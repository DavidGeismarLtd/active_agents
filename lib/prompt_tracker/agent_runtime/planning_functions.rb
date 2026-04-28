# frozen_string_literal: true

module PromptTracker
  module AgentRuntime
    # OpenAI-style function schemas for the planning toolkit.
    # Returned as plain arrays of hashes so they can be fed directly to any
    # LLM client.
    module PlanningFunctions
      PLANNING_FUNCTION_NAMES = %w[create_plan get_plan update_step add_step mark_task_complete].freeze

      module_function

      # Functions exposed during the planning phase (iteration 0).
      # Only create_plan is available — the agent cannot do anything else yet.
      def planning_phase_functions
        [ create_plan_schema ]
      end

      # Functions exposed during the execution phase (iteration 1+).
      # Includes every plan-manipulation function except create_plan.
      def execution_phase_functions
        [
          get_plan_schema,
          update_step_schema,
          add_step_schema,
          mark_task_complete_schema
        ]
      end

      def planning_function?(name)
        PLANNING_FUNCTION_NAMES.include?(name)
      end

      def create_plan_schema
        {
          "name" => "create_plan",
          "description" => "Create an execution plan with specific steps. MUST be called before starting work on the first iteration.",
          "parameters" => {
            "type" => "object",
            "required" => %w[goal steps],
            "properties" => {
              "goal" => {
                "type" => "string",
                "description" => "Clear statement of what you're trying to achieve"
              },
              "steps" => {
                "type" => "array",
                "description" => "List of 3-7 specific steps to accomplish the goal",
                "items" => { "type" => "string" }
              }
            }
          }
        }
      end

      def get_plan_schema
        {
          "name" => "get_plan",
          "description" => "Get the current execution plan with progress information",
          "parameters" => { "type" => "object", "properties" => {} }
        }
      end

      def update_step_schema
        {
          "name" => "update_step",
          "description" => "Update a step's status and add notes about progress",
          "parameters" => {
            "type" => "object",
            "required" => %w[step_id status],
            "properties" => {
              "step_id" => { "type" => "string", "description" => "Step ID (e.g., 'step_1')" },
              "status" => {
                "type" => "string",
                "enum" => %w[pending in_progress completed failed skipped],
                "description" => "New status for the step"
              },
              "notes" => { "type" => "string", "description" => "Optional notes about what was done" }
            }
          }
        }
      end

      def add_step_schema
        {
          "name" => "add_step",
          "description" => "Add a new step to the plan if you discover additional work needed",
          "parameters" => {
            "type" => "object",
            "required" => [ "description" ],
            "properties" => {
              "description" => { "type" => "string", "description" => "Description of the new step" },
              "after_step_id" => { "type" => "string", "description" => "Optional: Insert after this step ID" }
            }
          }
        }
      end

      def mark_task_complete_schema
        {
          "name" => "mark_task_complete",
          "description" => "Mark the entire task as complete with a summary. MUST be called when all steps are done.",
          "parameters" => {
            "type" => "object",
            "required" => [ "summary" ],
            "properties" => {
              "summary" => {
                "type" => "string",
                "description" => "Comprehensive summary of what was accomplished"
              }
            }
          }
        }
      end
    end
  end
end
