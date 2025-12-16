# This migration comes from prompt_tracker (originally 20251120074511)
class AddTestRunTrackingToLlmResponses < ActiveRecord::Migration[7.2]
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
