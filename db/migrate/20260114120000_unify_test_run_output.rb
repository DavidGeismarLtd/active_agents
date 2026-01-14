# frozen_string_literal: true

# Migration to unify test output storage in TestRun.
#
# Changes:
# 1. Rename conversation_data to output_data (unified storage for all test types)
# 2. Remove llm_response_id from test_runs (tests no longer create LlmResponse records)
# 3. Remove is_test_run from llm_responses (LlmResponse is now production-only)
class UnifyTestRunOutput < ActiveRecord::Migration[7.1]
  def change
    # 1. Rename conversation_data to output_data
    # This column now stores unified output for both single-turn and multi-turn tests
    rename_column :prompt_tracker_test_runs, :conversation_data, :output_data

    # 2. Remove llm_response_id from test_runs
    # Tests no longer create LlmResponse records - all output goes to output_data
    remove_foreign_key :prompt_tracker_test_runs,
                       :prompt_tracker_llm_responses,
                       column: :llm_response_id,
                       if_exists: true
    remove_index :prompt_tracker_test_runs, :llm_response_id, if_exists: true
    remove_column :prompt_tracker_test_runs, :llm_response_id, :bigint

    # 3. Remove is_test_run from llm_responses
    # LlmResponse is now only used for production tracked calls
    remove_index :prompt_tracker_llm_responses, :is_test_run, if_exists: true
    remove_column :prompt_tracker_llm_responses, :is_test_run, :boolean
  end
end
