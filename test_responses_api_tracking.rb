#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script to verify that the Responses API now tracks each LLM response
# Run with: rails runner test_responses_api_tracking.rb

puts "🧪 Testing Responses API LLM Response Tracking"
puts "=" * 60

# Find a task agent that uses the Responses API (gpt-5-pro)
agent = PromptTracker::DeployedAgent.joins(:prompt_version)
  .where("prompt_tracker_prompt_versions.model_config->>'model' LIKE ?", "gpt-5%")
  .first

unless agent
  puts "❌ No agent found with gpt-5 model"
  puts "Creating a test agent..."

  pv = PromptTracker::PromptVersion.create!(
    name: "Test Responses API Tracking",
    system_prompt: "You are a test assistant.",
    model_config: {
      "provider" => "openai",
      "model" => "gpt-5-pro",
      "api" => "responses"
    }
  )

  agent = PromptTracker::DeployedAgent.create!(
    prompt_version: pv,
    agent_type: "task_agent",
    slug: "test-responses-tracking-#{Time.now.to_i}",
    task_config: {
      "initial_prompt" => "Test task",
      "execution" => {
        "max_iterations" => 2,
        "timeout_seconds" => 300
      },
      "completion_criteria" => {
        "type" => "auto"
      }
    }
  )
end

puts "✅ Using agent: #{agent.slug}"
puts "   Model: #{agent.prompt_version.model_config['model']}"
puts "   API: #{agent.prompt_version.model_config['api']}"
puts ""

# Count LLM responses before
before_count = PromptTracker::LlmResponse.count
puts "📊 LlmResponse count before: #{before_count}"
puts ""

puts "🚀 Starting task execution..."
puts "   (This will make real API calls and may take a few minutes)"
puts ""

# Execute the task
begin
  result = PromptTracker::ExecuteTaskAgentJob.perform_now(agent.id)
  puts "✅ Task execution completed"
rescue => e
  puts "⚠️  Task execution failed: #{e.message}"
  puts "   (This is OK for testing - we just want to see if responses are tracked)"
end

# Count LLM responses after
after_count = PromptTracker::LlmResponse.count
new_responses = after_count - before_count

puts ""
puts "📊 Results:"
puts "   LlmResponse count after: #{after_count}"
puts "   New LlmResponse records: #{new_responses}"
puts ""

if new_responses > 1
  puts "✅ SUCCESS! Multiple LlmResponse records were created"
  puts "   This means the Responses API is now tracking each continuation call"
else
  puts "❌ ISSUE: Only #{new_responses} LlmResponse record(s) created"
  puts "   Expected multiple records for the function call loop"
end

puts ""
puts "🔍 Checking the latest task run..."

task_run = agent.task_runs.order(created_at: :desc).first
if task_run
  llm_responses = task_run.llm_responses.order(created_at: :asc)
  function_executions = task_run.function_executions.order(created_at: :asc)

  puts "   Task Run ##{task_run.id}"
  puts "   LLM Responses: #{llm_responses.count}"
  puts "   Function Executions: #{function_executions.count}"
  puts ""

  if llm_responses.any?
    puts "   LLM Response Timeline:"
    llm_responses.each_with_index do |resp, i|
      tool_calls_count = resp.tool_calls&.length || 0
      puts "   #{i + 1}. #{resp.created_at.strftime('%H:%M:%S.%L')} - #{tool_calls_count} tool calls"
    end
  end

  puts ""
  puts "🌐 View in browser:"
  puts "   http://localhost:3000/prompt_tracker/agents/#{agent.slug}/runs/#{task_run.id}"
end

puts ""
puts "=" * 60
puts "✅ Test complete!"
