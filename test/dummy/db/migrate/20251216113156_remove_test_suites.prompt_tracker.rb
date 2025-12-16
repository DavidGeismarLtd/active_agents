# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251121000001)
class RemoveTestSuites < ActiveRecord::Migration[7.2]
  def up
    # Remove foreign keys from prompt_test_runs
    if foreign_key_exists?(:prompt_tracker_prompt_test_runs, :prompt_tracker_prompt_test_suite_runs)
      remove_foreign_key :prompt_tracker_prompt_test_runs, :prompt_tracker_prompt_test_suite_runs
    end

    # Remove foreign key from prompt_tests
    if foreign_key_exists?(:prompt_tracker_prompt_tests, :prompt_tracker_prompt_test_suites)
      remove_foreign_key :prompt_tracker_prompt_tests, :prompt_tracker_prompt_test_suites
    end

    # Remove column from prompt_test_runs
    if column_exists?(:prompt_tracker_prompt_test_runs, :prompt_test_suite_run_id)
      remove_column :prompt_tracker_prompt_test_runs, :prompt_test_suite_run_id
    end

    # Remove column from prompt_tests
    if column_exists?(:prompt_tracker_prompt_tests, :prompt_test_suite_id)
      remove_column :prompt_tracker_prompt_tests, :prompt_test_suite_id
    end

    # Drop test suite tables
    drop_table :prompt_tracker_prompt_test_suite_runs if table_exists?(:prompt_tracker_prompt_test_suite_runs)
    drop_table :prompt_tracker_prompt_test_suites if table_exists?(:prompt_tracker_prompt_test_suites)
  end

  def down
    # Recreate test suite tables
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

    create_table :prompt_tracker_prompt_test_suite_runs do |t|
      t.references :prompt_test_suite, null: false, foreign_key: { to_table: :prompt_tracker_prompt_test_suites }

      t.string :status, default: "pending", null: false
      t.integer :total_tests, default: 0, null: false
      t.integer :passed_tests, default: 0, null: false
      t.integer :failed_tests, default: 0, null: false
      t.integer :skipped_tests, default: 0, null: false
      t.integer :error_tests, default: 0, null: false

      t.integer :total_duration_ms
      t.decimal :total_cost_usd, precision: 10, scale: 6

      t.string :triggered_by
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :prompt_tracker_prompt_test_suite_runs, :status
    add_index :prompt_tracker_prompt_test_suite_runs, :created_at

    # Add back foreign keys to prompt_tests and prompt_test_runs
    add_reference :prompt_tracker_prompt_tests, :prompt_test_suite,
                  foreign_key: { to_table: :prompt_tracker_prompt_test_suites }

    add_reference :prompt_tracker_prompt_test_runs, :prompt_test_suite_run,
                  foreign_key: { to_table: :prompt_tracker_prompt_test_suite_runs }
  end
end
