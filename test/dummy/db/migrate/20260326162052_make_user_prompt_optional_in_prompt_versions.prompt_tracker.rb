# This migration comes from prompt_tracker (originally 20260326160312)
class MakeUserPromptOptionalInPromptVersions < ActiveRecord::Migration[7.2]
  def change
    change_column_null :prompt_tracker_prompt_versions, :user_prompt, true
  end
end
