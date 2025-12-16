# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20251208000001)
# Migration to allow HumanEvaluations to be associated with either
# an Evaluation (review of automated evaluation) OR directly with
# an LlmResponse (direct human evaluation of the response).
#
# This enables two use cases:
# 1. Review automated evaluations (existing): human_evaluation.evaluation_id
# 2. Direct human evaluation of responses (new): human_evaluation.llm_response_id
class AddLlmResponseToHumanEvaluations < ActiveRecord::Migration[7.2]
  def change
    # Add optional reference to llm_response
    add_reference :prompt_tracker_human_evaluations,
                  :llm_response,
                  foreign_key: { to_table: :prompt_tracker_llm_responses },
                  index: true

    # Make evaluation_id optional (was previously required)
    change_column_null :prompt_tracker_human_evaluations, :evaluation_id, true

    # Add check constraint to ensure exactly one association is present
    # Either evaluation_id OR llm_response_id must be set, but not both
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE prompt_tracker_human_evaluations
          ADD CONSTRAINT human_evaluation_belongs_to_one
          CHECK (
            (evaluation_id IS NOT NULL AND llm_response_id IS NULL) OR
            (evaluation_id IS NULL AND llm_response_id IS NOT NULL)
          )
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE prompt_tracker_human_evaluations
          DROP CONSTRAINT IF EXISTS human_evaluation_belongs_to_one
        SQL
      end
    end
  end
end
