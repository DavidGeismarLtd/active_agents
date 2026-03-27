# frozen_string_literal: true

# ============================================================================
# TASK AGENTS SEEDS
# ============================================================================
# This file creates example task agents with deployed versions and task runs.
# Task agents are autonomous agents that execute multi-step tasks using LLM
# reasoning and function calls.

puts "\n🤖 Seeding Task Agents..."

# ============================================================================
# 1. News Monitoring Task Agent
# ============================================================================

# Get the news analyst prompt version (created in 04c_prompts_with_tools.rb)
news_prompt = PromptTracker::Prompt.find_by(name: "news_analyst")
news_version = news_prompt&.prompt_versions&.active&.first

if news_version
  news_agent = PromptTracker::DeployedAgent.create!(
    prompt_version: news_version,
    name: "Daily Tech News Monitor",
    agent_type: "task",
    task_config: {
      "initial_prompt" => "Monitor technology news and create a daily summary. Focus on AI, cloud computing, and cybersecurity developments.",
      "variables" => {
        "topic" => "technology",
        "focus_areas" => "AI, cloud computing, cybersecurity"
      },
      "execution" => {
        "max_iterations" => 5,
        "timeout_seconds" => 1800
      }
    }
  )

  puts "  ✓ Created 'Daily Tech News Monitor' task agent"

  # Create a completed task run
  completed_run = news_agent.task_runs.create!(
    status: "completed",
    trigger_type: "manual",
    variables_used: {
      "topic" => "artificial intelligence",
      "focus_areas" => "machine learning breakthroughs, AI ethics"
    },
    started_at: 2.hours.ago,
    completed_at: 1.hour.ago,
    output_summary: "Found 5 relevant articles about AI developments. Key findings: New GPT-5 rumors, AI regulation in EU, breakthrough in medical AI diagnostics.",
    iterations_count: 3,
    llm_calls_count: 3,
    function_calls_count: 2,
    total_cost_usd: 0.0234
  )

  puts "  ✓ Created completed task run for news monitor"

  # Create a running task run
  running_run = news_agent.task_runs.create!(
    status: "running",
    trigger_type: "api",
    variables_used: {
      "topic" => "cloud computing",
      "focus_areas" => "AWS, Azure, Google Cloud updates"
    },
    started_at: 10.minutes.ago,
    iterations_count: 1,
    llm_calls_count: 1,
    function_calls_count: 1
  )

  puts "  ✓ Created running task run for news monitor"

  # Create a queued task run
  queued_run = news_agent.task_runs.create!(
    status: "queued",
    trigger_type: "scheduled",
    variables_used: {
      "topic" => "cybersecurity",
      "focus_areas" => "data breaches, security vulnerabilities"
    }
  )

  puts "  ✓ Created queued task run for news monitor"
else
  puts "  ⚠️  Skipping news monitor agent (news_analyst prompt not found)"
end

# ============================================================================
# 2. Tech Support Automation Task Agent
# ============================================================================

tech_support_prompt = PromptTracker::Prompt.find_by(name: "tech_support_assistant_claude")
tech_support_version = tech_support_prompt&.prompt_versions&.active&.first

if tech_support_version
  support_agent = PromptTracker::DeployedAgent.create!(
    prompt_version: tech_support_version,
    name: "Automated Support Ticket Handler",
    agent_type: "task",
    task_config: {
      "initial_prompt" => "Process incoming support tickets: diagnose the issue, search knowledge base for solutions, and either resolve or escalate.",
      "variables" => {
        "issue_description" => "User reports application crashes on startup"
      },
      "execution" => {
        "max_iterations" => 10,
        "timeout_seconds" => 3600
      }
    }
  )

  puts "  ✓ Created 'Automated Support Ticket Handler' task agent"

  # Create a completed successful run
  successful_run = support_agent.task_runs.create!(
    status: "completed",
    trigger_type: "api",
    variables_used: {
      "issue_description" => "Error code E1001 when trying to export data"
    },
    started_at: 3.hours.ago,
    completed_at: 2.hours.ago,
    output_summary: "Issue resolved. Found error code E1001 in knowledge base - caused by insufficient disk space. Provided user with cleanup instructions and verified resolution.",
    iterations_count: 4,
    llm_calls_count: 4,
    function_calls_count: 3,
    total_cost_usd: 0.0156
  )

  puts "  ✓ Created successful support ticket resolution run"

  # Create a failed run
  failed_run = support_agent.task_runs.create!(
    status: "failed",
    trigger_type: "manual",
    variables_used: {
      "issue_description" => "Database connection timeout"
    },
    started_at: 1.hour.ago,
    completed_at: 50.minutes.ago,
    error_message: "Max iterations reached without resolution. Escalated to human support team.",
    iterations_count: 10,
    llm_calls_count: 10,
    function_calls_count: 8,
    total_cost_usd: 0.0423
  )

  puts "  ✓ Created failed support ticket run (escalated)"
else
  puts "  ⚠️  Skipping support agent (tech_support_assistant_claude prompt not found)"
end

puts "\n✅ Task Agents seeded:"
puts "   - 2 deployed task agents"
puts "   - 5 task runs (2 completed, 1 running, 1 queued, 1 failed)"
puts "\n📊 Task Run Status Distribution:"
puts "   - Completed: 2"
puts "   - Running: 1"
puts "   - Queued: 1"
puts "   - Failed: 1"
