# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251208000002)
class AddPromptTestRunToHumanEvaluations < ActiveRecord::Migration[7.0]
  def change
    # Add prompt_test_run_id to human_evaluations
    add_reference :prompt_tracker_human_evaluations,
                  :prompt_test_run,
                  foreign_key: { to_table: :prompt_tracker_prompt_test_runs },
                  index: true

    # Drop the old constraint that required exactly one of evaluation_id OR llm_response_id
    execute <<-SQL
      ALTER TABLE prompt_tracker_human_evaluations
      DROP CONSTRAINT IF EXISTS human_evaluation_belongs_to_one
    SQL

    # Add new constraint: exactly one of evaluation_id, llm_response_id, OR prompt_test_run_id
    execute <<-SQL
      ALTER TABLE prompt_tracker_human_evaluations
      ADD CONSTRAINT human_evaluation_belongs_to_one
      CHECK (
        (evaluation_id IS NOT NULL AND llm_response_id IS NULL AND prompt_test_run_id IS NULL) OR
        (evaluation_id IS NULL AND llm_response_id IS NOT NULL AND prompt_test_run_id IS NULL) OR
        (evaluation_id IS NULL AND llm_response_id IS NULL AND prompt_test_run_id IS NOT NULL)
      )
    SQL
  end
end
