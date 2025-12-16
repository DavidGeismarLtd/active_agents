# This migration comes from prompt_tracker (originally 20251203143500)
class FixThresholdScoreTypeInEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def up
    # Convert threshold_score from string to integer in all evaluator configs
    execute <<-SQL
      UPDATE prompt_tracker_evaluator_configs
      SET config = jsonb_set(
        config,
        '{threshold_score}',
        to_jsonb((config->>'threshold_score')::integer),
        true
      )
      WHERE config->>'threshold_score' IS NOT NULL
        AND jsonb_typeof(config->'threshold_score') = 'string'
    SQL
  end

  def down
    # Convert threshold_score back to string (for rollback)
    execute <<-SQL
      UPDATE prompt_tracker_evaluator_configs
      SET config = jsonb_set(
        config,
        '{threshold_score}',
        to_jsonb((config->>'threshold_score')::text),
        true
      )
      WHERE config->>'threshold_score' IS NOT NULL
        AND jsonb_typeof(config->'threshold_score') = 'number'
    SQL
  end
end
