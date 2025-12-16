# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251209064448)
# Migration to rename template to user_prompt and add system_prompt
#
# This migration aligns the PromptVersion schema with industry-standard LLM API structure:
# - system_prompt: Sets the AI's role, behavior, and constraints (optional)
# - user_prompt: The actual prompt with variables (required, formerly 'template')
#
# This is a breaking change that renames the 'template' column to 'user_prompt'
# to better reflect its purpose and distinguish it from the new 'system_prompt'.
class RenameTemplateToUserPromptAndAddSystemPrompt < ActiveRecord::Migration[7.2]
  def change
    # Add system_prompt column (optional)
    add_column :prompt_tracker_prompt_versions, :system_prompt, :text

    # Rename template to user_prompt
    rename_column :prompt_tracker_prompt_versions, :template, :user_prompt
  end
end
