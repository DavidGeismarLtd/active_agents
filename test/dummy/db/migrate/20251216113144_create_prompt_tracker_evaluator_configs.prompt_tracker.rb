# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250112000001)
# Migration to create the evaluator_configs table.
#
# EvaluatorConfigs define which evaluators should run automatically
# for a specific prompt, along with their configuration, weights,
# and dependencies.
#
# This enables:
# - Automatic evaluation when responses are created
# - Multi-evaluator scoring with weighted aggregation
# - Conditional evaluation based on dependencies
# - Per-prompt evaluator configuration
#
# Example:
#   A customer support prompt might have:
#   - LengthEvaluator (weight: 0.15, sync, priority: 1)
#   - KeywordEvaluator (weight: 0.20, sync, priority: 2)
#   - SentimentEvaluator (weight: 0.35, sync, priority: 3, depends_on: length_check)
#   - GPT4JudgeEvaluator (weight: 0.30, async, priority: 4, depends_on: keyword_check)
class CreatePromptTrackerEvaluatorConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_evaluator_configs do |t|
      # Foreign key to the prompt this configuration belongs to
      t.references :prompt,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_prompts },
                   index: true

      # Unique key identifying the evaluator (e.g., "length_check", "gpt4_judge")
      # This is used to look up the evaluator in the EvaluatorRegistry
      t.string :evaluator_key, null: false

      # Whether this evaluator is enabled for automatic evaluation
      # Disabled evaluators are skipped during auto-evaluation
      t.boolean :enabled, default: true, null: false

      # Configuration parameters for this evaluator (stored as JSONB)
      # Example for LengthEvaluator:
      # {
      #   "min_length": 50,
      #   "max_length": 500,
      #   "ideal_min": 100,
      #   "ideal_max": 300
      # }
      # Example for GPT4JudgeEvaluator:
      # {
      #   "judge_model": "gpt-4",
      #   "criteria": ["helpfulness", "accuracy", "tone"],
      #   "custom_instructions": "Evaluate as a customer support manager"
      # }
      t.jsonb :config, default: {}, null: false

      # Execution mode: "sync" or "async"
      # - sync: Runs immediately in the request cycle (for fast evaluators)
      # - async: Runs in a background job (for slow evaluators like LLM judges)
      t.string :run_mode, default: "async", null: false

      # Priority order for execution (higher priority runs first)
      # Used to ensure dependencies run before dependent evaluators
      t.integer :priority, default: 0, null: false

      # Weight for score aggregation (used in weighted_average strategy)
      # Weights should sum to 1.0 across all enabled configs for a prompt
      # Example: 0.15 = 15% of overall score
      t.decimal :weight, precision: 5, scale: 2, default: 1.0, null: false

      # Optional dependency: evaluator_key that must pass before this runs
      # Example: "length_check" - only run if length_check evaluation exists
      # If null, this evaluator has no dependencies (runs independently)
      t.string :depends_on

      # Minimum score required from the dependency evaluator
      # Only run this evaluator if dependency score >= this value
      # Example: 80 - only run if dependency scored 80 or higher
      # If null, defaults to 80
      t.integer :min_dependency_score

      # Standard Rails timestamps
      t.timestamps
    end

    # Ensure each prompt can only have one config per evaluator_key
    add_index :prompt_tracker_evaluator_configs,
              [ :prompt_id, :evaluator_key ],
              unique: true,
              name: "index_evaluator_configs_on_prompt_and_key"

    # Index for finding enabled configs
    add_index :prompt_tracker_evaluator_configs,
              :enabled,
              name: "index_evaluator_configs_on_enabled"

    # Index for finding configs with dependencies
    add_index :prompt_tracker_evaluator_configs,
              :depends_on,
              name: "index_evaluator_configs_on_depends_on"

    # Index for priority ordering
    add_index :prompt_tracker_evaluator_configs,
              [ :prompt_id, :priority ],
              name: "index_evaluator_configs_on_prompt_and_priority"
  end
end
