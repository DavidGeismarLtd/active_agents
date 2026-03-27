# frozen_string_literal: true

# Add task_run associations to existing tracking tables
# Links LLM responses and function executions to task runs
class AddTaskRunAssociations < ActiveRecord::Migration[7.2]
  def change
    # Link LlmResponses to TaskRuns (optional - can be part of conversation OR task run)
    add_reference :prompt_tracker_llm_responses,
                  :task_run,
                  foreign_key: { to_table: :prompt_tracker_task_runs },
                  index: true

    # Link FunctionExecutions to TaskRuns (optional - can be part of conversation OR task run)
    add_reference :prompt_tracker_function_executions,
                  :task_run,
                  foreign_key: { to_table: :prompt_tracker_task_runs },
                  index: true
  end
end
