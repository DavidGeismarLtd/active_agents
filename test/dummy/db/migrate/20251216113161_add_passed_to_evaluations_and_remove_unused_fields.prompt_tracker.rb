# This migration comes from prompt_tracker (originally 20251127164335)
class AddPassedToEvaluationsAndRemoveUnusedFields < ActiveRecord::Migration[7.2]
  def change
    # Add passed boolean to evaluations
    add_column :prompt_tracker_evaluations, :passed, :boolean
    add_index :prompt_tracker_evaluations, :passed

    # Backfill passed based on score (normalized score >= 0.8 = passed)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE prompt_tracker_evaluations
          SET passed = CASE
            WHEN (score - score_min) / NULLIF((score_max - score_min), 0) >= 0.8 THEN true
            ELSE false
          END
        SQL
      end
    end

    # Remove criteria_scores from evaluations (no longer used)
    remove_column :prompt_tracker_evaluations, :criteria_scores, :jsonb, default: {}

    # Remove score_aggregation_strategy from prompts (no longer used)
    remove_column :prompt_tracker_prompts, :score_aggregation_strategy, :string, default: "weighted_average"
    remove_index :prompt_tracker_prompts, name: "index_prompts_on_aggregation_strategy", if_exists: true
  end
end
