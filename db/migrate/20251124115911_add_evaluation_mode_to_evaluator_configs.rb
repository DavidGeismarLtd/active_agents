class AddEvaluationModeToEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_evaluator_configs, :evaluation_mode, :string, default: 'scored', null: false
    add_index :prompt_tracker_evaluator_configs, :evaluation_mode
  end
end
