# This migration comes from prompt_tracker (originally 20251124115911)
class AddEvaluationModeToEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_evaluator_configs, :evaluation_mode, :string, default: "scored", null: false
    add_index :prompt_tracker_evaluator_configs, :evaluation_mode
  end
end
