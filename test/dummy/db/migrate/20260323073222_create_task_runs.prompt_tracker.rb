# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20260320000002)
# Create task_runs table to track individual task agent executions
class CreateTaskRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_task_runs do |t|
      # Association to deployed agent
      t.references :deployed_agent,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents },
                   index: true

      # Status tracking
      t.string :status, null: false, default: "queued"
      t.string :trigger_type, null: false # scheduled, manual, api

      # Timing
      t.datetime :started_at
      t.datetime :completed_at

      # Configuration and results
      t.jsonb :variables_used, default: {}, null: false
      t.text :output_summary
      t.text :error_message
      t.jsonb :metadata, default: {}, null: false

      # Execution statistics
      t.integer :llm_calls_count, default: 0, null: false
      t.integer :function_calls_count, default: 0, null: false
      t.integer :iterations_count, default: 0, null: false
      t.decimal :total_cost_usd, precision: 10, scale: 6

      t.timestamps
    end

    # Indexes for common queries
    add_index :prompt_tracker_task_runs, :status
    add_index :prompt_tracker_task_runs, :trigger_type
    add_index :prompt_tracker_task_runs, :started_at
    add_index :prompt_tracker_task_runs, [ :deployed_agent_id, :created_at ],
              name: "index_task_runs_on_agent_and_created"
  end
end
