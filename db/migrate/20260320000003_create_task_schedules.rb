# frozen_string_literal: true

# Create task_schedules table to manage scheduled task execution
class CreateTaskSchedules < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_task_schedules do |t|
      # Association to deployed agent (one schedule per task agent)
      t.references :deployed_agent,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents },
                   index: { unique: true }

      # Schedule type
      t.string :schedule_type, null: false # cron, interval

      # Cron-based scheduling
      t.string :cron_expression

      # Interval-based scheduling
      t.integer :interval_value
      t.string :interval_unit # minutes, hours, days, weeks

      # Configuration
      t.string :timezone, default: "UTC", null: false
      t.boolean :enabled, default: true, null: false

      # Tracking
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.integer :run_count, default: 0, null: false

      t.timestamps
    end

    # Indexes for finding due schedules
    add_index :prompt_tracker_task_schedules, :enabled
    add_index :prompt_tracker_task_schedules, :next_run_at
    add_index :prompt_tracker_task_schedules, [ :enabled, :next_run_at ],
              name: "index_task_schedules_on_enabled_and_next_run"
  end
end
