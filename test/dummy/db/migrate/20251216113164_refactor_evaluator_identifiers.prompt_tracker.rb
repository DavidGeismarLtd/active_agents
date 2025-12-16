# This migration comes from prompt_tracker (originally 20251130101219)
class RefactorEvaluatorIdentifiers < ActiveRecord::Migration[7.2]
  def up
    # Step 1: Rename evaluator_key to evaluator_type in evaluator_configs
    # This will now store the full class name instead of a symbol key
    rename_column :prompt_tracker_evaluator_configs, :evaluator_key, :evaluator_type

    # Step 2: Add evaluator_config_id to evaluations
    # This links evaluations to their configuration
    add_column :prompt_tracker_evaluations, :evaluator_config_id, :bigint
    add_index :prompt_tracker_evaluations, :evaluator_config_id

    # Step 3: Update existing data
    # Convert old evaluator_key symbols to class names
    reversible do |dir|
      dir.up do
        # Map old keys to class names
        mapping = {
          "keyword" => "PromptTracker::Evaluators::KeywordEvaluator",
          "llm_judge" => "PromptTracker::Evaluators::LlmJudgeEvaluator",
          "pattern_match" => "PromptTracker::Evaluators::PatternMatchEvaluator",
          "exact_match" => "PromptTracker::Evaluators::ExactMatchEvaluator",
          "length" => "PromptTracker::Evaluators::LengthEvaluator",
          "format" => "PromptTracker::Evaluators::FormatEvaluator",
          "human" => "PromptTracker::Evaluators::HumanEvaluator"
        }

        mapping.each do |old_key, class_name|
          execute <<-SQL
            UPDATE prompt_tracker_evaluator_configs
            SET evaluator_type = '#{class_name}'
            WHERE evaluator_type = '#{old_key}'
          SQL
        end

        # Update evaluations.evaluator_type to use class names
        # Map old evaluator_type values (human/automated/llm_judge) to class names based on evaluator_id patterns
        execute <<-SQL
          UPDATE prompt_tracker_evaluations
          SET evaluator_type = CASE
            WHEN evaluator_id LIKE 'keyword_evaluator%' THEN 'PromptTracker::Evaluators::KeywordEvaluator'
            WHEN evaluator_id LIKE 'llm_judge%' THEN 'PromptTracker::Evaluators::LlmJudgeEvaluator'
            WHEN evaluator_id LIKE 'pattern_match%' THEN 'PromptTracker::Evaluators::PatternMatchEvaluator'
            WHEN evaluator_id LIKE 'exact_match%' THEN 'PromptTracker::Evaluators::ExactMatchEvaluator'
            WHEN evaluator_id LIKE 'length_evaluator%' THEN 'PromptTracker::Evaluators::LengthEvaluator'
            WHEN evaluator_id LIKE 'format_evaluator%' THEN 'PromptTracker::Evaluators::FormatEvaluator'
            WHEN evaluator_type = 'human' OR evaluator_id LIKE '%@%' THEN 'PromptTracker::Evaluators::HumanEvaluator'
            ELSE evaluator_type
          END
        SQL

        # Populate evaluator_config_id from metadata where available
        execute <<-SQL
          UPDATE prompt_tracker_evaluations
          SET evaluator_config_id = (metadata->>'evaluator_config_id')::bigint
          WHERE metadata->>'evaluator_config_id' IS NOT NULL
        SQL
      end
    end
  end

  def down
    # Remove evaluator_config_id
    remove_index :prompt_tracker_evaluations, :evaluator_config_id
    remove_column :prompt_tracker_evaluations, :evaluator_config_id

    # Revert evaluator_type to evaluator_key
    reversible do |dir|
      dir.down do
        # Map class names back to keys
        mapping = {
          "PromptTracker::Evaluators::KeywordEvaluator" => "keyword",
          "PromptTracker::Evaluators::LlmJudgeEvaluator" => "llm_judge",
          "PromptTracker::Evaluators::PatternMatchEvaluator" => "pattern_match",
          "PromptTracker::Evaluators::ExactMatchEvaluator" => "exact_match",
          "PromptTracker::Evaluators::LengthEvaluator" => "length",
          "PromptTracker::Evaluators::FormatEvaluator" => "format",
          "PromptTracker::Evaluators::HumanEvaluator" => "human"
        }

        mapping.each do |class_name, old_key|
          execute <<-SQL
            UPDATE prompt_tracker_evaluator_configs
            SET evaluator_type = '#{old_key}'
            WHERE evaluator_type = '#{class_name}'
          SQL
        end

        # Revert evaluations.evaluator_type to old values
        execute <<-SQL
          UPDATE prompt_tracker_evaluations
          SET evaluator_type = CASE
            WHEN evaluator_type LIKE '%HumanEvaluator' THEN 'human'
            WHEN evaluator_type LIKE '%LlmJudgeEvaluator' THEN 'llm_judge'
            ELSE 'automated'
          END
        SQL
      end
    end

    rename_column :prompt_tracker_evaluator_configs, :evaluator_type, :evaluator_key
  end
end
