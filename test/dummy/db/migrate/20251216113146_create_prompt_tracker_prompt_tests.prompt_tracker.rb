# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000001)
class CreatePromptTrackerPromptTests < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompt_tests do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :prompt_tracker_prompts }
      t.bigint :prompt_test_suite_id

      t.string :name, null: false
      t.text :description

      # Test input
      t.jsonb :template_variables, default: {}, null: false

      # Expected output validation
      t.text :expected_output
      t.jsonb :expected_patterns, default: [], null: false

      # Model configuration for test execution
      t.jsonb :model_config, default: {}, null: false

      # Evaluator configurations with thresholds
      t.jsonb :evaluator_configs, default: [], null: false

      # Test metadata
      t.boolean :enabled, default: true, null: false
      t.jsonb :tags, default: [], null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :prompt_tracker_prompt_tests, :name
    add_index :prompt_tracker_prompt_tests, :enabled
    add_index :prompt_tracker_prompt_tests, :tags, using: :gin
    add_index :prompt_tracker_prompt_tests, [ :prompt_id, :name ], unique: true
  end
end
