# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000003)
class CreatePromptTrackerPromptTestRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompt_test_runs do |t|
      t.references :prompt_test, null: false, foreign_key: { to_table: :prompt_tracker_prompt_tests }
      t.references :prompt_version, null: false, foreign_key: { to_table: :prompt_tracker_prompt_versions }
      t.references :llm_response, foreign_key: { to_table: :prompt_tracker_llm_responses }
      t.bigint :prompt_test_suite_run_id

      # Test execution status
      t.string :status, null: false, default: "pending"

      # Test results
      t.boolean :passed
      t.text :error_message
      t.jsonb :assertion_results, default: {}, null: false

      # Evaluator results
      t.integer :passed_evaluators, default: 0, null: false
      t.integer :failed_evaluators, default: 0, null: false
      t.integer :total_evaluators, default: 0, null: false
      t.jsonb :evaluator_results, default: [], null: false

      # Performance metrics
      t.integer :execution_time_ms
      t.decimal :cost_usd, precision: 10, scale: 6

      # Context
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :prompt_tracker_prompt_test_runs, :status
    add_index :prompt_tracker_prompt_test_runs, :passed
    add_index :prompt_tracker_prompt_test_runs, :created_at
    add_index :prompt_tracker_prompt_test_runs, [ :prompt_test_id, :created_at ]
  end
end
