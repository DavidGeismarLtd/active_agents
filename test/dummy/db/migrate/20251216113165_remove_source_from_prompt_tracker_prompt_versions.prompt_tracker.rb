# This migration comes from prompt_tracker (originally 20251201103324)
class RemoveSourceFromPromptTrackerPromptVersions < ActiveRecord::Migration[7.2]
  def change
    remove_column :prompt_tracker_prompt_versions, :source, :string
  end
end
