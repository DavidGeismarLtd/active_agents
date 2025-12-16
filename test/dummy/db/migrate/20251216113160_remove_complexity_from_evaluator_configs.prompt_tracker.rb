# This migration comes from prompt_tracker (originally 20251126124329)
class RemoveComplexityFromEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def change
    # Remove index first
    remove_index :prompt_tracker_evaluator_configs, name: "index_evaluator_configs_on_depends_on", if_exists: true

    # Remove columns
    remove_column :prompt_tracker_evaluator_configs, :run_mode, :string
    remove_column :prompt_tracker_evaluator_configs, :priority, :integer
    remove_column :prompt_tracker_evaluator_configs, :weight, :decimal
    remove_column :prompt_tracker_evaluator_configs, :depends_on, :string
    remove_column :prompt_tracker_evaluator_configs, :min_dependency_score, :decimal
  end
end
