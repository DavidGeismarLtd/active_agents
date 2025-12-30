# frozen_string_literal: true

# Clean up existing data (order matters due to foreign key constraints)
puts "  Cleaning up existing data..."

PromptTracker::Evaluation.delete_all
PromptTracker::TestRun.delete_all  # Delete test runs before LLM responses
PromptTracker::Test.delete_all
PromptTracker::LlmResponse.delete_all
PromptTracker::AbTest.delete_all
PromptTracker::EvaluatorConfig.delete_all
PromptTracker::DatasetRow.delete_all  # Delete dataset rows before datasets
PromptTracker::Dataset.delete_all  # Delete datasets before prompt versions
PromptTracker::PromptVersion.delete_all
PromptTracker::Prompt.delete_all
PromptTracker::Openai::Assistant.delete_all

puts "  ✓ Cleanup complete"
