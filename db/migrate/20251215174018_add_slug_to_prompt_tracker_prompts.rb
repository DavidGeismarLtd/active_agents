class AddSlugToPromptTrackerPrompts < ActiveRecord::Migration[7.2]
  def up
    # Add slug column
    add_column :prompt_tracker_prompts, :slug, :string

    # Migrate existing data: copy name to slug (names are already in correct format)
    PromptTracker::Prompt.reset_column_information
    PromptTracker::Prompt.find_each do |prompt|
      prompt.update_column(:slug, prompt.name)
    end

    # Make slug non-nullable and add unique index
    change_column_null :prompt_tracker_prompts, :slug, false
    add_index :prompt_tracker_prompts, :slug, unique: true

    # Remove unique constraint from name (keep the index for searching)
    remove_index :prompt_tracker_prompts, :name
    add_index :prompt_tracker_prompts, :name
  end

  def down
    # Restore unique constraint on name
    remove_index :prompt_tracker_prompts, :name
    add_index :prompt_tracker_prompts, :name, unique: true

    # Remove slug column and index
    remove_index :prompt_tracker_prompts, :slug
    remove_column :prompt_tracker_prompts, :slug
  end
end

