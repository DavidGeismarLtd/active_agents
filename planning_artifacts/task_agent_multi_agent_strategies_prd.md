# Task Agent Multi-Agent Strategies - Product Requirements Document

**Version:** 1.0
**Date:** 2026-03-25
**Status:** Draft
**Related:** Task Agent System PRD, Task Agent Planning System PRD

---

## Executive Summary

The **Planning Pattern** has been successfully implemented for task agents, providing structured execution with explicit plans, progress tracking, and completion signals. This PRD proposes **complementary strategies** to enable more sophisticated multi-agent workflows:

1. **Subagent Orchestration** – delegate subtasks to specialized agents
2. **Critic/Verifier Agents** – dedicated review and quality gates
3. **Parallel Subtasks** – concurrent execution of independent work
4. **Reusable Orchestration Templates** – standardized workflow patterns

These strategies build on existing infrastructure (`TaskAgentRuntimeService`, `TaskRun`, `PlanningService`) and are opt-in via `task_config.orchestration`.

---

## Problem Statement

### Current Limitations

Even with planning mode, task agents face these challenges:

**1. Monolithic Execution**
- Single agent handles all aspects of complex tasks
- Cannot leverage specialized agents for different skills (research, coding, summarization, verification)
- Difficult to reuse highly-tuned agents as building blocks

**2. Sequential Processing**
- All work happens in a single loop
- No first-class support for parallel subtasks
- Inefficient for tasks with independent sub-goals (e.g., research multiple sources)

**3. Weak Quality Control**
- Quality verification embedded in the same agent doing the work
- No dedicated critic/verifier pattern
- Difficult to enforce consistent quality standards across tasks

**4. Limited Composability**
- Cannot easily compose workflows from existing agents
- Each new complex task requires building from scratch
- No reusable orchestration patterns

### Real-World Examples

**Example 1: Weekly Tech Report**
- Current: Single agent must research AI news, cloud news, security news, then write report
- Desired: Orchestrator delegates to 3 specialized research agents in parallel, then to writer agent, then to verifier

**Example 2: Multi-Repo Code Refactoring**
- Current: Single agent processes repos sequentially
- Desired: Orchestrator fans out to specialized refactoring agents per repo, aggregates results

**Example 3: Content Creation Pipeline**
- Current: Single agent drafts, reviews, and publishes
- Desired: Writer agent → Fact-checker agent → SEO optimizer agent → Publisher

---

## Goals & Non-Goals

### Goals

1. **Enable Subagent Delegation**
   - Allow task agents to call other `DeployedAgent`s as subagents
   - Track parent/child relationships between `TaskRun`s
   - Maintain full observability of delegated work

2. **Support Verification Pattern**
   - Attach dedicated verifier agents to workflows
   - Gate task completion on verifier approval
   - Standardize verification interfaces

3. **Enable Parallel Execution**
   - Run independent subtasks concurrently
   - Aggregate results from parallel subagents
   - Reduce total wall-clock time for complex tasks

4. **Declarative Configuration**
   - Configure orchestration in `task_config.orchestration`
   - No hidden magic or implicit behavior
   - Forward-only design (no legacy compatibility shims)

5. **Maintain Observability**
   - Display subagent runs in TaskRun UI
   - Stream verification results in real-time
   - Preserve existing timeline and Turbo Streams patterns

### Non-Goals

- Not building a general-purpose DAG workflow engine (like Airflow)
- Not introducing a new persistent "Workflow" model in Phase 1
- Not adding defensive error handling (failures surface in TaskRun as today)
- Not supporting arbitrary nesting depth (limit to 2-3 levels initially)

---

## User Stories

### As a Developer

**Story 1: Compose Workflows from Existing Agents**
```
Given I have specialized agents for research, writing, and verification
When I create an orchestrator agent
Then I can configure it to delegate to these agents in sequence
And track the entire workflow in a single TaskRun tree
```

**Story 2: Parallel Research**
```
Given I need to gather data from 5 different sources
When I configure parallel subtasks
Then my orchestrator can fan out to 5 research agents simultaneously
And aggregate their results in a fraction of the time
```

**Story 3: Quality Gates**
```
Given I have a verifier agent that checks code quality
When I configure it as required for completion
Then my task cannot complete without verifier approval
And I see verification results in the timeline
```

### As a Task Agent (Orchestrator)

**Story 4: Delegate Specialized Work**
```
Given I'm an orchestrator agent with a complex task
When I encounter a subtask requiring specialized skills
Then I can call run_subagent() with the appropriate specialist
And receive a structured summary of their work
```

**Story 5: Request Verification**
```
Given I've completed my work
When I need quality approval before finishing
Then I can call request_verification() with my output
And adapt based on the verifier's feedback
```

---

## Architecture Overview

### Configuration Design

Add optional `orchestration` section to `DeployedAgent.task_config`:

```ruby
{
  "initial_prompt": "Generate and verify weekly tech report",
  "planning": {
    "enabled": true
  },
  "orchestration": {
    "enabled": true,
    "max_depth": 2,  # Prevent infinite nesting
    "subagents": [
      {
        "key": "ai_researcher",
        "agent_slug": "tech-news-researcher",
        "description": "Researches AI and ML news"
      },
      {
        "key": "cloud_researcher",
        "agent_slug": "tech-news-researcher",
        "description": "Researches cloud computing news"
      },
      {
        "key": "writer",
        "agent_slug": "longform-writer",
        "description": "Writes comprehensive reports"
      }
    ],
    "verifier": {
      "agent_slug": "report-verifier",
      "required_for_completion": true,
      "description": "Verifies report quality and accuracy"
    },
    "parallel_subtasks": {
      "enabled": true,
      "max_concurrent": 5,
      "allowed_subagent_keys": ["ai_researcher", "cloud_researcher"]
    }
  },
  "execution": {
    "max_iterations": 20,  # Increased for orchestration
    "timeout_seconds": 3600
  }
}
```

### Configuration Fields

**`orchestration.enabled`** (Boolean, default: `false`)
- Enables orchestration mode for this task agent

**`orchestration.max_depth`** (Integer, default: `2`)
- Maximum nesting depth for subagent calls
- Prevents infinite recursion

**`orchestration.subagents`** (Array of objects)
- `key` (String, required) – Internal identifier used in function calls
- `agent_slug` (String, required) – Slug of the `DeployedAgent` to call
- `description` (String, optional) – Helps LLM understand when to use this subagent

**`orchestration.verifier`** (Object, optional)
- `agent_slug` (String, required) – Slug of the verifier agent
- `required_for_completion` (Boolean, default: `false`) – Gates task completion
- `description` (String, optional) – Describes verifier's role

**`orchestration.parallel_subtasks`** (Object, optional)
- `enabled` (Boolean, default: `false`)
- `max_concurrent` (Integer, default: `3`) – Max parallel subagent runs
- `allowed_subagent_keys` (Array of strings) – Which subagents can run in parallel

---

## Data Model Extensions

### TaskRun Model

Add fields to support parent/child relationships:

```ruby
# Migration
add_column :task_runs, :parent_task_run_id, :bigint, null: true
add_column :task_runs, :orchestration_depth, :integer, default: 0
add_column :task_runs, :orchestration_role, :string, null: true
# Values: "orchestrator", "subagent", "verifier"

add_index :task_runs, :parent_task_run_id
add_foreign_key :task_runs, :task_runs, column: :parent_task_run_id
```

**New associations:**

```ruby
class TaskRun < ApplicationRecord
  belongs_to :parent_task_run, class_name: "TaskRun", optional: true
  has_many :child_task_runs, class_name: "TaskRun", foreign_key: :parent_task_run_id

  # Scopes
  scope :orchestrators, -> { where(orchestration_role: "orchestrator") }
  scope :subagents, -> { where(orchestration_role: "subagent") }
  scope :verifiers, -> { where(orchestration_role: "verifier") }
  scope :root_runs, -> { where(parent_task_run_id: nil) }
end
```

### Extend `trigger_type` Enum

```ruby
# Existing: "manual", "schedule"
# Add: "subagent", "verification"

enum trigger_type: {
  manual: "manual",
  schedule: "schedule",
  subagent: "subagent",
  verification: "verification"
}
```

---

## LLM Function Interfaces

### 1. `run_subagent` (Synchronous Delegation)

**Description:** Execute a specialized subagent to handle a focused subtask and wait for its result.

**Function Definition:**

```json
{
  "name": "run_subagent",
  "description": "Delegate a subtask to a specialized subagent and wait for completion. Use this when you need specialized skills or want to isolate a complex subtask.",
  "parameters": {
    "type": "object",
    "required": ["subagent_key", "input"],
    "properties": {
      "subagent_key": {
        "type": "string",
        "description": "Key of the subagent to run (from orchestration.subagents config)",
        "enum": ["ai_researcher", "cloud_researcher", "writer"]
      },
      "input": {
        "type": "string",
        "description": "The task/prompt to send to the subagent"
      },
      "context": {
        "type": "string",
        "description": "Optional additional context for the subagent"
      }
    }
  }
}
```

**Return Value:**

```json
{
  "success": true,
  "task_run_id": 456,
  "status": "completed",
  "summary": "Found 15 AI news articles from the past week. Key trends: ...",
  "execution_time_seconds": 45.2,
  "cost_usd": 0.023,
  "metadata": {
    "iterations": 3,
    "function_calls": 5
  }
}
```

**Implementation (in `OrchestrationService`):**

```ruby
def self.run_subagent(parent_task_run, args)
  subagent_key = args[:subagent_key]
  input = args[:input]

  # Validate subagent_key exists in config
  subagent_config = find_subagent_config(parent_task_run, subagent_key)
  return { success: false, error: "Unknown subagent: #{subagent_key}" } unless subagent_config

  # Find the deployed agent
  subagent = DeployedAgent.find_by(slug: subagent_config[:agent_slug])
  return { success: false, error: "Subagent not found" } unless subagent

  # Check depth limit
  depth = parent_task_run.orchestration_depth + 1
  max_depth = parent_task_run.deployed_agent.task_configuration.dig(:orchestration, :max_depth) || 2
  return { success: false, error: "Max orchestration depth exceeded" } if depth > max_depth

  # Create child TaskRun
  child_run = TaskRun.create!(
    deployed_agent: subagent,
    trigger_type: "subagent",
    parent_task_run: parent_task_run,
    orchestration_depth: depth,
    orchestration_role: "subagent",
    metadata: {
      orchestration: {
        parent_task_run_id: parent_task_run.id,
        subagent_key: subagent_key,
        input: input
      }
    }
  )

  # Execute synchronously
  TaskAgentRuntimeService.call(
    task_agent: subagent,
    task_run: child_run,
    variables: { input: input }
  )

  # Reload to get final status
  child_run.reload

  # Return summary
  {
    success: child_run.completed?,
    task_run_id: child_run.id,
    status: child_run.status,
    summary: child_run.metadata.dig("completion_summary") || "Subagent completed",
    execution_time_seconds: child_run.duration,
    cost_usd: child_run.total_cost_usd,
    metadata: {
      iterations: child_run.iteration_count,
      function_calls: child_run.function_executions.count
    }
  }
end
```

### 2. `run_subagents_batch` (Parallel Delegation)

**Description:** Execute multiple subagents in parallel for independent subtasks.

**Function Definition:**

```json
{
  "name": "run_subagents_batch",
  "description": "Run multiple subagents in parallel for independent subtasks. Results are aggregated and returned together.",
  "parameters": {
    "type": "object",
    "required": ["items"],
    "properties": {
      "items": {
        "type": "array",
        "description": "List of subagent tasks to run in parallel",
        "items": {
          "type": "object",
          "required": ["subagent_key", "input"],
          "properties": {
            "subagent_key": { "type": "string" },
            "input": { "type": "string" },
            "context": { "type": "string" }
          }
        }
      }
    }
  }
}
```

**Return Value:**

```json
{
  "success": true,
  "results": [
    {
      "subagent_key": "ai_researcher",
      "task_run_id": 457,
      "status": "completed",
      "summary": "...",
      "execution_time_seconds": 42.1
    },
    {
      "subagent_key": "cloud_researcher",
      "task_run_id": 458,
      "status": "completed",
      "summary": "...",
      "execution_time_seconds": 38.7
    }
  ],
  "total_execution_time_seconds": 43.5,
  "total_cost_usd": 0.045
}
```

**Implementation:**

```ruby
def self.run_subagents_batch(parent_task_run, args)
  items = args[:items]

  # Validate parallel execution is enabled
  parallel_config = parent_task_run.deployed_agent.task_configuration.dig(:orchestration, :parallel_subtasks)
  return { success: false, error: "Parallel subtasks not enabled" } unless parallel_config[:enabled]

  # Validate max_concurrent
  max_concurrent = parallel_config[:max_concurrent] || 3
  return { success: false, error: "Too many parallel tasks" } if items.size > max_concurrent

  # Execute in parallel using threads (or background jobs for true async)
  results = Parallel.map(items, in_threads: max_concurrent) do |item|
    run_subagent(parent_task_run, item)
  end

  {
    success: results.all? { |r| r[:success] },
    results: results,
    total_execution_time_seconds: results.map { |r| r[:execution_time_seconds] }.max,
    total_cost_usd: results.sum { |r| r[:cost_usd] }
  }
end
```

### 3. `request_verification`

**Description:** Request verification/review from a dedicated verifier agent.

**Function Definition:**

```json
{
  "name": "request_verification",
  "description": "Submit work to the verifier agent for quality review and approval.",
  "parameters": {
    "type": "object",
    "required": ["subject", "content"],
    "properties": {
      "subject": {
        "type": "string",
        "description": "What is being verified (e.g., 'Weekly Tech Report Draft')"
      },
      "content": {
        "type": "string",
        "description": "The content to verify"
      },
      "criteria": {
        "type": "string",
        "description": "Optional specific criteria for verification"
      }
    }
  }
}
```

**Return Value:**

```json
{
  "success": true,
  "task_run_id": 459,
  "approved": true,
  "verdict": "APPROVED",
  "feedback": "Report is comprehensive and well-structured. Minor suggestions: ...",
  "issues": [],
  "suggested_changes": [
    "Add source citations for statistics",
    "Expand cloud security section"
  ],
  "confidence_score": 0.92
}
```

**Implementation:**

```ruby
def self.request_verification(parent_task_run, args)
  verifier_config = parent_task_run.deployed_agent.task_configuration.dig(:orchestration, :verifier)
  return { success: false, error: "No verifier configured" } unless verifier_config

  verifier = DeployedAgent.find_by(slug: verifier_config[:agent_slug])
  return { success: false, error: "Verifier agent not found" } unless verifier

  # Create verification TaskRun
  verification_run = TaskRun.create!(
    deployed_agent: verifier,
    trigger_type: "verification",
    parent_task_run: parent_task_run,
    orchestration_depth: parent_task_run.orchestration_depth + 1,
    orchestration_role: "verifier",
    metadata: {
      verification: {
        parent_task_run_id: parent_task_run.id,
        subject: args[:subject],
        content: args[:content],
        criteria: args[:criteria]
      }
    }
  )

  # Execute verifier
  verification_prompt = build_verification_prompt(args)
  TaskAgentRuntimeService.call(
    task_agent: verifier,
    task_run: verification_run,
    variables: { verification_request: verification_prompt }
  )

  verification_run.reload

  # Parse verifier output (expect structured format)
  verdict = parse_verification_verdict(verification_run)

  {
    success: true,
    task_run_id: verification_run.id,
    approved: verdict[:approved],
    verdict: verdict[:verdict],
    feedback: verdict[:feedback],
    issues: verdict[:issues] || [],
    suggested_changes: verdict[:suggested_changes] || [],
    confidence_score: verdict[:confidence_score]
  }
end
```

### 4. `mark_task_complete_with_verification`

**Description:** Mark task complete, enforcing verification if required.

**Function Definition:**

```json
{
  "name": "mark_task_complete_with_verification",
  "description": "Mark the task as complete. If verification is required, ensures verification was performed and approved.",
  "parameters": {
    "type": "object",
    "required": ["summary"],
    "properties": {
      "summary": {
        "type": "string",
        "description": "Summary of completed work"
      },
      "verification_task_run_id": {
        "type": "integer",
        "description": "ID of the verification TaskRun (required if verifier is configured)"
      }
    }
  }
}
```

**Implementation:**

```ruby
def self.mark_task_complete_with_verification(task_run, args)
  verifier_config = task_run.deployed_agent.task_configuration.dig(:orchestration, :verifier)

  # If verifier is required, enforce verification
  if verifier_config && verifier_config[:required_for_completion]
    verification_id = args[:verification_task_run_id]
    return { success: false, error: "Verification required but not provided" } unless verification_id

    verification_run = TaskRun.find_by(id: verification_id, parent_task_run: task_run)
    return { success: false, error: "Invalid verification TaskRun" } unless verification_run

    verdict = verification_run.metadata.dig("verification_result", "verdict")
    return { success: false, error: "Verification not approved" } unless verdict == "APPROVED"
  end

  # Delegate to existing PlanningService
  PlanningService.mark_task_complete(task_run, args)
end
```

---

## Execution Flow

### Typical Orchestrator Workflow

**Example: Weekly Tech Report**

```
Iteration 0 (Planning Phase):
  Orchestrator creates plan:
    1. Research AI news
    2. Research cloud news
    3. Write comprehensive report
    4. Verify report quality
    5. Publish report

Iteration 1-2 (Parallel Research):
  Orchestrator calls run_subagents_batch([
    { subagent_key: "ai_researcher", input: "Find top AI news from past week" },
    { subagent_key: "cloud_researcher", input: "Find top cloud news from past week" }
  ])

  → Creates TaskRun #457 (ai_researcher) - runs in parallel
  → Creates TaskRun #458 (cloud_researcher) - runs in parallel
  → Both complete in ~40 seconds (vs 80 sequential)

  Orchestrator receives summaries and updates plan:
    ✓ Step 1: Completed via subagent ai_researcher (TaskRun #457)
    ✓ Step 2: Completed via subagent cloud_researcher (TaskRun #458)

Iteration 3-4 (Writing):
  Orchestrator calls run_subagent(
    subagent_key: "writer",
    input: "Write report based on: [research summaries]"
  )

  → Creates TaskRun #459 (writer)
  → Writer agent drafts comprehensive report

  Orchestrator updates plan:
    ✓ Step 3: Completed via subagent writer (TaskRun #459)

Iteration 5-6 (Verification):
  Orchestrator calls request_verification(
    subject: "Weekly Tech Report",
    content: "[draft report]"
  )

  → Creates TaskRun #460 (verifier)
  → Verifier reviews and returns: { approved: true, suggestions: [...] }

  Orchestrator integrates suggestions and updates plan:
    ✓ Step 4: Verification approved with minor suggestions

Iteration 7 (Completion):
  Orchestrator calls mark_task_complete_with_verification(
    summary: "Weekly tech report completed and verified",
    verification_task_run_id: 460
  )

  → Task marked complete
  → All child TaskRuns visible in UI tree
```

---

## UI & UX Design

### TaskRun Detail Page (Orchestrator View)

**Tree View of Related Runs:**

```
📋 Weekly Tech Report Generator (TaskRun #456) - Completed
├── 🔍 AI News Research (TaskRun #457) - Completed [Subagent]
│   ├── Duration: 42.1s
│   ├── Cost: $0.021
│   └── Summary: Found 15 AI articles, key trends: LLM advances, AI safety...
│
├── 🔍 Cloud News Research (TaskRun #458) - Completed [Subagent]
│   ├── Duration: 38.7s
│   ├── Cost: $0.019
│   └── Summary: Found 12 cloud articles, key trends: Serverless, Kubernetes...
│
├── ✍️ Report Writing (TaskRun #459) - Completed [Subagent]
│   ├── Duration: 67.3s
│   ├── Cost: $0.034
│   └── Summary: Generated 2,500-word comprehensive report
│
└── ✅ Report Verification (TaskRun #460) - Completed [Verifier]
    ├── Duration: 23.1s
    ├── Cost: $0.012
    ├── Verdict: APPROVED
    └── Feedback: Excellent coverage, minor citation suggestions
```

**Timeline View (with Turbo Streams):**

```
[09:00:00] 📋 Task started
[09:00:02] 🎯 Plan created with 5 steps
[09:00:05] 🚀 Started parallel subagents: ai_researcher, cloud_researcher
[09:00:47] ✅ Subagent ai_researcher completed (TaskRun #457)
[09:00:43] ✅ Subagent cloud_researcher completed (TaskRun #458)
[09:00:50] 🔄 Updated step 1: completed
[09:00:51] 🔄 Updated step 2: completed
[09:00:55] 🚀 Started subagent: writer
[09:02:02] ✅ Subagent writer completed (TaskRun #459)
[09:02:05] 🔄 Updated step 3: completed
[09:02:10] 🔍 Verification requested (TaskRun #460)
[09:02:33] ✅ Verification approved
[09:02:35] 🔄 Updated step 4: completed
[09:02:40] 🎉 Task completed with verification
```

### Configuration UI

**Agent Creation Form - Orchestration Section:**

```
┌─ Orchestration (Optional) ────────────────────────┐
│                                                    │
│ ☑ Enable orchestration mode                       │
│                                                    │
│ Max Depth: [2] ▼                                   │
│                                                    │
│ Subagents:                                         │
│ ┌────────────────────────────────────────────┐    │
│ │ Key: ai_researcher                         │    │
│ │ Agent: [Tech News Researcher ▼]           │    │
│ │ Description: Researches AI and ML news     │    │
│ │                                    [Remove] │    │
│ └────────────────────────────────────────────┘    │
│ [+ Add Subagent]                                   │
│                                                    │
│ Verifier:                                          │
│ ┌────────────────────────────────────────────┐    │
│ │ Agent: [Report Verifier ▼]                 │    │
│ │ ☑ Required for completion                  │    │
│ │ Description: Verifies quality and accuracy │    │
│ └────────────────────────────────────────────┘    │
│                                                    │
│ Parallel Execution:                                │
│ ☑ Enable parallel subtasks                        │
│ Max Concurrent: [3] ▼                              │
│ Allowed Subagents: ☑ ai_researcher                │
│                    ☑ cloud_researcher              │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Synchronous Subagent Delegation (Weeks 1-2)

**Database:**
- [ ] Migration: Add `parent_task_run_id`, `orchestration_depth`, `orchestration_role` to `task_runs`
- [ ] Add `trigger_type` values: `"subagent"`, `"verification"`
- [ ] Add associations to `TaskRun` model

**Services:**
- [ ] Create `OrchestrationService` with `run_subagent` method
- [ ] Extend `TaskAgentRuntimeService` to inject orchestration functions
- [ ] Add orchestration config validation to `DeployedAgent`

**Functions:**
- [ ] Implement `run_subagent` function tool
- [ ] Add depth limit enforcement
- [ ] Track parent/child relationships

**UI:**
- [ ] Extend TaskRun detail page with tree view
- [ ] Add subagent badges and status indicators
- [ ] Update timeline to show subagent events

**Tests:**
- [ ] Unit tests for `OrchestrationService.run_subagent`
- [ ] Integration test: orchestrator → subagent → completion
- [ ] Test depth limit enforcement
- [ ] Test error handling (subagent not found, depth exceeded)

**Deliverable:** Orchestrators can delegate to single subagents synchronously

---

### Phase 2: Verification Pattern (Weeks 3-4)

**Services:**
- [ ] Implement `OrchestrationService.request_verification`
- [ ] Implement `OrchestrationService.mark_task_complete_with_verification`
- [ ] Add verification result parsing logic

**Functions:**
- [ ] Implement `request_verification` function tool
- [ ] Implement `mark_task_complete_with_verification` function tool
- [ ] Standardize verifier output format

**UI:**
- [ ] Add verification badge and status in tree view
- [ ] Display verification verdict and feedback
- [ ] Show verification timeline events

**Tests:**
- [ ] Unit tests for verification flow
- [ ] Test required verification enforcement
- [ ] Test verification rejection handling
- [ ] Integration test: orchestrator → work → verification → completion

**Deliverable:** Orchestrators can request verification and gate completion

---

### Phase 3: Parallel Subtasks (Weeks 5-6)

**Services:**
- [ ] Implement `OrchestrationService.run_subagents_batch`
- [ ] Add parallel execution using `Parallel` gem or background jobs
- [ ] Implement result aggregation logic

**Functions:**
- [ ] Implement `run_subagents_batch` function tool
- [ ] Add max_concurrent enforcement
- [ ] Handle partial failures in batch

**UI:**
- [ ] Show parallel execution in timeline (grouped events)
- [ ] Display wall-clock time savings
- [ ] Add parallel execution metrics

**Tests:**
- [ ] Unit tests for batch execution
- [ ] Test max_concurrent limits
- [ ] Test partial failure scenarios
- [ ] Performance test: verify actual parallelization

**Deliverable:** Orchestrators can run multiple subagents in parallel

---

### Phase 4: Templates & Polish (Weeks 7-8)

**Configuration:**
- [ ] Define orchestration template schema
- [ ] Create example templates (research-write-verify, multi-repo-refactor)
- [ ] Add template selection to UI

**UI:**
- [ ] Template library page
- [ ] Visual orchestration diagram
- [ ] Metrics dashboard (subagent usage, parallelization gains)

**Documentation:**
- [ ] "Building Multi-Agent Workflows" guide
- [ ] Example orchestration patterns
- [ ] Best practices for subagent design

**Tests:**
- [ ] End-to-end tests for each template
- [ ] Load testing for complex orchestrations

**Deliverable:** Production-ready orchestration system with templates

---

## Technical Considerations

### Depth Limits & Recursion

**Problem:** Prevent infinite nesting (orchestrator → subagent → sub-subagent → ...)

**Solution:**
- Enforce `max_depth` (default: 2) in configuration
- Track `orchestration_depth` in each TaskRun
- Reject `run_subagent` calls that would exceed limit

### Timeout Handling

**Problem:** Subagent runs can be long; orchestrator might timeout

**Solution:**
- Each subagent has its own `timeout_seconds` from its config
- Orchestrator's timeout is independent
- If orchestrator times out, child runs continue but become orphaned
- UI shows orphaned runs with warning badge

### Cost Tracking

**Problem:** Need to attribute costs correctly across orchestrator + subagents

**Solution:**
- Each TaskRun tracks its own `total_cost_usd`
- Orchestrator's cost = its LLM calls + sum of child TaskRun costs
- Add `TaskRun#total_cost_with_children` method

### Parallel Execution Implementation

**Phase 3 Options:**

**Option A: Threads (Simple)**
```ruby
results = Parallel.map(items, in_threads: max_concurrent) do |item|
  run_subagent(parent_task_run, item)
end
```
- ✅ Simple, synchronous from orchestrator's perspective
- ❌ Blocks orchestrator's execution thread
- ✅ Good for Phase 3 MVP

**Option B: Background Jobs (Production)**
```ruby
job_ids = items.map do |item|
  ExecuteSubagentJob.perform_later(parent_task_run.id, item).job_id
end
# Poll for completion or use callbacks
```
- ✅ Non-blocking, scalable
- ✅ Better for production workloads
- ❌ More complex (need polling or callbacks)
- 🎯 Future enhancement

### Error Handling

**Principle:** No defensive error handling; failures surface in TaskRun

**Scenarios:**

1. **Subagent not found**
   - Return `{ success: false, error: "Subagent not found" }`
   - Orchestrator can handle or fail

2. **Subagent fails**
   - Child TaskRun status = `failed`
   - Return `{ success: false, status: "failed", error: "..." }`
   - Orchestrator decides whether to retry or abort

3. **Verification rejects**
   - Return `{ approved: false, issues: [...] }`
   - Orchestrator can iterate or abort

4. **Depth limit exceeded**
   - Return `{ success: false, error: "Max depth exceeded" }`
   - Prevents runaway recursion

---

## Success Metrics

### Adoption Metrics

1. **Orchestration Adoption Rate**
   - Target: 20% of task agents use orchestration within 3 months
   - Measure: `DeployedAgent.where("task_config->>'orchestration'->>'enabled' = 'true'").count`

2. **Subagent Reusability**
   - Target: Average subagent is used by 3+ orchestrators
   - Measure: Avg references per subagent slug in configs

### Performance Metrics

3. **Parallelization Gains**
   - Target: 40% reduction in wall-clock time for parallel workflows
   - Measure: Compare sequential vs parallel execution times

4. **Verification Effectiveness**
   - Target: 80% of verified tasks pass on first attempt
   - Measure: Ratio of approved verifications to total verifications

### Quality Metrics

5. **Task Success Rate**
   - Target: Orchestrated tasks have ≥95% success rate
   - Measure: `TaskRun.orchestrators.completed.count / TaskRun.orchestrators.count`

6. **Cost Efficiency**
   - Target: Orchestrated tasks cost ≤20% more than monolithic (due to coordination overhead)
   - Measure: Compare avg cost per task type

---

## Risks & Mitigations

### Risk 1: Complexity Overwhelms Users

**Risk:** Orchestration config is too complex for average users

**Mitigation:**
- Make orchestration **opt-in** and clearly labeled "Advanced"
- Provide templates for common patterns
- Add configuration wizard in UI
- Comprehensive documentation with examples

### Risk 2: Deep Nesting Performance

**Risk:** Deep orchestration trees cause performance issues

**Mitigation:**
- Enforce `max_depth` limit (default: 2)
- Monitor and alert on deep trees
- Add metrics for orchestration depth distribution

### Risk 3: Orphaned Child Runs

**Risk:** Orchestrator times out, leaving child runs running

**Mitigation:**
- UI clearly shows orphaned runs
- Add cleanup job to mark orphaned runs
- Consider adding "cancel children on parent timeout" option

### Risk 4: Cost Explosion

**Risk:** Parallel execution causes unexpected cost spikes

**Mitigation:**
- Enforce `max_concurrent` limits
- Show cost estimates before execution
- Add budget alerts per orchestrator
- Track and display cost trends

---

## Open Questions

### Q1: Should subagents inherit context from orchestrator?

**Options:**
- A) Subagents are fully isolated (only receive explicit input)
- B) Subagents can access orchestrator's plan and metadata

**Recommendation:** Start with A (isolated) for simplicity. Add B in Phase 4 if needed.

---

### Q2: How to handle subagent versioning?

**Scenario:** Orchestrator references subagent by slug, but subagent's PromptVersion changes

**Options:**
- A) Always use latest version (current behavior)
- B) Pin to specific PromptVersion in config
- C) Warn if subagent changed since orchestrator was created

**Recommendation:** Start with A. Add B in Phase 4 for production stability.

---

### Q3: Should verifiers have access to full TaskRun history?

**Options:**
- A) Verifier only sees content submitted for verification
- B) Verifier can access full orchestrator TaskRun (plan, timeline, etc.)

**Recommendation:** Start with A. Add B as optional `include_context: true` parameter.

---

## Appendix: Example Workflows

### Example 1: Multi-Source Research Report

**Orchestrator:** `research-report-generator`

**Config:**
```json
{
  "orchestration": {
    "enabled": true,
    "subagents": [
      { "key": "web_researcher", "agent_slug": "web-research-agent" },
      { "key": "academic_researcher", "agent_slug": "academic-research-agent" },
      { "key": "report_writer", "agent_slug": "longform-writer" }
    ],
    "verifier": {
      "agent_slug": "fact-checker",
      "required_for_completion": true
    },
    "parallel_subtasks": {
      "enabled": true,
      "allowed_subagent_keys": ["web_researcher", "academic_researcher"]
    }
  }
}
```

**Workflow:**
1. Orchestrator creates plan
2. Calls `run_subagents_batch` for web + academic research (parallel)
3. Calls `run_subagent` for report writing
4. Calls `request_verification` for fact-checking
5. Iterates on feedback if needed
6. Calls `mark_task_complete_with_verification`

---

### Example 2: Multi-Repo Code Refactoring

**Orchestrator:** `multi-repo-refactorer`

**Config:**
```json
{
  "orchestration": {
    "enabled": true,
    "subagents": [
      { "key": "typescript_refactorer", "agent_slug": "ts-refactor-agent" },
      { "key": "python_refactorer", "agent_slug": "py-refactor-agent" }
    ],
    "verifier": {
      "agent_slug": "code-reviewer",
      "required_for_completion": true
    },
    "parallel_subtasks": {
      "enabled": true,
      "max_concurrent": 5,
      "allowed_subagent_keys": ["typescript_refactorer", "python_refactorer"]
    }
  }
}
```

**Workflow:**
1. Orchestrator analyzes repos and creates plan
2. Calls `run_subagents_batch` with one item per repo (parallel)
3. Aggregates refactoring results
4. Calls `request_verification` for code review
5. Addresses review comments if needed
6. Calls `mark_task_complete_with_verification`

---

### Example 3: Content Creation Pipeline

**Orchestrator:** `content-pipeline`

**Config:**
```json
{
  "orchestration": {
    "enabled": true,
    "subagents": [
      { "key": "researcher", "agent_slug": "content-researcher" },
      { "key": "writer", "agent_slug": "content-writer" },
      { "key": "seo_optimizer", "agent_slug": "seo-agent" }
    ],
    "verifier": {
      "agent_slug": "editorial-reviewer",
      "required_for_completion": true
    }
  }
}
```

**Workflow:**
1. Orchestrator creates plan
2. Calls `run_subagent(researcher)` for topic research
3. Calls `run_subagent(writer)` with research summary
4. Calls `run_subagent(seo_optimizer)` with draft
5. Calls `request_verification` for editorial review
6. Publishes if approved, iterates if not
7. Calls `mark_task_complete_with_verification`

---

## Conclusion

This PRD proposes a **complementary set of strategies** that build on the existing Planning Pattern to enable sophisticated multi-agent workflows. By introducing **subagent orchestration**, **verification patterns**, and **parallel execution**, we unlock new use cases while maintaining the simplicity and observability that make task agents powerful.

The phased implementation approach allows us to:
- Deliver value incrementally (synchronous → verification → parallel)
- Validate assumptions with real usage before building complex features
- Maintain backward compatibility (orchestration is opt-in)
- Preserve the clean, forward-only configuration philosophy

**Next Steps:**
1. Review and approve this PRD
2. Create detailed technical specs for Phase 1
3. Begin database migrations and `OrchestrationService` implementation
4. Build Phase 1 MVP: synchronous subagent delegation
