# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251211000001)
# Migration to create datasets table for storing reusable test data
#
# Datasets allow users to:
# - Create reusable collections of test variables
# - Run tests against multiple data rows
# - Generate test data using LLMs
# - Track which datasets were used in test runs
class CreatePromptTrackerDatasets < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_datasets do |t|
      # Association to prompt version (datasets are version-specific)
      t.references :prompt_version,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_prompt_versions },
                   index: true

      # Basic info
      t.string :name, null: false
      t.text :description

      # Schema derived from prompt_version.variables_schema
      # Stored here for validation and to detect schema drift
      t.jsonb :schema, null: false, default: []

      # Metadata
      t.string :created_by
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # Indexes
    add_index :prompt_tracker_datasets, [ :prompt_version_id, :name ], unique: true
    add_index :prompt_tracker_datasets, :created_at
  end
end
