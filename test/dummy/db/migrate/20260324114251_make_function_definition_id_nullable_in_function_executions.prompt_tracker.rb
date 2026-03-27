# This migration comes from prompt_tracker (originally 20260324084310)
class MakeFunctionDefinitionIdNullableInFunctionExecutions < ActiveRecord::Migration[7.2]
  def change
    # Allow function_definition_id to be NULL for virtual/planning functions
    # that don't have a corresponding FunctionDefinition record
    change_column_null :prompt_tracker_function_executions, :function_definition_id, true
  end
end
