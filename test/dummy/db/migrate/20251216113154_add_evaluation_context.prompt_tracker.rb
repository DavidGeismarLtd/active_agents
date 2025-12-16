# This migration comes from prompt_tracker (originally 20251120074559)
class AddEvaluationContext < ActiveRecord::Migration[7.2]
  def change
    # Add context enum
    add_column :prompt_tracker_evaluations, :evaluation_context, :string, default: "tracked_call"

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
