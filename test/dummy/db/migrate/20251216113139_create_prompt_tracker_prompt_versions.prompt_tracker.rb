# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250104000002)
# Migration to create the prompt_versions table.
#
# PromptVersions store specific iterations of a prompt template.
# Each time a prompt's template changes, a new version is created.
# Versions are immutable once they have LLM responses.
#
# Example:
#   Version 1: "Hello {{name}}"
#   Version 2: "Hi {{name}}!" (improved version)
#   Version 3: "Hey {{name}}, how can I help?" (further refined)
class CreatePromptTrackerPromptVersions < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_prompt_versions do |t|
      # Foreign key to the parent prompt
      t.references :prompt,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_prompts },
                   index: true

      # The actual prompt template with variable placeholders
      # Example: "Hello {{customer_name}}, how can I help with {{issue}}?"
      t.text :template, null: false

      # Sequential version number (1, 2, 3, etc.)
      # Incremented each time a new version is created
      t.integer :version_number, null: false

      # Current status of this version
      # - active: Currently being used for new LLM calls
      # - deprecated: Replaced by a newer version
      # - draft: Created via web UI, not yet promoted to production
      t.string :status, null: false, default: "draft", index: true

      # Where this version came from
      # - file: Synced from YAML file (production-ready)
      # - web_ui: Created via web interface (experimental)
      # - api: Created via API (programmatic)
      t.string :source, null: false, default: "file", index: true

      # Schema for variables used in the template
      # Stored as JSONB for flexibility
      # Example: [
      #   { "name": "customer_name", "type": "string", "required": true },
      #   { "name": "issue", "type": "string", "required": false }
      # ]
      t.jsonb :variables_schema, default: []

      # Model configuration (temperature, max_tokens, etc.)
      # Stored as JSONB for flexibility across different providers
      # Example: { "temperature": 0.7, "max_tokens": 150, "top_p": 1.0 }
      t.jsonb :model_config, default: {}

      # Notes about this version (what changed, why, etc.)
      t.text :notes

      # Who created this version
      t.string :created_by

      # Standard Rails timestamps
      t.timestamps
    end

    # Composite index for finding active version of a prompt
    add_index :prompt_tracker_prompt_versions,
              [ :prompt_id, :status ],
              name: "index_prompt_versions_on_prompt_and_status"

    # Unique constraint: only one version number per prompt
    add_index :prompt_tracker_prompt_versions,
              [ :prompt_id, :version_number ],
              unique: true,
              name: "index_prompt_versions_on_prompt_and_version_number"
  end
end
