# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250112000002)
# Migration to add score aggregation strategy to prompts.
#
# NOTE: This column is deprecated and no longer used.
# Evaluations now use simple pass/fail logic instead of aggregated scores.
#
class AddScoreAggregationStrategyToPrompts < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_prompts,
               :score_aggregation_strategy,
               :string,
               default: "weighted_average"

    # Add index for filtering by strategy
    add_index :prompt_tracker_prompts,
              :score_aggregation_strategy,
              name: "index_prompts_on_aggregation_strategy"
  end
end
