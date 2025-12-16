# This migration comes from prompt_tracker (originally 20251211085351)
class RemoveTemplateVariablesFromPromptTests < ActiveRecord::Migration[7.2]
  def change
    remove_column :prompt_tracker_prompt_tests, :template_variables, :jsonb
  end
end
