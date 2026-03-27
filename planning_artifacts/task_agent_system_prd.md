# Task Agent System - Product Requirements Document

**Version:** 1.0
**Date:** 2026-03-20
**Status:** Draft

---

## Executive Summary

Extend the PromptTracker deployed agent system to support **task-based execution** in addition to conversational agents. Task agents are autonomous LLM-powered workers that can be scheduled or manually triggered to complete specific jobs (e.g., "scrape real estate data daily and email results").

### Key Differences: Conversational vs Task Agents

| Aspect | Conversational Agent | Task Agent |
|--------|---------------------|------------|
| **Trigger** | External HTTP request (user message) | Scheduled (cron) or manual trigger |
| **State** | Conversation history with TTL | Task execution history |
| **Input** | User message | Initial command/parameters |
| **Interaction** | Multi-turn reactive dialogue | Autonomous execution with optional multi-turn |
| **Duration** | Short (seconds) | Can be long-running (minutes/hours) |
| **Output** | Response text to user | Structured result via function calls |

---

## Goals

1. **Reuse existing infrastructure**: Extend `DeployedAgent` model with `agent_type` field
2. **Support both scheduled and manual execution**: Cron-based scheduling + on-demand triggers
3. **Enable autonomous multi-turn execution**: Agent can make multiple LLM calls until task complete
4. **Leverage function calling for output**: No built-in output handlers - use functions instead
5. **Provide user-friendly scheduling UI**: Common presets + advanced cron expressions
6. **Track execution history**: Complete audit trail of all task runs

---

## User Stories

### As a developer, I want to:
- Create a task agent that scrapes data from a website daily
- Configure how many LLM iterations the agent can make to complete the task
- Manually trigger a task agent to test it before scheduling
- View execution history with logs, LLM calls, and function executions
- Pause/resume scheduled tasks
- Clone an existing task agent with different parameters

### As a task agent, I should:
- Execute autonomously based on my initial prompt and available functions
- Make multiple LLM calls if needed to complete complex tasks
- Call functions to fetch data, process it, and deliver output
- Handle errors gracefully and report failures
- Respect timeout and iteration limits

---

## Architecture Overview

### Core Models

#### 1. DeployedAgent (Extended)
```ruby
# Add agent_type field to existing model
class DeployedAgent < ApplicationRecord
  # New fields:
  # - agent_type: string (enum: "conversational", "task")
  # - task_config: jsonb (task-specific configuration)

  enum agent_type: { conversational: "conversational", task: "task" }

  # Associations
  has_many :task_runs # Only for task agents
  has_one :task_schedule # Only for task agents
end
```

**task_config structure:**
```json
{
  "initial_prompt": "Fetch all real estate listings from {{source_url}} posted in the last {{time_period}}",
  "variables": {
    "source_url": "https://example.com",
    "time_period": "24 hours"
  },
  "execution": {
    "max_iterations": 5,
    "timeout_seconds": 3600,
    "retry_on_failure": true,
    "max_retries": 3
  },
  "completion_criteria": {
    "type": "auto", // or "explicit" (agent must call mark_complete function)
    "max_function_calls": 20
  }
}
```

#### 2. TaskRun (New Model)
```ruby
class TaskRun < ApplicationRecord
  belongs_to :deployed_agent # The task agent
  has_many :llm_responses # Track all LLM calls during this run
  has_many :function_executions # Track all function calls during this run

  # Fields:
  # - status: enum (queued, running, completed, failed, cancelled, timeout)
  # - trigger_type: enum (scheduled, manual, api)
  # - started_at: datetime
  # - completed_at: datetime
  # - variables_used: jsonb (variables for this specific run)
  # - output_summary: text (final result summary)
  # - error_message: text
  # - metadata: jsonb (stats, iterations_count, etc.)
  # - llm_calls_count: integer
  # - function_calls_count: integer
  # - total_cost_usd: decimal
end
```

#### 3. TaskSchedule (New Model)
```ruby
class TaskSchedule < ApplicationRecord
  belongs_to :deployed_agent # The task agent

  # Fields:
  # - schedule_type: enum (cron, interval)
  # - cron_expression: string (e.g., "0 9 * * *")
  # - interval_value: integer (e.g., 1)
  # - interval_unit: enum (minutes, hours, days, weeks)
  # - enabled: boolean
  # - timezone: string (e.g., "America/New_York")
  # - last_run_at: datetime
  # - next_run_at: datetime
  # - run_count: integer
end
```

---

## Execution Flow

### 1. Task Agent Creation

```ruby
# User creates a task agent via UI or API
task_agent = DeployedAgent.create!(
  agent_type: "task",
  name: "Daily Real Estate Scraper",
  prompt_version: scraper_version,
  task_config: {
    initial_prompt: "Fetch all new real estate listings from {{source_url}} posted in the last {{time_period}}",
    variables: {
      source_url: "https://example-realestate.com",
      time_period: "24 hours"
    },
    execution: {
      max_iterations: 5,
      timeout_seconds: 3600,
      retry_on_failure: true
    }
  }
)

# Create schedule
TaskSchedule.create!(
  deployed_agent: task_agent,
  schedule_type: "cron",
  cron_expression: "0 9 * * *", # Daily at 9am
  timezone: "America/New_York",
  enabled: true
)
```

### 2. Scheduled Execution

```
┌─────────────────────────────────────────────────────────────┐
│ ScheduledTaskRunnerJob (runs every minute via cron)        │
│ - Checks TaskSchedule.enabled.where("next_run_at <= ?")    │
│ - Enqueues ExecuteTaskAgentJob for each due task           │
│ - Updates next_run_at based on cron expression             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ ExecuteTaskAgentJob.perform_later(task_agent_id, options)  │
│ - Creates TaskRun record (status: queued)                  │
│ - Calls TaskAgentRuntimeService                            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ TaskAgentRuntimeService.call(task_agent, task_run)         │
│ - Renders initial prompt with variables                    │
│ - Executes autonomous loop (up to max_iterations)          │
│ - Tracks all LLM calls and function executions             │
│ - Handles completion/failure/timeout                       │
└─────────────────────────────────────────────────────────────┘
```

### 3. Manual Execution

```ruby
# User clicks "Run Now" button in UI
# Or calls API endpoint: POST /agents/:slug/run

# Controller action:
def run_now
  task_run = @agent.task_runs.create!(
    status: "queued",
    trigger_type: "manual",
    variables_used: params[:variables] || @agent.task_config[:variables]
  )

  ExecuteTaskAgentJob.perform_later(@agent.id, task_run.id)

  redirect_to task_run_path(task_run), notice: "Task started"
end
```

### 4. Autonomous Execution Loop

```ruby
# TaskAgentRuntimeService pseudo-code

def execute
  iteration = 0
  max_iterations = task_config.dig(:execution, :max_iterations) || 5

  # Initial prompt
  current_prompt = render_initial_prompt

  loop do
    iteration += 1
    break if iteration > max_iterations

    # Call LLM with function calling enabled
    llm_response = call_llm_with_functions(current_prompt)

    # Track LLM call
    track_llm_response(llm_response)

    # Check if task is complete
    if task_complete?(llm_response)
      mark_task_run_completed(llm_response)
      break
    end

    # If agent wants to continue, use its response as next prompt
    current_prompt = llm_response[:text]
  end

  # Handle timeout/max iterations
  if iteration > max_iterations
    mark_task_run_failed("Max iterations reached")
  end
end

def task_complete?(llm_response)
  # Option 1: Auto-detect (no more function calls, agent says "done")
  # Option 2: Explicit (agent called mark_task_complete function)

  case task_config.dig(:completion_criteria, :type)
  when "auto"
    llm_response[:tool_calls].empty? &&
      llm_response[:text].match?(/task (complete|done|finished)/i)
  when "explicit"
    llm_response[:tool_calls].any? { |tc| tc[:name] == "mark_task_complete" }
  end
end
```

---

## Service Architecture

### New Services

#### 1. TaskAgentRuntimeService
```ruby
module PromptTracker
  # Service for executing task agents autonomously
  #
  # Similar to AgentRuntimeService but:
  # - No conversation state (stateless execution)
  # - Multi-turn autonomous loop
  # - Tracks execution in TaskRun
  #
  class TaskAgentRuntimeService
    def self.call(task_agent:, task_run:, variables: nil)
      new(task_agent: task_agent, task_run: task_run, variables: variables).execute
    end

    def execute
      # 1. Update task_run status to running
      # 2. Render initial prompt with variables
      # 3. Execute autonomous loop
      # 4. Track all LLM calls and function executions
      # 5. Update task_run with final status and output
    end
  end
end
```

#### 2. TaskScheduleCalculator
```ruby
module PromptTracker
  # Calculates next run time for task schedules
  #
  # Supports:
  # - Cron expressions (using fugit gem)
  # - Simple intervals (every N minutes/hours/days/weeks)
  #
  class TaskScheduleCalculator
    def self.next_run_time(schedule)
      case schedule.schedule_type
      when "cron"
        calculate_from_cron(schedule.cron_expression, schedule.timezone)
      when "interval"
        calculate_from_interval(schedule.interval_value, schedule.interval_unit)
      end
    end
  end
end
```

### New Background Jobs

#### 1. ExecuteTaskAgentJob
```ruby
class ExecuteTaskAgentJob < ApplicationJob
  queue_as :default

  def perform(task_agent_id, task_run_id, options = {})
    task_agent = PromptTracker::DeployedAgent.find(task_agent_id)
    task_run = PromptTracker::TaskRun.find(task_run_id)

    PromptTracker::TaskAgentRuntimeService.call(
      task_agent: task_agent,
      task_run: task_run,
      variables: options[:variables]
    )
  rescue StandardError => e
    task_run.update!(
      status: "failed",
      error_message: e.message,
      completed_at: Time.current
    )
    raise # Re-raise for job retry mechanism
  end
end
```

#### 2. ScheduledTaskRunnerJob
```ruby
class ScheduledTaskRunnerJob < ApplicationJob
  queue_as :default

  # This job runs every minute via cron (e.g., via whenever gem or Heroku Scheduler)
  def perform
    # Find all enabled schedules that are due
    due_schedules = PromptTracker::TaskSchedule
      .enabled
      .where("next_run_at <= ?", Time.current)

    due_schedules.find_each do |schedule|
      # Create task run
      task_run = schedule.deployed_agent.task_runs.create!(
        status: "queued",
        trigger_type: "scheduled",
        variables_used: schedule.deployed_agent.task_config[:variables]
      )

      # Enqueue execution job
      ExecuteTaskAgentJob.perform_later(
        schedule.deployed_agent.id,
        task_run.id
      )

      # Update schedule
      schedule.update!(
        last_run_at: Time.current,
        next_run_at: TaskScheduleCalculator.next_run_time(schedule),
        run_count: schedule.run_count + 1
      )
    end
  end
end
```

---

## Database Schema

### Migration 1: Extend DeployedAgents

```ruby
class AddTaskAgentSupportToDeployedAgents < ActiveRecord::Migration[7.0]
  def change
    add_column :prompt_tracker_deployed_agents, :agent_type, :string,
               default: "conversational", null: false
    add_column :prompt_tracker_deployed_agents, :task_config, :jsonb,
               default: {}, null: false

    add_index :prompt_tracker_deployed_agents, :agent_type
  end
end
```

### Migration 2: Create TaskRuns

```ruby
class CreateTaskRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_task_runs do |t|
      t.references :deployed_agent, null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents }

      t.string :status, null: false, default: "queued"
      t.string :trigger_type, null: false # scheduled, manual, api

      t.datetime :started_at
      t.datetime :completed_at

      t.jsonb :variables_used, default: {}, null: false
      t.text :output_summary
      t.text :error_message
      t.jsonb :metadata, default: {}, null: false

      # Stats
      t.integer :llm_calls_count, default: 0, null: false
      t.integer :function_calls_count, default: 0, null: false
      t.integer :iterations_count, default: 0, null: false
      t.decimal :total_cost_usd, precision: 10, scale: 6

      t.timestamps
    end

    add_index :prompt_tracker_task_runs, :status
    add_index :prompt_tracker_task_runs, :trigger_type
    add_index :prompt_tracker_task_runs, :started_at
    add_index :prompt_tracker_task_runs, [:deployed_agent_id, :created_at]
  end
end
```

### Migration 3: Create TaskSchedules

```ruby
class CreateTaskSchedules < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_task_schedules do |t|
      t.references :deployed_agent, null: false,
                   foreign_key: { to_table: :prompt_tracker_deployed_agents },
                   index: { unique: true } # One schedule per task agent

      t.string :schedule_type, null: false # cron, interval

      # Cron-based scheduling
      t.string :cron_expression

      # Interval-based scheduling
      t.integer :interval_value
      t.string :interval_unit # minutes, hours, days, weeks

      t.string :timezone, default: "UTC", null: false
      t.boolean :enabled, default: true, null: false

      t.datetime :last_run_at
      t.datetime :next_run_at
      t.integer :run_count, default: 0, null: false

      t.timestamps
    end

    add_index :prompt_tracker_task_schedules, :enabled
    add_index :prompt_tracker_task_schedules, :next_run_at
    add_index :prompt_tracker_task_schedules, [:enabled, :next_run_at]
  end
end
```

### Migration 4: Add TaskRun associations to existing models

```ruby
class AddTaskRunAssociations < ActiveRecord::Migration[7.0]
  def change
    # Link LlmResponses to TaskRuns
    add_reference :prompt_tracker_llm_responses, :task_run,
                  foreign_key: { to_table: :prompt_tracker_task_runs }

    # Link FunctionExecutions to TaskRuns
    add_reference :prompt_tracker_function_executions, :task_run,
                  foreign_key: { to_table: :prompt_tracker_task_runs }
  end
end
```

---

## UI/UX Design

### 1. Task Agent Creation Flow

**Step 1: Choose Agent Type**
```
┌─────────────────────────────────────────────────────┐
│ Deploy New Agent                                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  What type of agent do you want to deploy?         │
│                                                     │
│  ○ Conversational Agent                            │
│     Interactive chat agent accessible via API      │
│                                                     │
│  ● Task Agent                                      │
│     Autonomous agent that runs on schedule or      │
│     on-demand to complete specific tasks           │
│                                                     │
│                              [Continue →]          │
└─────────────────────────────────────────────────────┘
```

**Step 2: Configure Task Agent**
```
┌─────────────────────────────────────────────────────┐
│ Configure Task Agent                                │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Name: [Daily Real Estate Scraper____________]      │
│                                                     │
│ Prompt Version: [Select Version ▼]                 │
│                                                     │
│ Initial Prompt:                                     │
│ ┌─────────────────────────────────────────────┐   │
│ │ Fetch all new real estate listings from    │   │
│ │ {{source_url}} posted in the last          │   │
│ │ {{time_period}}                            │   │
│ └─────────────────────────────────────────────┘   │
│                                                     │
│ Variables:                                          │
│   source_url: [https://example.com__________]      │
│   time_period: [24 hours___________________]       │
│                                                     │
│ Execution Settings:                                 │
│   Max Iterations: [5___] (1-20)                    │
│   Timeout: [3600___] seconds                       │
│   □ Retry on failure (max 3 retries)              │
│                                                     │
│ Completion Criteria:                                │
│   ● Auto-detect (no function calls + "done")       │
│   ○ Explicit (agent calls mark_task_complete)     │
│                                                     │
│                    [Back] [Create Task Agent]      │
└─────────────────────────────────────────────────────┘
```

**Step 3: Configure Schedule (Optional)**
```
┌─────────────────────────────────────────────────────┐
│ Schedule Task Agent                                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│ ● Enable scheduling                                │
│ ○ Manual trigger only                             │
│                                                     │
│ Schedule Type:                                      │
│ ● Common Intervals                                 │
│   ○ Every hour                                     │
│   ● Every day at [09:00] [America/New_York ▼]     │
│   ○ Every week on [Monday ▼] at [09:00]          │
│   ○ Custom interval: Every [1] [days ▼]          │
│                                                     │
│ ○ Advanced (Cron Expression)                       │
│   [0 9 * * *_____________________________]         │
│   Next run: March 21, 2026 at 9:00 AM EST         │
│                                                     │
│                    [Back] [Create & Schedule]      │
└─────────────────────────────────────────────────────┘
```

### 2. Task Agent Dashboard

```
┌─────────────────────────────────────────────────────────────────────┐
│ Task Agents                                    [+ New Task Agent]   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Filters: [All ▼] [Status: All ▼] [Schedule: All ▼]                │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐   │
│ │ Daily Real Estate Scraper                          ● Active │   │
│ │ Runs daily at 9:00 AM EST                                   │   │
│ │                                                              │   │
│ │ Last run: 2 hours ago (Success) • Next run: in 22 hours    │   │
│ │ Total runs: 47 • Success rate: 95.7%                       │   │
│ │                                                              │   │
│ │ [View Runs] [Run Now] [Edit] [Pause] [⋮]                  │   │
│ └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐   │
│ │ Weekly Analytics Report                        ⏸ Paused    │   │
│ │ Runs every Monday at 8:00 AM UTC                            │   │
│ │                                                              │   │
│ │ Last run: 5 days ago (Success) • Next run: Paused          │   │
│ │ Total runs: 12 • Success rate: 100%                        │   │
│ │                                                              │   │
│ │ [View Runs] [Run Now] [Edit] [Resume] [⋮]                 │   │
│ └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 3. Task Run History

```
┌─────────────────────────────────────────────────────────────────────┐
│ Daily Real Estate Scraper > Run History                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Filters: [Last 30 days ▼] [Status: All ▼] [Trigger: All ▼]        │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐   │
│ │ ✓ Run #47 - Completed                                       │   │
│ │ Triggered: Scheduled • Started: 2 hours ago                 │   │
│ │ Duration: 12.3s • Cost: $0.0045                            │   │
│ │ LLM calls: 3 • Function calls: 5 • Iterations: 2           │   │
│ │                                                              │   │
│ │ Output: Successfully scraped 23 new listings               │   │
│ │                                                              │   │
│ │ [View Details] [View Logs] [Retry]                         │   │
│ └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────┐   │
│ │ ✗ Run #46 - Failed                                          │   │
│ │ Triggered: Scheduled • Started: 1 day ago                   │   │
│ │ Duration: 30.1s • Cost: $0.0023                            │   │
│ │ LLM calls: 2 • Function calls: 3 • Iterations: 2           │   │
│ │                                                              │   │
│ │ Error: Function 'fetch_webpage' timed out after 30s        │   │
│ │                                                              │   │
│ │ [View Details] [View Logs] [Retry]                         │   │
│ └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 4. Task Run Details

```
┌─────────────────────────────────────────────────────────────────────┐
│ Run #47 - Completed                                    [Retry Run]  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Overview                                                            │
│ ├─ Status: Completed ✓                                             │
│ ├─ Trigger: Scheduled                                              │
│ ├─ Started: March 20, 2026 at 9:00:00 AM EST                      │
│ ├─ Completed: March 20, 2026 at 9:00:12 AM EST                    │
│ ├─ Duration: 12.3 seconds                                          │
│ └─ Cost: $0.0045                                                   │
│                                                                     │
│ Execution Stats                                                     │
│ ├─ Iterations: 2 / 5 max                                           │
│ ├─ LLM Calls: 3                                                    │
│ ├─ Function Calls: 5                                               │
│ └─ Tokens: 1,234 prompt + 567 completion = 1,801 total            │
│                                                                     │
│ Variables Used                                                      │
│ ├─ source_url: https://example-realestate.com                     │
│ └─ time_period: 24 hours                                           │
│                                                                     │
│ Output Summary                                                      │
│ ┌─────────────────────────────────────────────────────────────┐   │
│ │ Successfully scraped 23 new real estate listings.          │   │
│ │ Sent email report to user@example.com with CSV attachment. │   │
│ └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│ ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│ Execution Timeline                                                  │
│                                                                     │
│ [Iteration 1] ──────────────────────────────────────────────       │
│                                                                     │
│ 09:00:00  🤖 LLM Call #1                                           │
│           Model: gpt-4o • Tokens: 456 • Cost: $0.0012             │
│           Prompt: "Fetch all new real estate listings from..."    │
│           Response: "I'll fetch the webpage and extract listings"  │
│           Tool calls: fetch_webpage(url="...")                     │
│                                                                     │
│ 09:00:03  ⚡ Function: fetch_webpage                               │
│           Duration: 2.1s • Success ✓                               │
│           Result: HTML content (45KB)                              │
│                                                                     │
│ [Iteration 2] ──────────────────────────────────────────────       │
│                                                                     │
│ 09:00:05  🤖 LLM Call #2                                           │
│           Model: gpt-4o • Tokens: 678 • Cost: $0.0018             │
│           Prompt: "Parse the HTML and extract listing data"        │
│           Tool calls: parse_html(...), format_csv(...)            │
│                                                                     │
│ 09:00:07  ⚡ Function: parse_html                                  │
│           Duration: 1.8s • Success ✓                               │
│           Result: 23 listings extracted                            │
│                                                                     │
│ 09:00:09  ⚡ Function: format_csv                                  │
│           Duration: 0.3s • Success ✓                               │
│           Result: CSV file (3.2KB)                                 │
│                                                                     │
│ 09:00:10  🤖 LLM Call #3                                           │
│           Model: gpt-4o • Tokens: 234 • Cost: $0.0006             │
│           Prompt: "Send the CSV report via email"                  │
│           Tool calls: send_email(...)                              │
│                                                                     │
│ 09:00:11  ⚡ Function: send_email                                  │
│           Duration: 1.1s • Success ✓                               │
│           Result: Email sent successfully                          │
│                                                                     │
│ 09:00:12  ✓ Task completed (no more function calls)               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## API Endpoints

### Task Agent Management

```
POST   /prompt_tracker/agents
  - Create new agent (conversational or task)
  - Body: { agent_type: "task", name: "...", task_config: {...}, ... }

GET    /prompt_tracker/agents/:slug
  - View agent details (works for both types)

PATCH  /prompt_tracker/agents/:slug
  - Update agent configuration

DELETE /prompt_tracker/agents/:slug
  - Delete agent

POST   /prompt_tracker/agents/:slug/pause
  - Pause agent (stops scheduled runs for task agents)

POST   /prompt_tracker/agents/:slug/resume
  - Resume agent
```

### Task Execution

```
POST   /prompt_tracker/agents/:slug/run
  - Manually trigger a task agent
  - Body: { variables: { source_url: "...", ... } } (optional)
  - Response: { task_run_id: 123, status: "queued" }

GET    /prompt_tracker/agents/:slug/runs
  - List all task runs for this agent
  - Query params: status, trigger_type, page, per_page

GET    /prompt_tracker/task_runs/:id
  - View task run details

POST   /prompt_tracker/task_runs/:id/cancel
  - Cancel a running task

POST   /prompt_tracker/task_runs/:id/retry
  - Retry a failed task run
```

### Task Scheduling

```
POST   /prompt_tracker/agents/:slug/schedule
  - Create or update schedule for task agent
  - Body: { schedule_type: "cron", cron_expression: "0 9 * * *", ... }

GET    /prompt_tracker/agents/:slug/schedule
  - View current schedule

DELETE /prompt_tracker/agents/:slug/schedule
  - Remove schedule (task becomes manual-only)

POST   /prompt_tracker/agents/:slug/schedule/enable
  - Enable schedule

POST   /prompt_tracker/agents/:slug/schedule/disable
  - Disable schedule (pause scheduled runs)
```

---

## Implementation Phases

### Phase 1: Core Task Agent Infrastructure (Week 1-2)
- [ ] Database migrations (agent_type, task_runs, task_schedules)
- [ ] Extend DeployedAgent model with task agent support
- [ ] Create TaskRun and TaskSchedule models
- [ ] Implement TaskAgentRuntimeService (basic single-iteration)
- [ ] Create ExecuteTaskAgentJob
- [ ] Add manual trigger API endpoint
- [ ] Basic UI for creating task agents
- [ ] Basic UI for viewing task runs

### Phase 2: Autonomous Multi-Turn Execution (Week 3)
- [ ] Implement autonomous loop in TaskAgentRuntimeService
- [ ] Add max_iterations and timeout support
- [ ] Implement completion criteria (auto-detect and explicit)
- [ ] Add iteration tracking and stats
- [ ] Enhanced task run details UI with timeline
- [ ] Add retry mechanism for failed runs

### Phase 3: Scheduling System (Week 4)
- [ ] Implement TaskScheduleCalculator service
- [ ] Create ScheduledTaskRunnerJob
- [ ] Add cron expression support (using fugit gem)
- [ ] Add interval-based scheduling
- [ ] Schedule management UI
- [ ] Timezone support
- [ ] Next run time calculation and display

### Phase 4: Polish & Advanced Features (Week 5)
- [ ] Task agent dashboard with stats
- [ ] Advanced filtering and search
- [ ] Task run comparison
- [ ] Clone task agent feature
- [ ] Bulk operations (pause/resume multiple agents)
- [ ] Email notifications for failures
- [ ] Webhook notifications
- [ ] Cost tracking and budgets

---

## Technical Considerations

### 1. Scheduling Infrastructure

**Option A: Use existing Rails scheduler (whenever gem)**
```ruby
# config/schedule.rb
every 1.minute do
  runner "ScheduledTaskRunnerJob.perform_later"
end
```

**Option B: Use Sidekiq-cron or Sidekiq-scheduler**
```ruby
# More robust for production, built-in retry, monitoring
```

**Recommendation**: Start with Option A for simplicity, migrate to Option B for production.

### 2. Long-Running Tasks

- Use ActiveJob with Sidekiq for background processing
- Set appropriate timeouts in task_config
- Implement graceful cancellation
- Store progress updates in TaskRun.metadata
- Consider using Sidekiq Pro for better monitoring

### 3. Function Execution for Output

**Example functions users can create:**

```ruby
# send_email function
def execute(to:, subject:, body:, attachment: nil)
  # Use ActionMailer or SendGrid API
  # Return success/failure
end

# post_to_webhook function
def execute(url:, data:, headers: {})
  # HTTP POST to webhook
  # Return response
end

# upload_to_s3 function
def execute(bucket:, key:, content:, content_type: "text/plain")
  # Upload to S3
  # Return S3 URL
end

# save_to_database function
def execute(table:, data:)
  # Insert into custom table
  # Return record ID
end
```

### 4. Error Handling

- Retry failed tasks automatically (configurable)
- Track error patterns and alert users
- Provide detailed error messages in task run
- Allow manual retry from UI
- Implement circuit breaker for repeatedly failing tasks

### 5. Cost Management

- Track total cost per task run
- Set budget limits per task agent
- Alert when costs exceed threshold
- Show cost trends over time

### 6. Security

- Task agents use same API key authentication as conversational agents
- Rate limiting applies to task execution
- Function execution happens in sandboxed Lambda environment
- Validate all user inputs in task_config

---

## Success Metrics

### User Adoption
- Number of task agents created
- Percentage of users creating task agents vs conversational agents
- Task agent retention rate (still active after 30 days)

### Execution Quality
- Task run success rate (target: >95%)
- Average execution time
- Function call success rate
- Cost per task run

### User Satisfaction
- Time to create first task agent
- Number of manual triggers vs scheduled runs
- Task agent clone rate (indicates usefulness)

---

## Example Use Cases

### 1. Daily Real Estate Scraper
```
Agent scrapes real estate website daily, extracts new listings,
formats as CSV, emails to user.

Functions needed:
- fetch_webpage(url)
- parse_html(html, schema)
- format_csv(data)
- send_email(to, subject, attachment)
```

### 2. Weekly Analytics Report
```
Agent queries database for weekly metrics, generates charts,
creates PDF report, uploads to S3, posts to Slack.

Functions needed:
- query_database(sql)
- generate_chart(data, type)
- create_pdf(content)
- upload_to_s3(bucket, key, content)
- post_to_slack(channel, message, attachments)
```

### 3. Hourly Competitor Price Monitor
```
Agent checks competitor prices every hour, compares to our prices,
alerts if competitor price drops below threshold.

Functions needed:
- fetch_competitor_prices(urls)
- get_our_prices(product_ids)
- send_alert(message, urgency)
```

### 4. Daily Social Media Content Generator
```
Agent generates social media posts based on trending topics,
creates images, schedules posts via Buffer API.

Functions needed:
- get_trending_topics(platform)
- generate_image(prompt)
- schedule_post(platform, content, image, time)
```

---

## Open Questions

1. **Should task agents support streaming output?**
   - Real-time progress updates via WebSocket?
   - Or just final result?

2. **Should we support task agent chaining?**
   - Task A completes → triggers Task B
   - Or keep it simple for v1?

3. **Should we support conditional scheduling?**
   - "Run only if previous run failed"
   - "Run only on weekdays"
   - Or just basic cron for v1?

4. **Should we support task agent templates?**
   - Pre-built task agents for common use cases
   - One-click deploy with customization

5. **Should we support task agent versioning?**
   - Track changes to task_config over time
   - Rollback to previous version

---

## Conclusion

This PRD outlines a comprehensive task agent system that extends PromptTracker's deployed agent infrastructure to support autonomous, scheduled task execution. By reusing existing models and services, we can deliver this feature efficiently while maintaining consistency with the conversational agent system.

The phased implementation approach allows us to deliver value incrementally:
1. **Phase 1**: Basic task agents with manual triggers
2. **Phase 2**: Autonomous multi-turn execution
3. **Phase 3**: Scheduling system
4. **Phase 4**: Polish and advanced features

This design leverages the existing function calling system for output delivery, keeping the architecture simple and flexible while enabling powerful use cases like data scraping, report generation, and automated monitoring.
