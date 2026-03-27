class MakeUserPromptOptionalInPromptVersions < ActiveRecord::Migration[7.2]
  def change
    change_column_null :prompt_tracker_prompt_versions, :user_prompt, true
  end
end
