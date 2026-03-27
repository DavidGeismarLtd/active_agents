# Task Agent System - Executive Summary

**Date:** 2026-03-20  
**Status:** Ready for Implementation

---

## Overview

Extend PromptTracker's deployed agent system to support **autonomous task-based execution** in addition to conversational agents. Task agents are LLM-powered workers that run on schedules or on-demand to complete specific jobs.

---

## Key Design Decisions

### ✅ Reuse DeployedAgent Model
- Add `agent_type` enum field: `"conversational"` or `"task"`
- Add `task_config` jsonb field for task-specific configuration
- **Rationale**: Maximize code reuse, maintain consistency

### ✅ Support Both Scheduled & Manual Triggers
- **Scheduled**: Cron expressions or simple intervals (hourly, daily, weekly)
- **Manual**: "Run Now" button in UI or API endpoint
- **Rationale**: Flexibility for testing and production use

### ✅ No Built-in Output Handlers
- Output delivery via **function calls** (send_email, post_to_webhook, upload_to_s3, etc.)
- **Rationale**: Keeps system simple, flexible, and extensible

### ✅ Configurable Autonomous Execution
- `max_iterations` parameter controls multi-turn loops
- Agent can make multiple LLM calls until task complete
- **Rationale**: Enables complex tasks while preventing infinite loops

### ✅ User-Friendly Scheduling
- UI presets: "Every hour", "Every day at 9am", "Every Monday"
- Advanced: Custom cron expressions
- **Rationale**: Easy for beginners, powerful for experts

---

## Core Components

### New Models

1. **TaskRun** - Tracks individual task executions
   - Status: queued → running → completed/failed
   - Tracks: LLM calls, function calls, iterations, cost
   - Links to LlmResponse and FunctionExecution records

2. **TaskSchedule** - Defines when tasks run
   - Cron expressions or interval-based (every N hours/days)
   - Timezone support
   - Enable/disable scheduling

### New Services

1. **TaskAgentRuntimeService** - Executes task agents autonomously
   - Multi-turn loop with max_iterations limit
   - Tracks all LLM calls and function executions
   - Handles completion criteria (auto-detect or explicit)

2. **TaskScheduleCalculator** - Calculates next run times
   - Parses cron expressions (using fugit gem)
   - Handles timezones

### New Background Jobs

1. **ExecuteTaskAgentJob** - Runs a single task
   - Creates TaskRun record
   - Calls TaskAgentRuntimeService
   - Handles errors and retries

2. **ScheduledTaskRunnerJob** - Checks schedules every minute
   - Finds due schedules
   - Enqueues ExecuteTaskAgentJob for each
   - Updates next_run_at

---

## Example Use Case: Daily Real Estate Scraper

```ruby
# 1. Create task agent
task_agent = DeployedAgent.create!(
  agent_type: "task",
  name: "Daily Real Estate Scraper",
  prompt_version: scraper_version,
  task_config: {
    initial_prompt: "Fetch all new listings from {{source_url}} in the last {{time_period}}",
    variables: { source_url: "https://example.com", time_period: "24 hours" },
    execution: { max_iterations: 5, timeout_seconds: 3600 }
  }
)

# 2. Create schedule
TaskSchedule.create!(
  deployed_agent: task_agent,
  schedule_type: "cron",
  cron_expression: "0 9 * * *", # Daily at 9am
  timezone: "America/New_York"
)

# 3. Agent executes autonomously:
# - Calls fetch_webpage(url)
# - Calls parse_html(html, schema)
# - Calls format_csv(data)
# - Calls send_email(to, subject, attachment)
# - Task complete!
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)
- Database migrations
- TaskRun and TaskSchedule models
- Basic TaskAgentRuntimeService (single iteration)
- Manual trigger API
- Basic UI

### Phase 2: Autonomous Execution (Week 3)
- Multi-turn loop with max_iterations
- Completion criteria
- Iteration tracking
- Enhanced UI with timeline

### Phase 3: Scheduling (Week 4)
- TaskScheduleCalculator
- ScheduledTaskRunnerJob
- Cron + interval support
- Schedule management UI

### Phase 4: Polish (Week 5)
- Dashboard with stats
- Advanced filtering
- Clone feature
- Notifications
- Cost tracking

---

## Technical Stack

- **Scheduling**: whenever gem (simple) or Sidekiq-cron (production)
- **Background Jobs**: ActiveJob + Sidekiq
- **Cron Parsing**: fugit gem
- **Function Execution**: Existing AWS Lambda integration
- **Tracking**: Existing LlmResponse and FunctionExecution models

---

## Success Metrics

- Task run success rate: >95%
- User adoption: 30% of users create task agents
- Retention: 80% of task agents still active after 30 days
- Average execution time: <60 seconds
- Cost per task run: <$0.10

---

## Next Steps

1. ✅ Review and approve PRD
2. Create detailed technical specs for Phase 1
3. Set up development environment
4. Begin database migrations
5. Implement TaskRun and TaskSchedule models
6. Build TaskAgentRuntimeService (basic version)
7. Create UI for task agent creation
8. Test with real use cases

---

## Questions & Answers

**Q: Why not separate TaskAgent model?**  
A: Reusing DeployedAgent maximizes code reuse and maintains consistency. The `agent_type` field cleanly separates concerns.

**Q: How does output delivery work?**  
A: Via function calls! Users create functions like `send_email()`, `upload_to_s3()`, etc. The agent calls them as needed.

**Q: What prevents infinite loops?**  
A: `max_iterations` parameter (default: 5) and timeout (default: 3600s). Task fails if limits exceeded.

**Q: Can I test before scheduling?**  
A: Yes! Use "Run Now" button for manual execution with custom variables.

**Q: How are costs tracked?**  
A: Each TaskRun tracks total_cost_usd by summing costs from all LlmResponse records.

---

## Full Documentation

See `planning_artifacts/task_agent_system_prd.md` for complete PRD with:
- Detailed database schema
- Complete API endpoints
- UI mockups
- Service architecture
- Error handling
- Security considerations
- Example use cases

