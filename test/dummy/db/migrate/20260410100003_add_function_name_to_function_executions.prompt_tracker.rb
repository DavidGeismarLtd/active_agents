# This migration comes from prompt_tracker (originally 20260410100001)
class AddFunctionNameToFunctionExecutions < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_function_executions, :function_name, :string
  end
end
