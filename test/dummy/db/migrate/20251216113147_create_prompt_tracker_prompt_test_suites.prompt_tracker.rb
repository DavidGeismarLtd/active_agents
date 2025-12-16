# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000002)
class CreatePromptTrackerPromptTestSuites < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompt_test_suites do |t|
      t.string :name, null: false
      t.text :description

      # Optional: filter tests by prompt
      t.references :prompt, foreign_key: { to_table: :prompt_tracker_prompts }

      # Suite metadata
      t.boolean :enabled, default: true, null: false
      t.jsonb :tags, default: [], null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :prompt_tracker_prompt_test_suites, :name, unique: true
    add_index :prompt_tracker_prompt_test_suites, :enabled
    add_index :prompt_tracker_prompt_test_suites, :tags, using: :gin
  end
end
