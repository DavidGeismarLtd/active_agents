# Task Agent System - Implementation Checklist

**Date:** 2026-03-20  
**Status:** Ready to Start

---

## Phase 1: Core Infrastructure (Week 1-2)

### Database Migrations

- [ ] **Migration 1**: Add `agent_type` and `task_config` to `deployed_agents`
  - [ ] Add `agent_type` column (string, default: "conversational")
  - [ ] Add `task_config` column (jsonb, default: {})
  - [ ] Add index on `agent_type`
  - [ ] Test migration up/down

- [ ] **Migration 2**: Create `task_runs` table
  - [ ] Add all columns (status, trigger_type, timestamps, stats)
  - [ ] Add foreign key to `deployed_agents`
  - [ ] Add indexes (status, trigger_type, started_at, composite)
  - [ ] Test migration up/down

- [ ] **Migration 3**: Create `task_schedules` table
  - [ ] Add all columns (schedule_type, cron, interval, timezone)
  - [ ] Add foreign key to `deployed_agents` (unique)
  - [ ] Add indexes (enabled, next_run_at, composite)
  - [ ] Test migration up/down

- [ ] **Migration 4**: Add `task_run_id` to existing tables
  - [ ] Add to `llm_responses` (optional foreign key)
  - [ ] Add to `function_executions` (optional foreign key)
  - [ ] Test migration up/down

### Models

- [ ] **DeployedAgent** (extend existing)
  - [ ] Add `enum agent_type: { conversational: "conversational", task: "task" }`
  - [ ] Add `has_many :task_runs`
  - [ ] Add `has_one :task_schedule`
  - [ ] Add validation for `task_config` when `agent_type == "task"`
  - [ ] Add helper methods: `task?`, `conversational?`
  - [ ] Write model specs

- [ ] **TaskRun** (new model)
  - [ ] Add associations (belongs_to :deployed_agent, has_many :llm_responses, etc.)
  - [ ] Add validations (status, trigger_type)
  - [ ] Add scopes (queued, running, completed, failed, recent)
  - [ ] Add status enum
  - [ ] Add helper methods: `duration`, `success_rate`, etc.
  - [ ] Write model specs

- [ ] **TaskSchedule** (new model)
  - [ ] Add associations (belongs_to :deployed_agent)
  - [ ] Add validations (schedule_type, cron_expression or interval)
  - [ ] Add scopes (enabled, due)
  - [ ] Add schedule_type enum
  - [ ] Add helper methods: `next_run`, `overdue?`, etc.
  - [ ] Write model specs

### Services

- [ ] **TaskAgentRuntimeService** (new service - basic version)
  - [ ] Implement `call` method
  - [ ] Render initial prompt with variables
  - [ ] Single LLM call with function execution
  - [ ] Track LlmResponse and FunctionExecution
  - [ ] Update TaskRun status and stats
  - [ ] Handle errors gracefully
  - [ ] Write service specs

- [ ] **ExecuteTaskAgentJob** (new job)
  - [ ] Implement `perform` method
  - [ ] Load task agent and task run
  - [ ] Call TaskAgentRuntimeService
  - [ ] Handle errors and update TaskRun
  - [ ] Write job specs

### Controllers & Routes

- [ ] **Extend DeployedAgentsController**
  - [ ] Update `new` action to support agent_type selection
  - [ ] Update `create` action to handle task_config
  - [ ] Update `show` action to display task-specific info
  - [ ] Add `run_now` action for manual triggers
  - [ ] Write controller specs

- [ ] **TaskRunsController** (new controller)
  - [ ] Implement `index` action (list runs for agent)
  - [ ] Implement `show` action (run details)
  - [ ] Implement `retry` action
  - [ ] Write controller specs

- [ ] **Routes**
  - [ ] Add `POST /agents/:slug/run` (manual trigger)
  - [ ] Add `GET /agents/:slug/runs` (list runs)
  - [ ] Add `GET /task_runs/:id` (run details)
  - [ ] Add `POST /task_runs/:id/retry` (retry run)

### Views

- [ ] **Agent Type Selection** (new/edit form)
  - [ ] Radio buttons for conversational vs task
  - [ ] Show/hide relevant config sections with Stimulus
  - [ ] Test UI interactions

- [ ] **Task Agent Configuration Form**
  - [ ] Initial prompt textarea with variable highlighting
  - [ ] Variables input (key-value pairs)
  - [ ] Execution settings (max_iterations, timeout)
  - [ ] Completion criteria radio buttons
  - [ ] Test form submission

- [ ] **Task Run List** (index view)
  - [ ] Table with status, trigger, duration, cost
  - [ ] Filters (status, trigger_type, date range)
  - [ ] Pagination
  - [ ] Test UI

- [ ] **Task Run Details** (show view)
  - [ ] Overview section (status, duration, cost)
  - [ ] Stats section (iterations, LLM calls, function calls)
  - [ ] Variables used
  - [ ] Output summary
  - [ ] Error message (if failed)
  - [ ] Test UI

### Factories & Fixtures

- [ ] **TaskRun factory**
  - [ ] Default trait
  - [ ] `:completed` trait
  - [ ] `:failed` trait
  - [ ] `:with_llm_responses` trait
  - [ ] `:with_function_executions` trait

- [ ] **TaskSchedule factory**
  - [ ] Default trait (cron)
  - [ ] `:interval` trait
  - [ ] `:disabled` trait

- [ ] **Update DeployedAgent factory**
  - [ ] `:task_agent` trait
  - [ ] `:with_task_runs` trait
  - [ ] `:with_schedule` trait

---

## Phase 2: Autonomous Multi-Turn Execution (Week 3)

### Services

- [ ] **Enhance TaskAgentRuntimeService**
  - [ ] Implement autonomous loop (up to max_iterations)
  - [ ] Track iteration count
  - [ ] Implement completion criteria (auto-detect)
  - [ ] Implement completion criteria (explicit)
  - [ ] Handle timeout
  - [ ] Update specs

### Views

- [ ] **Enhanced Task Run Details**
  - [ ] Execution timeline (iteration-by-iteration)
  - [ ] Show each LLM call with prompt/response
  - [ ] Show each function call with args/result
  - [ ] Visual iteration markers
  - [ ] Test UI

### Features

- [ ] **Retry Mechanism**
  - [ ] Implement retry logic in ExecuteTaskAgentJob
  - [ ] Track retry count in TaskRun
  - [ ] Add retry button in UI
  - [ ] Write specs

---

## Phase 3: Scheduling System (Week 4)

### Dependencies

- [ ] **Add fugit gem** to Gemfile
  - [ ] `gem 'fugit'` for cron parsing
  - [ ] Run `bundle install`

### Services

- [ ] **TaskScheduleCalculator** (new service)
  - [ ] Implement `next_run_time` for cron
  - [ ] Implement `next_run_time` for intervals
  - [ ] Handle timezones
  - [ ] Write service specs

- [ ] **ScheduledTaskRunnerJob** (new job)
  - [ ] Find all due schedules
  - [ ] Create TaskRun for each
  - [ ] Enqueue ExecuteTaskAgentJob
  - [ ] Update schedule (last_run_at, next_run_at)
  - [ ] Write job specs

### System Configuration

- [ ] **Set up cron job**
  - [ ] Add whenever gem (or use Heroku Scheduler)
  - [ ] Configure to run ScheduledTaskRunnerJob every minute
  - [ ] Test in development
  - [ ] Document deployment steps

### Controllers & Routes

- [ ] **TaskSchedulesController** (new controller)
  - [ ] Implement `create` action
  - [ ] Implement `update` action
  - [ ] Implement `destroy` action
  - [ ] Implement `enable` action
  - [ ] Implement `disable` action
  - [ ] Write controller specs

- [ ] **Routes**
  - [ ] Add `POST /agents/:slug/schedule`
  - [ ] Add `PATCH /agents/:slug/schedule`
  - [ ] Add `DELETE /agents/:slug/schedule`
  - [ ] Add `POST /agents/:slug/schedule/enable`
  - [ ] Add `POST /agents/:slug/schedule/disable`

### Views

- [ ] **Schedule Configuration Form**
  - [ ] Schedule type radio (cron vs interval)
  - [ ] Common presets (hourly, daily, weekly)
  - [ ] Custom cron expression input
  - [ ] Timezone selector
  - [ ] Next run preview
  - [ ] Test UI

- [ ] **Schedule Display** (in agent show page)
  - [ ] Show current schedule
  - [ ] Show next run time
  - [ ] Show last run time
  - [ ] Enable/disable toggle
  - [ ] Edit button
  - [ ] Test UI

---

## Phase 4: Polish & Advanced Features (Week 5)

### Dashboard

- [ ] **Task Agent Dashboard**
  - [ ] Stats cards (total agents, active, success rate)
  - [ ] Agent list with filters
  - [ ] Quick actions (run now, pause, edit)
  - [ ] Test UI

### Features

- [ ] **Clone Task Agent**
  - [ ] Add clone action to controller
  - [ ] Copy all config with new name
  - [ ] Add clone button in UI
  - [ ] Write specs

- [ ] **Bulk Operations**
  - [ ] Pause multiple agents
  - [ ] Resume multiple agents
  - [ ] Delete multiple agents
  - [ ] Write specs

- [ ] **Notifications**
  - [ ] Email on task failure
  - [ ] Webhook on task completion
  - [ ] Configure in task_config
  - [ ] Write specs

- [ ] **Cost Tracking**
  - [ ] Calculate total_cost_usd per TaskRun
  - [ ] Show cost trends over time
  - [ ] Budget alerts
  - [ ] Write specs

---

## Testing Checklist

### Unit Tests
- [ ] All model specs passing
- [ ] All service specs passing
- [ ] All job specs passing
- [ ] All helper specs passing

### Integration Tests
- [ ] Controller specs passing
- [ ] Request specs passing
- [ ] System specs for UI flows

### Manual Testing
- [ ] Create task agent via UI
- [ ] Trigger task manually
- [ ] View task run details
- [ ] Create schedule
- [ ] Wait for scheduled run
- [ ] Test retry on failure
- [ ] Test pause/resume
- [ ] Test clone

---

## Documentation

- [ ] Update README with task agent section
- [ ] API documentation for new endpoints
- [ ] User guide for creating task agents
- [ ] Developer guide for extending system
- [ ] Migration guide from conversational to task

---

## Deployment

- [ ] Run migrations in staging
- [ ] Test in staging environment
- [ ] Set up cron job in production
- [ ] Run migrations in production
- [ ] Monitor first scheduled runs
- [ ] Announce feature to users

---

## Success Criteria

- [ ] ✅ Can create task agent via UI
- [ ] ✅ Can trigger task manually and see results
- [ ] ✅ Can schedule task with cron expression
- [ ] ✅ Scheduled tasks run automatically
- [ ] ✅ Task runs tracked with full details
- [ ] ✅ Failed tasks can be retried
- [ ] ✅ All tests passing
- [ ] ✅ Documentation complete
- [ ] ✅ Successfully deployed to production

