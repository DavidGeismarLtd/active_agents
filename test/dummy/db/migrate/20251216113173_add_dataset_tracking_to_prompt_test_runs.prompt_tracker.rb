# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251211000003)
# Migration to add dataset tracking to prompt test runs
#
# This allows us to track:
# - Which dataset was used for a test run
# - Which specific row from the dataset was used
# - Aggregate results across dataset runs
class AddDatasetTrackingToPromptTestRuns < ActiveRecord::Migration[7.2]
  def change
    # Add optional references to dataset and dataset_row
    add_reference :prompt_tracker_prompt_test_runs,
                  :dataset,
                  foreign_key: { to_table: :prompt_tracker_datasets },
                  index: true

    add_reference :prompt_tracker_prompt_test_runs,
                  :dataset_row,
                  foreign_key: { to_table: :prompt_tracker_dataset_rows },
                  index: true

    # Add composite index for querying test runs by dataset
    add_index :prompt_tracker_prompt_test_runs,
              [ :dataset_id, :created_at ],
              name: "index_prompt_test_runs_on_dataset_and_created_at"
  end
end
