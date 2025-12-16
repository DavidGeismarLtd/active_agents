# This migration comes from prompt_tracker (originally 20250104000006)
class AddAbTestToLlmResponses < ActiveRecord::Migration[7.0]
  def change
    add_reference :prompt_tracker_llm_responses, :ab_test,
                  foreign_key: { to_table: :prompt_tracker_ab_tests },
                  index: true

    add_column :prompt_tracker_llm_responses, :ab_variant, :string

    # Composite index for efficient A/B test queries
    add_index :prompt_tracker_llm_responses, [ :ab_test_id, :ab_variant ],
              name: "index_llm_responses_on_ab_test_and_variant"
  end
end
