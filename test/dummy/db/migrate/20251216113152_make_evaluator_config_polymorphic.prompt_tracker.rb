# This migration comes from prompt_tracker (originally 20251120074359)
class MakeEvaluatorConfigPolymorphic < ActiveRecord::Migration[7.2]
  def up
    # Add polymorphic columns
    add_column :prompt_tracker_evaluator_configs, :configurable_type, :string
    add_column :prompt_tracker_evaluator_configs, :configurable_id, :bigint

    # Add threshold column (previously only in PromptTest JSONB)
    add_column :prompt_tracker_evaluator_configs, :threshold, :integer

    # Migrate existing data: prompt_id → configurable (PromptVersion)
    # Strategy: Assign configs to the active version of each prompt
    execute <<-SQL
      UPDATE prompt_tracker_evaluator_configs ec
      SET
        configurable_type = 'PromptTracker::PromptVersion',
        configurable_id = (
          SELECT pv.id
          FROM prompt_tracker_prompt_versions pv
          WHERE pv.prompt_id = ec.prompt_id
            AND pv.status = 'active'
          LIMIT 1
        )
      WHERE ec.prompt_id IS NOT NULL
    SQL

    # Handle prompts without active version (assign to latest version)
    execute <<-SQL
      UPDATE prompt_tracker_evaluator_configs ec
      SET
        configurable_id = (
          SELECT pv.id
          FROM prompt_tracker_prompt_versions pv
          WHERE pv.prompt_id = ec.prompt_id
          ORDER BY pv.version_number DESC
          LIMIT 1
        )
      WHERE ec.configurable_id IS NULL AND ec.prompt_id IS NOT NULL
    SQL

    # Add indexes
    add_index :prompt_tracker_evaluator_configs, [ :configurable_type, :configurable_id ],
              name: "index_evaluator_configs_on_configurable"

    # Remove old foreign key and column
    remove_foreign_key :prompt_tracker_evaluator_configs, :prompt_tracker_prompts if foreign_key_exists?(:prompt_tracker_evaluator_configs, :prompt_tracker_prompts)
    remove_column :prompt_tracker_evaluator_configs, :prompt_id

    # Add new constraint
    add_index :prompt_tracker_evaluator_configs,
              [ :configurable_type, :configurable_id, :evaluator_key ],
              unique: true,
              name: "index_evaluator_configs_unique_per_configurable"
  end

  def down
    # Add back prompt_id column
    add_column :prompt_tracker_evaluator_configs, :prompt_id, :bigint

    # Migrate data back: configurable (PromptVersion) → prompt_id
    execute <<-SQL
      UPDATE prompt_tracker_evaluator_configs ec
      SET prompt_id = (
        SELECT pv.prompt_id
        FROM prompt_tracker_prompt_versions pv
        WHERE pv.id = ec.configurable_id
      )
      WHERE ec.configurable_type = 'PromptTracker::PromptVersion'
    SQL

    # Remove polymorphic columns
    remove_index :prompt_tracker_evaluator_configs, name: "index_evaluator_configs_on_configurable"
    remove_index :prompt_tracker_evaluator_configs, name: "index_evaluator_configs_unique_per_configurable"
    remove_column :prompt_tracker_evaluator_configs, :configurable_type
    remove_column :prompt_tracker_evaluator_configs, :configurable_id
    remove_column :prompt_tracker_evaluator_configs, :threshold

    # Add back foreign key
    add_foreign_key :prompt_tracker_evaluator_configs, :prompt_tracker_prompts, column: :prompt_id
  end
end
