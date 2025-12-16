# This migration comes from prompt_tracker (originally 20251129203532)
class RemoveEvaluationModeAndThresholdFromEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def change
    # Remove evaluation_mode and threshold columns from evaluator_configs
    # These fields are no longer needed - any threshold/mode logic should be stored in the config JSONB column
    remove_column :prompt_tracker_evaluator_configs, :evaluation_mode, :string
    remove_column :prompt_tracker_evaluator_configs, :threshold, :integer
  end
end
