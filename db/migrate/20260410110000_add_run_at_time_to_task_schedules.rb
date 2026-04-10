class AddRunAtTimeToTaskSchedules < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_task_schedules, :run_at_time, :string, default: "09:00"
  end
end
