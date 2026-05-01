# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20260416100000)
class AddContainerExecutionToTaskRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_task_runs, :container_id, :string
    add_column :prompt_tracker_task_runs, :execution_mode, :string,
               default: "in_process", null: false
  end
end
