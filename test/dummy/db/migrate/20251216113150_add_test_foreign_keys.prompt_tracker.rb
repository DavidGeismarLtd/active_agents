# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250115000005)
class AddTestForeignKeys < ActiveRecord::Migration[7.2]
  def change
    # Add foreign key from prompt_tests to prompt_test_suites
    add_foreign_key :prompt_tracker_prompt_tests,
                    :prompt_tracker_prompt_test_suites,
                    column: :prompt_test_suite_id

    add_index :prompt_tracker_prompt_tests, :prompt_test_suite_id

    # Add foreign key from prompt_test_runs to prompt_test_suite_runs
    add_foreign_key :prompt_tracker_prompt_test_runs,
                    :prompt_tracker_prompt_test_suite_runs,
                    column: :prompt_test_suite_run_id

    add_index :prompt_tracker_prompt_test_runs, :prompt_test_suite_run_id
  end
end
