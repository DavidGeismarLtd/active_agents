# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_03_26_162052) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "prompt_tracker_ab_tests", force: :cascade do |t|
    t.bigint "prompt_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "hypothesis"
    t.string "status", default: "draft", null: false
    t.string "metric_to_optimize", null: false
    t.string "optimization_direction", default: "minimize", null: false
    t.jsonb "traffic_split", default: {}, null: false
    t.jsonb "variants", default: [], null: false
    t.float "confidence_level", default: 0.95
    t.float "minimum_detectable_effect", default: 0.05
    t.integer "minimum_sample_size", default: 100
    t.jsonb "results", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.string "created_by"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "completed_at" ], name: "index_prompt_tracker_ab_tests_on_completed_at"
    t.index [ "metric_to_optimize" ], name: "index_prompt_tracker_ab_tests_on_metric_to_optimize"
    t.index [ "prompt_id", "status" ], name: "index_prompt_tracker_ab_tests_on_prompt_id_and_status"
    t.index [ "prompt_id" ], name: "index_prompt_tracker_ab_tests_on_prompt_id"
    t.index [ "started_at" ], name: "index_prompt_tracker_ab_tests_on_started_at"
    t.index [ "status" ], name: "index_prompt_tracker_ab_tests_on_status"
  end

  create_table "prompt_tracker_agent_conversations", force: :cascade do |t|
    t.bigint "deployed_agent_id", null: false
    t.string "conversation_id", null: false
    t.jsonb "messages", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_message_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "deployed_agent_id", "conversation_id" ], name: "index_agent_conversations_on_agent_and_conversation", unique: true
    t.index [ "deployed_agent_id" ], name: "index_prompt_tracker_agent_conversations_on_deployed_agent_id"
    t.index [ "expires_at" ], name: "index_prompt_tracker_agent_conversations_on_expires_at"
    t.index [ "last_message_at" ], name: "index_prompt_tracker_agent_conversations_on_last_message_at"
  end

  create_table "prompt_tracker_dataset_rows", force: :cascade do |t|
    t.bigint "dataset_id", null: false
    t.jsonb "row_data", default: {}, null: false
    t.string "source", default: "manual", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_prompt_tracker_dataset_rows_on_created_at"
    t.index [ "dataset_id" ], name: "index_prompt_tracker_dataset_rows_on_dataset_id"
    t.index [ "source" ], name: "index_prompt_tracker_dataset_rows_on_source"
  end

  create_table "prompt_tracker_datasets", force: :cascade do |t|
    t.string "testable_type"
    t.bigint "testable_id"
    t.string "name", null: false
    t.text "description"
    t.jsonb "schema", default: [], null: false
    t.string "created_by"
    t.jsonb "metadata", default: {}, null: false
    t.integer "dataset_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_prompt_tracker_datasets_on_created_at"
    t.index [ "dataset_type" ], name: "index_prompt_tracker_datasets_on_dataset_type"
    t.index [ "testable_type", "testable_id" ], name: "index_prompt_tracker_datasets_on_testable_type_and_testable_id"
  end

  create_table "prompt_tracker_deployed_agent_functions", force: :cascade do |t|
    t.bigint "deployed_agent_id", null: false
    t.bigint "function_definition_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "deployed_agent_id", "function_definition_id" ], name: "index_deployed_agent_functions_unique", unique: true
    t.index [ "deployed_agent_id" ], name: "index_deployed_agent_funcs_on_agent_id"
    t.index [ "function_definition_id" ], name: "index_deployed_agent_funcs_on_func_def_id"
  end

  create_table "prompt_tracker_deployed_agents", force: :cascade do |t|
    t.bigint "prompt_version_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.jsonb "deployment_config", default: {}, null: false
    t.datetime "deployed_at"
    t.datetime "paused_at"
    t.text "error_message"
    t.integer "request_count", default: 0, null: false
    t.datetime "last_request_at"
    t.string "created_by"
    t.text "api_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_prompt_tracker_deployed_agents_on_created_at"
    t.index [ "prompt_version_id" ], name: "index_prompt_tracker_deployed_agents_on_prompt_version_id"
    t.index [ "slug" ], name: "index_prompt_tracker_deployed_agents_on_slug", unique: true
    t.index [ "status" ], name: "index_prompt_tracker_deployed_agents_on_status"
  end

  create_table "prompt_tracker_environment_variables", force: :cascade do |t|
    t.string "name", null: false
    t.string "key", null: false
    t.text "value", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "key" ], name: "index_prompt_tracker_environment_variables_on_key", unique: true
    t.index [ "name" ], name: "index_prompt_tracker_environment_variables_on_name"
  end

  create_table "prompt_tracker_evaluations", force: :cascade do |t|
    t.bigint "llm_response_id"
    t.decimal "score", precision: 10, scale: 2, null: false
    t.decimal "score_min", precision: 10, scale: 2, default: "0.0"
    t.decimal "score_max", precision: 10, scale: 2, default: "5.0"
    t.string "evaluator_type", null: false
    t.string "evaluator_id"
    t.text "feedback"
    t.jsonb "metadata", default: {}
    t.boolean "passed"
    t.bigint "test_run_id"
    t.string "evaluation_context", default: "tracked_call", null: false
    t.bigint "evaluator_config_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "evaluation_context" ], name: "index_prompt_tracker_evaluations_on_evaluation_context"
    t.index [ "evaluator_config_id" ], name: "index_prompt_tracker_evaluations_on_evaluator_config_id"
    t.index [ "evaluator_type", "created_at" ], name: "index_evaluations_on_type_and_created_at"
    t.index [ "evaluator_type" ], name: "index_prompt_tracker_evaluations_on_evaluator_type"
    t.index [ "llm_response_id" ], name: "index_prompt_tracker_evaluations_on_llm_response_id"
    t.index [ "score" ], name: "index_evaluations_on_score"
    t.index [ "test_run_id" ], name: "index_prompt_tracker_evaluations_on_test_run_id"
  end

  create_table "prompt_tracker_evaluator_configs", force: :cascade do |t|
    t.string "configurable_type", null: false
    t.bigint "configurable_id", null: false
    t.string "evaluator_type", null: false
    t.string "evaluator_key"
    t.boolean "enabled", default: true, null: false
    t.integer "priority"
    t.decimal "threshold_score", precision: 10, scale: 2
    t.string "depends_on"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "configurable_type", "configurable_id" ], name: "index_evaluator_configs_on_configurable"
    t.index [ "depends_on" ], name: "index_prompt_tracker_evaluator_configs_on_depends_on"
    t.index [ "enabled" ], name: "index_prompt_tracker_evaluator_configs_on_enabled"
  end

  create_table "prompt_tracker_function_definition_environment_variables", force: :cascade do |t|
    t.bigint "function_definition_id", null: false
    t.bigint "environment_variable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "environment_variable_id" ], name: "index_func_def_env_vars_on_env_var_id"
    t.index [ "function_definition_id", "environment_variable_id" ], name: "index_func_def_env_vars_unique", unique: true
    t.index [ "function_definition_id" ], name: "index_func_def_env_vars_on_func_def_id"
  end

  create_table "prompt_tracker_function_definitions", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.jsonb "parameters", default: {}, null: false
    t.text "code", null: false
    t.string "language", default: "ruby", null: false
    t.string "category"
    t.jsonb "tags", default: []
    t.text "environment_variables"
    t.jsonb "dependencies", default: []
    t.jsonb "example_input", default: {}
    t.jsonb "example_output", default: {}
    t.integer "version", default: 1, null: false
    t.string "created_by"
    t.integer "usage_count", default: 0, null: false
    t.datetime "last_executed_at"
    t.integer "execution_count", default: 0, null: false
    t.integer "average_execution_time_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "lambda_function_name"
    t.string "deployment_status", default: "not_deployed", null: false
    t.datetime "deployed_at"
    t.text "deployment_error"
    t.index [ "category" ], name: "index_prompt_tracker_function_definitions_on_category"
    t.index [ "created_at" ], name: "index_prompt_tracker_function_definitions_on_created_at"
    t.index [ "deployment_status" ], name: "index_prompt_tracker_function_definitions_on_deployment_status"
    t.index [ "lambda_function_name" ], name: "idx_on_lambda_function_name_982a02593f"
    t.index [ "language" ], name: "index_prompt_tracker_function_definitions_on_language"
    t.index [ "last_executed_at" ], name: "index_prompt_tracker_function_definitions_on_last_executed_at"
    t.index [ "name" ], name: "index_prompt_tracker_function_definitions_on_name", unique: true
  end

  create_table "prompt_tracker_function_executions", force: :cascade do |t|
    t.bigint "function_definition_id", null: false
    t.jsonb "arguments", default: {}, null: false
    t.jsonb "result"
    t.boolean "success", default: true, null: false
    t.text "error_message"
    t.integer "execution_time_ms"
    t.datetime "executed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "deployed_agent_id"
    t.bigint "agent_conversation_id"
    t.index [ "agent_conversation_id" ], name: "idx_on_agent_conversation_id_74963468f2"
    t.index [ "deployed_agent_id" ], name: "index_prompt_tracker_function_executions_on_deployed_agent_id"
    t.index [ "executed_at" ], name: "index_prompt_tracker_function_executions_on_executed_at"
    t.index [ "function_definition_id", "executed_at" ], name: "index_function_executions_on_definition_and_executed_at"
    t.index [ "function_definition_id" ], name: "idx_on_function_definition_id_ac862f4b59"
    t.index [ "success" ], name: "index_prompt_tracker_function_executions_on_success"
  end

  create_table "prompt_tracker_human_evaluations", force: :cascade do |t|
    t.bigint "evaluation_id"
    t.bigint "llm_response_id"
    t.bigint "test_run_id"
    t.decimal "score", precision: 10, scale: 2, null: false
    t.text "feedback"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "evaluation_id" ], name: "index_prompt_tracker_human_evaluations_on_evaluation_id"
    t.index [ "llm_response_id" ], name: "index_prompt_tracker_human_evaluations_on_llm_response_id"
    t.index [ "test_run_id" ], name: "index_prompt_tracker_human_evaluations_on_test_run_id"
    t.check_constraint "evaluation_id IS NOT NULL AND llm_response_id IS NULL AND test_run_id IS NULL OR evaluation_id IS NULL AND llm_response_id IS NOT NULL AND test_run_id IS NULL OR evaluation_id IS NULL AND llm_response_id IS NULL AND test_run_id IS NOT NULL", name: "human_evaluation_belongs_to_one"
  end

  create_table "prompt_tracker_llm_responses", force: :cascade do |t|
    t.bigint "prompt_version_id", null: false
    t.text "rendered_prompt", null: false
    t.text "rendered_system_prompt"
    t.jsonb "variables_used", default: {}
    t.text "response_text"
    t.jsonb "response_metadata", default: {}
    t.string "status", default: "pending", null: false
    t.string "error_type"
    t.text "error_message"
    t.integer "response_time_ms"
    t.integer "tokens_prompt"
    t.integer "tokens_completion"
    t.integer "tokens_total"
    t.decimal "cost_usd", precision: 10, scale: 6
    t.string "provider", null: false
    t.string "model", null: false
    t.string "user_id"
    t.string "session_id"
    t.string "environment"
    t.jsonb "context", default: {}
    t.bigint "ab_test_id"
    t.string "ab_variant"
    t.bigint "trace_id"
    t.bigint "span_id"
    t.string "conversation_id"
    t.integer "turn_number"
    t.string "response_id"
    t.string "previous_response_id"
    t.jsonb "tools_used", default: []
    t.jsonb "tool_outputs", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "deployed_agent_id"
    t.bigint "agent_conversation_id"
    t.index [ "ab_test_id", "ab_variant" ], name: "index_llm_responses_on_ab_test_and_variant"
    t.index [ "ab_test_id" ], name: "index_prompt_tracker_llm_responses_on_ab_test_id"
    t.index [ "agent_conversation_id" ], name: "index_prompt_tracker_llm_responses_on_agent_conversation_id"
    t.index [ "conversation_id", "turn_number" ], name: "index_llm_responses_on_conversation_turn"
    t.index [ "conversation_id" ], name: "index_prompt_tracker_llm_responses_on_conversation_id"
    t.index [ "deployed_agent_id" ], name: "index_prompt_tracker_llm_responses_on_deployed_agent_id"
    t.index [ "environment" ], name: "index_prompt_tracker_llm_responses_on_environment"
    t.index [ "model" ], name: "index_prompt_tracker_llm_responses_on_model"
    t.index [ "previous_response_id" ], name: "index_prompt_tracker_llm_responses_on_previous_response_id"
    t.index [ "prompt_version_id" ], name: "index_prompt_tracker_llm_responses_on_prompt_version_id"
    t.index [ "provider", "model", "created_at" ], name: "index_llm_responses_on_provider_model_created_at"
    t.index [ "provider" ], name: "index_prompt_tracker_llm_responses_on_provider"
    t.index [ "response_id" ], name: "index_prompt_tracker_llm_responses_on_response_id", unique: true, where: "(response_id IS NOT NULL)"
    t.index [ "session_id" ], name: "index_prompt_tracker_llm_responses_on_session_id"
    t.index [ "span_id" ], name: "index_prompt_tracker_llm_responses_on_span_id"
    t.index [ "status", "created_at" ], name: "index_llm_responses_on_status_and_created_at"
    t.index [ "status" ], name: "index_prompt_tracker_llm_responses_on_status"
    t.index [ "tools_used" ], name: "index_prompt_tracker_llm_responses_on_tools_used", using: :gin
    t.index [ "trace_id" ], name: "index_prompt_tracker_llm_responses_on_trace_id"
    t.index [ "user_id" ], name: "index_prompt_tracker_llm_responses_on_user_id"
  end

  create_table "prompt_tracker_prompt_test_suite_runs", force: :cascade do |t|
    t.bigint "prompt_test_suite_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "total_tests", default: 0, null: false
    t.integer "passed_tests", default: 0, null: false
    t.integer "failed_tests", default: 0, null: false
    t.integer "skipped_tests", default: 0, null: false
    t.integer "error_tests", default: 0, null: false
    t.integer "total_duration_ms"
    t.decimal "total_cost_usd", precision: 10, scale: 6
    t.string "triggered_by"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_prompt_tracker_prompt_test_suite_runs_on_created_at"
    t.index [ "prompt_test_suite_id", "created_at" ], name: "idx_on_prompt_test_suite_id_created_at_00b03ff2b9"
    t.index [ "prompt_test_suite_id" ], name: "idx_on_prompt_test_suite_id_4251a091be"
    t.index [ "status" ], name: "index_prompt_tracker_prompt_test_suite_runs_on_status"
  end

  create_table "prompt_tracker_prompt_test_suites", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.bigint "prompt_id"
    t.boolean "enabled", default: true, null: false
    t.jsonb "tags", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "enabled" ], name: "index_prompt_tracker_prompt_test_suites_on_enabled"
    t.index [ "name" ], name: "index_prompt_tracker_prompt_test_suites_on_name", unique: true
    t.index [ "prompt_id" ], name: "index_prompt_tracker_prompt_test_suites_on_prompt_id"
    t.index [ "tags" ], name: "index_prompt_tracker_prompt_test_suites_on_tags", using: :gin
  end

  create_table "prompt_tracker_prompt_versions", force: :cascade do |t|
    t.bigint "prompt_id", null: false
    t.text "user_prompt"
    t.text "system_prompt"
    t.integer "version_number", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "variables_schema", default: []
    t.jsonb "model_config", default: {}
    t.jsonb "response_schema"
    t.text "notes"
    t.string "created_by"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "archived_at" ], name: "index_prompt_tracker_prompt_versions_on_archived_at"
    t.index [ "prompt_id", "status" ], name: "index_prompt_versions_on_prompt_and_status"
    t.index [ "prompt_id", "version_number" ], name: "index_prompt_versions_on_prompt_and_version_number", unique: true
    t.index [ "prompt_id" ], name: "index_prompt_tracker_prompt_versions_on_prompt_id"
    t.index [ "status" ], name: "index_prompt_tracker_prompt_versions_on_status"
  end

  create_table "prompt_tracker_prompts", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "category"
    t.jsonb "tags", default: []
    t.string "created_by"
    t.datetime "archived_at"
    t.string "score_aggregation_strategy", default: "weighted_average"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "archived_at" ], name: "index_prompt_tracker_prompts_on_archived_at"
    t.index [ "category" ], name: "index_prompt_tracker_prompts_on_category"
    t.index [ "name" ], name: "index_prompt_tracker_prompts_on_name", unique: true
    t.index [ "score_aggregation_strategy" ], name: "index_prompts_on_aggregation_strategy"
    t.index [ "slug" ], name: "index_prompt_tracker_prompts_on_slug", unique: true
  end

  create_table "prompt_tracker_spans", force: :cascade do |t|
    t.bigint "trace_id", null: false
    t.bigint "parent_span_id"
    t.string "name", null: false
    t.string "span_type"
    t.text "input"
    t.text "output"
    t.string "status", default: "running", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "duration_ms"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "parent_span_id" ], name: "index_prompt_tracker_spans_on_parent_span_id"
    t.index [ "span_type" ], name: "index_prompt_tracker_spans_on_span_type"
    t.index [ "status", "created_at" ], name: "index_prompt_tracker_spans_on_status_and_created_at"
    t.index [ "trace_id" ], name: "index_prompt_tracker_spans_on_trace_id"
  end

  create_table "prompt_tracker_test_runs", force: :cascade do |t|
    t.bigint "test_id", null: false
    t.bigint "dataset_id"
    t.bigint "dataset_row_id"
    t.string "status", default: "pending", null: false
    t.boolean "passed"
    t.text "error_message"
    t.jsonb "assertion_results", default: {}, null: false
    t.integer "passed_evaluators", default: 0, null: false
    t.integer "failed_evaluators", default: 0, null: false
    t.integer "total_evaluators", default: 0, null: false
    t.jsonb "evaluator_results", default: [], null: false
    t.integer "execution_time_ms"
    t.decimal "cost_usd", precision: 10, scale: 6
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "output_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_prompt_tracker_test_runs_on_created_at"
    t.index [ "output_data" ], name: "index_prompt_tracker_test_runs_on_output_data", using: :gin
    t.index [ "passed" ], name: "index_prompt_tracker_test_runs_on_passed"
    t.index [ "status" ], name: "index_prompt_tracker_test_runs_on_status"
    t.index [ "test_id" ], name: "index_prompt_tracker_test_runs_on_test_id"
  end

  create_table "prompt_tracker_tests", force: :cascade do |t|
    t.string "testable_type"
    t.bigint "testable_id"
    t.string "name", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.jsonb "tags", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "enabled" ], name: "index_prompt_tracker_tests_on_enabled"
    t.index [ "name" ], name: "index_prompt_tracker_tests_on_name"
    t.index [ "tags" ], name: "index_prompt_tracker_tests_on_tags", using: :gin
    t.index [ "testable_type", "testable_id" ], name: "index_prompt_tracker_tests_on_testable_type_and_testable_id"
  end

  create_table "prompt_tracker_traces", force: :cascade do |t|
    t.string "name", null: false
    t.text "input"
    t.text "output"
    t.string "status", default: "running", null: false
    t.string "session_id"
    t.string "user_id"
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "duration_ms"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "session_id" ], name: "index_prompt_tracker_traces_on_session_id"
    t.index [ "started_at" ], name: "index_prompt_tracker_traces_on_started_at"
    t.index [ "status", "created_at" ], name: "index_prompt_tracker_traces_on_status_and_created_at"
    t.index [ "user_id" ], name: "index_prompt_tracker_traces_on_user_id"
  end

  add_foreign_key "prompt_tracker_ab_tests", "prompt_tracker_prompts", column: "prompt_id"
  add_foreign_key "prompt_tracker_agent_conversations", "prompt_tracker_deployed_agents", column: "deployed_agent_id"
  add_foreign_key "prompt_tracker_dataset_rows", "prompt_tracker_datasets", column: "dataset_id"
  add_foreign_key "prompt_tracker_deployed_agent_functions", "prompt_tracker_deployed_agents", column: "deployed_agent_id"
  add_foreign_key "prompt_tracker_deployed_agent_functions", "prompt_tracker_function_definitions", column: "function_definition_id"
  add_foreign_key "prompt_tracker_deployed_agents", "prompt_tracker_prompt_versions", column: "prompt_version_id"
  add_foreign_key "prompt_tracker_evaluations", "prompt_tracker_test_runs", column: "test_run_id"
  add_foreign_key "prompt_tracker_function_definition_environment_variables", "prompt_tracker_environment_variables", column: "environment_variable_id"
  add_foreign_key "prompt_tracker_function_definition_environment_variables", "prompt_tracker_function_definitions", column: "function_definition_id"
  add_foreign_key "prompt_tracker_function_executions", "prompt_tracker_agent_conversations", column: "agent_conversation_id"
  add_foreign_key "prompt_tracker_function_executions", "prompt_tracker_deployed_agents", column: "deployed_agent_id"
  add_foreign_key "prompt_tracker_function_executions", "prompt_tracker_function_definitions", column: "function_definition_id"
  add_foreign_key "prompt_tracker_human_evaluations", "prompt_tracker_evaluations", column: "evaluation_id"
  add_foreign_key "prompt_tracker_human_evaluations", "prompt_tracker_llm_responses", column: "llm_response_id"
  add_foreign_key "prompt_tracker_human_evaluations", "prompt_tracker_test_runs", column: "test_run_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_ab_tests", column: "ab_test_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_agent_conversations", column: "agent_conversation_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_deployed_agents", column: "deployed_agent_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_prompt_versions", column: "prompt_version_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_spans", column: "span_id"
  add_foreign_key "prompt_tracker_llm_responses", "prompt_tracker_traces", column: "trace_id"
  add_foreign_key "prompt_tracker_prompt_versions", "prompt_tracker_prompts", column: "prompt_id"
  add_foreign_key "prompt_tracker_spans", "prompt_tracker_spans", column: "parent_span_id"
  add_foreign_key "prompt_tracker_spans", "prompt_tracker_traces", column: "trace_id"
  add_foreign_key "prompt_tracker_test_runs", "prompt_tracker_dataset_rows", column: "dataset_row_id"
  add_foreign_key "prompt_tracker_test_runs", "prompt_tracker_datasets", column: "dataset_id"
  add_foreign_key "prompt_tracker_test_runs", "prompt_tracker_tests", column: "test_id"
end
