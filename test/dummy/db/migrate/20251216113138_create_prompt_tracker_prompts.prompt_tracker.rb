# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250104000001)
# Migration to create the prompts table.
#
# Prompts are containers for different versions of a prompt template.
# They group all versions of a prompt together and provide metadata
# like name, description, category, and tags.
#
# Example:
#   A prompt named "customer_support_greeting" might have multiple
#   versions as it's refined over time. This table stores the prompt
#   metadata, while prompt_versions stores each specific iteration.
class CreatePromptTrackerPrompts < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompts do |t|
      # Unique identifier for the prompt (e.g., "customer_support_greeting")
      # This is how developers reference the prompt in code
      t.string :name, null: false, index: { unique: true }

      # Human-readable description of what this prompt does
      t.text :description

      # Category for grouping prompts (e.g., "support", "sales", "content")
      t.string :category, index: true

      # Flexible tagging system stored as JSONB array
      # Example: ["customer-facing", "high-priority", "production"]
      t.jsonb :tags, default: []

      # Who created this prompt (user email, system name, etc.)
      t.string :created_by

      # Soft delete timestamp - when null, prompt is active
      # When set, prompt is archived and won't appear in active queries
      t.datetime :archived_at, index: true

      # Standard Rails timestamps
      t.timestamps
    end
  end
end
