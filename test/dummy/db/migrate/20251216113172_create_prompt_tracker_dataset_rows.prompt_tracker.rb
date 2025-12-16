# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251211000002)
# Migration to create dataset_rows table for storing individual test data rows
#
# Each row represents one set of variable values to test against
class CreatePromptTrackerDatasetRows < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_dataset_rows do |t|
      # Association to dataset
      t.references :dataset,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_datasets },
                   index: true

      # The actual variable values (matches dataset.schema)
      t.jsonb :row_data, null: false, default: {}

      # Source tracking
      t.string :source, null: false, default: "manual" # 'manual', 'llm_generated', 'imported'

      # Optional metadata for categorization, tagging, etc.
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # Indexes
    add_index :prompt_tracker_dataset_rows, :created_at
    add_index :prompt_tracker_dataset_rows, :source
  end
end
