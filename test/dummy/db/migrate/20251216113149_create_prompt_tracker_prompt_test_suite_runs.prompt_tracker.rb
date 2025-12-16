# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000004)
class CreatePromptTrackerPromptTestSuiteRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompt_test_suite_runs do |t|
      t.references :prompt_test_suite, null: false, foreign_key: { to_table: :prompt_tracker_prompt_test_suites }

      # Suite execution status
      t.string :status, null: false, default: "pending"

      # Test counts
      t.integer :total_tests, default: 0, null: false
      t.integer :passed_tests, default: 0, null: false
      t.integer :failed_tests, default: 0, null: false
      t.integer :skipped_tests, default: 0, null: false
      t.integer :error_tests, default: 0, null: false

      # Performance metrics
      t.integer :total_duration_ms
      t.decimal :total_cost_usd, precision: 10, scale: 6

      # Execution context
      t.string :triggered_by
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :prompt_tracker_prompt_test_suite_runs, :status
    add_index :prompt_tracker_prompt_test_suite_runs, :created_at
    add_index :prompt_tracker_prompt_test_suite_runs, [ :prompt_test_suite_id, :created_at ]
  end
end
