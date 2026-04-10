# This migration comes from prompt_tracker (originally 20260410110000)
class AddRunAtTimeToTaskSchedules < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_task_schedules, :run_at_time, :string, default: "09:00"
  end
end
