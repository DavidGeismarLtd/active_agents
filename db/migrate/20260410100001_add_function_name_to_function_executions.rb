class AddFunctionNameToFunctionExecutions < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_function_executions, :function_name, :string
  end
end
