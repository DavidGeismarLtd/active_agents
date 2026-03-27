# frozen_string_literal: true

# Clean up existing data (order matters due to foreign key constraints)
puts "  Cleaning up existing data..."

PromptTracker::HumanEvaluation.delete_all  # Delete first - has FKs to evaluations, llm_responses, test_runs
PromptTracker::Evaluation.delete_all
PromptTracker::FunctionExecution.delete_all if defined?(PromptTracker::FunctionExecution)  # Delete function executions before llm_responses
PromptTracker::TestRun.delete_all  # Delete test runs before LLM responses
PromptTracker::Test.delete_all
PromptTracker::LlmResponse.delete_all  # Delete LLM responses before task runs (has FK to task_run_id)
PromptTracker::TaskRun.delete_all if defined?(PromptTracker::TaskRun)  # Delete task runs after LLM responses
PromptTracker::AbTest.delete_all
PromptTracker::EvaluatorConfig.delete_all
PromptTracker::DatasetRow.delete_all  # Delete dataset rows before datasets
PromptTracker::Dataset.delete_all  # Delete datasets before prompt versions
PromptTracker::AgentConversation.delete_all  # Delete conversations before deployed agents (messages are JSONB, not separate table)
PromptTracker::DeployedAgentFunction.delete_all if defined?(PromptTracker::DeployedAgentFunction)  # Delete agent-function associations before deployed agents
PromptTracker::DeployedAgent.delete_all  # Delete deployed agents before prompt versions
PromptTracker::PromptVersion.delete_all
PromptTracker::Prompt.delete_all

puts "  ✓ Cleanup complete"
