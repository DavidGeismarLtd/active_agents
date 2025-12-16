# This migration comes from prompt_tracker (originally 20251127171611)
class AddPromptTestRunIdToEvaluations < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_evaluations, :prompt_test_run_id, :bigint
    add_index :prompt_tracker_evaluations, :prompt_test_run_id
    add_foreign_key :prompt_tracker_evaluations, :prompt_tracker_prompt_test_runs, column: :prompt_test_run_id
  end
end
