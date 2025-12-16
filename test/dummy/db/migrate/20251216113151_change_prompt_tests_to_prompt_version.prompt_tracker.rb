# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000006)
class ChangePromptTestsToPromptVersion < ActiveRecord::Migration[7.2]
  def change
    # Remove old foreign key and index
    remove_foreign_key :prompt_tracker_prompt_tests, :prompt_tracker_prompts
    remove_index :prompt_tracker_prompt_tests, name: "index_prompt_tracker_prompt_tests_on_prompt_id"
    remove_index :prompt_tracker_prompt_tests, name: "index_prompt_tracker_prompt_tests_on_prompt_id_and_name"

    # Rename column
    rename_column :prompt_tracker_prompt_tests, :prompt_id, :prompt_version_id

    # Add new foreign key and indexes
    add_foreign_key :prompt_tracker_prompt_tests, :prompt_tracker_prompt_versions, column: :prompt_version_id
    add_index :prompt_tracker_prompt_tests, :prompt_version_id
    add_index :prompt_tracker_prompt_tests, [ :prompt_version_id, :name ], unique: true
  end
end
