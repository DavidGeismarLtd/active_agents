# frozen_string_literal: true

class UpdatePromptTrackerTaskSchedulesForIntervalPresets < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_task_schedules, :run_at_time, :string, null: false, default: "09:00"

    change_column_default :prompt_tracker_task_schedules,
                          :schedule_type,
                          from: nil,
                          to: "interval"
  end
end
