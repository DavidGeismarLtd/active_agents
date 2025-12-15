# Phase 1: Database Schema Changes

## 📋 Overview

Modify database schema to support:
1. Polymorphic EvaluatorConfig (belongs to PromptVersion OR PromptTest)
2. LlmResponse test run tracking
3. Evaluation context tracking

## 🗄️ Migrations

### Migration 1: Make EvaluatorConfig Polymorphic

**File:** `db/migrate/YYYYMMDDHHMMSS_make_evaluator_config_polymorphic.rb`

```ruby
class MakeEvaluatorConfigPolymorphic < ActiveRecord::Migration[7.0]
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
    add_index :prompt_tracker_evaluator_configs, [:configurable_type, :configurable_id],
              name: 'index_evaluator_configs_on_configurable'

    # Remove old foreign key and column
    remove_foreign_key :prompt_tracker_evaluator_configs, :prompt_tracker_prompts
    remove_column :prompt_tracker_evaluator_configs, :prompt_id

    # Add new constraint
    add_index :prompt_tracker_evaluator_configs,
              [:configurable_type, :configurable_id, :evaluator_key],
              unique: true,
              name: 'index_evaluator_configs_unique_per_configurable'
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
    remove_index :prompt_tracker_evaluator_configs, name: 'index_evaluator_configs_on_configurable'
    remove_index :prompt_tracker_evaluator_configs, name: 'index_evaluator_configs_unique_per_configurable'
    remove_column :prompt_tracker_evaluator_configs, :configurable_type
    remove_column :prompt_tracker_evaluator_configs, :configurable_id
    remove_column :prompt_tracker_evaluator_configs, :threshold

    # Add back foreign key
    add_foreign_key :prompt_tracker_evaluator_configs, :prompt_tracker_prompts, column: :prompt_id
  end
end
```

### Migration 2: Add Test Run Tracking to LlmResponse

**File:** `db/migrate/YYYYMMDDHHMMSS_add_test_run_tracking_to_llm_responses.rb`

```ruby
class AddTestRunTrackingToLlmResponses < ActiveRecord::Migration[7.0]
  def change
    # Add explicit test run flag
    add_column :prompt_tracker_llm_responses, :is_test_run, :boolean, default: false, null: false

    # Backfill from response_metadata
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE prompt_tracker_llm_responses
          SET is_test_run = true
          WHERE response_metadata->>'test_run' = 'true'
        SQL
      end
    end

    # Add index for filtering
    add_index :prompt_tracker_llm_responses, :is_test_run
  end
end
```

### Migration 3: Add Evaluation Context

**File:** `db/migrate/YYYYMMDDHHMMSS_add_evaluation_context.rb`

```ruby
class AddEvaluationContext < ActiveRecord::Migration[7.0]
  def change
    # Add context enum
    add_column :prompt_tracker_evaluations, :evaluation_context, :string, default: 'tracked_call'

    # Backfill based on llm_response.is_test_run
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE prompt_tracker_evaluations e
          SET evaluation_context = CASE
            WHEN lr.is_test_run = true THEN 'test_run'
            ELSE 'tracked_call'
          END
          FROM prompt_tracker_llm_responses lr
          WHERE e.llm_response_id = lr.id
        SQL
      end
    end

    # Add index
    add_index :prompt_tracker_evaluations, :evaluation_context
  end
end
```

### Migration 4: Migrate PromptTest Evaluator Configs

**File:** `db/migrate/YYYYMMDDHHMMSS_migrate_prompt_test_evaluator_configs.rb`

```ruby
class MigratePromptTestEvaluatorConfigs < ActiveRecord::Migration[7.0]
  def up
    # Migrate JSONB evaluator_configs to EvaluatorConfig records
    PromptTracker::PromptTest.find_each do |test|
      next if test.evaluator_configs.blank?

      test.evaluator_configs.each do |config|
        PromptTracker::EvaluatorConfig.create!(
          configurable: test,
          evaluator_key: config['evaluator_key'],
          threshold: config['threshold'] || 80,
          config: config['config'] || {},
          enabled: true,
          run_mode: 'sync',
          priority: 0,
          weight: 1.0
        )
      end
    end

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
```

## ✅ Validation Checklist

After running migrations:

- [ ] All existing EvaluatorConfigs migrated to PromptVersion
- [ ] No orphaned EvaluatorConfig records
- [ ] LlmResponse.is_test_run correctly set
- [ ] Evaluation.evaluation_context correctly set
- [ ] PromptTest evaluator_configs migrated to EvaluatorConfig records
- [ ] All indexes created
- [ ] Foreign keys intact
- [ ] Can rollback migrations successfully

## 🧪 Testing Migrations

```bash
# Test up migration
rails db:migrate

# Verify data
rails console
> PromptTracker::EvaluatorConfig.where(configurable_type: 'PromptTracker::PromptVersion').count
> PromptTracker::EvaluatorConfig.where(configurable_type: 'PromptTracker::PromptTest').count
> PromptTracker::LlmResponse.where(is_test_run: true).count
> PromptTracker::Evaluation.group(:evaluation_context).count

# Test down migration
rails db:rollback STEP=4

# Verify rollback
rails console
> PromptTracker::EvaluatorConfig.first.respond_to?(:prompt_id) # should be true
```
