# This migration comes from prompt_tracker (originally 20251120074646)
class MigratePromptTestEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def up
    # Migrate JSONB evaluator_configs to EvaluatorConfig records
    execute <<-SQL
      INSERT INTO prompt_tracker_evaluator_configs (
        configurable_type,
        configurable_id,
        evaluator_key,
        threshold,
        config,
        enabled,
        run_mode,
        priority,
        weight,
        created_at,
        updated_at
      )
      SELECT
        'PromptTracker::PromptTest',
        pt.id,
        ec->>'evaluator_key',
        COALESCE((ec->>'threshold')::integer, 80),
        COALESCE(ec->'config', '{}'::jsonb),
        true,
        'sync',
        0,
        1.0,
        NOW(),
        NOW()
      FROM prompt_tracker_prompt_tests pt,
           jsonb_array_elements(pt.evaluator_configs) AS ec
      WHERE pt.evaluator_configs IS NOT NULL
        AND jsonb_array_length(pt.evaluator_configs) > 0
    SQL

    # Remove JSONB column
    remove_column :prompt_tracker_prompt_tests, :evaluator_configs
  end

  def down
    # Add back JSONB column
    add_column :prompt_tracker_prompt_tests, :evaluator_configs, :jsonb, default: [], null: false

    # Migrate back to JSONB
    PromptTracker::PromptTest.find_each do |test|
      configs = test.evaluator_configs.map do |ec|
        {
          evaluator_key: ec.evaluator_key,
          threshold: ec.threshold,
          config: ec.config
        }
      end
      test.update_column(:evaluator_configs, configs)
    end
  end
end
