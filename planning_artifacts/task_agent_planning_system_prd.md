# Task Agent Planning System - Product Requirements Document

**Version:** 1.0
**Date:** 2026-03-21
**Status:** Draft
**Related:** Task Agent System PRD

---

## Executive Summary

Add **planning capabilities** to task agents to enable structured, goal-oriented execution with explicit progress tracking and completion signals. This solves the current issues of over-iteration, unclear stopping conditions, and lack of progress visibility.

### Problem Statement

Current task agents have several limitations:
1. **No explicit goal tracking** - Agents don't maintain clear understanding of objectives
2. **No structured planning** - Agents react to each iteration without a plan
3. **Poor stopping conditions** - Either hit max iterations or stop when no function calls made
4. **No progress visibility** - Users can't see what the agent is working on in real-time
5. **Over-iteration issues** - Agents continue iterating unnecessarily (e.g., Task Run #12 found 9 articles but concluded "no news found")

### Solution

Add optional **planning mode** to task agents that:
- Requires agents to create explicit plans before execution
- Provides planning functions (`create_plan`, `update_step`, `mark_task_complete`)
- Stores plans in JSONB (Phase 1) with migration path to dedicated tables (Phase 2)
- Streams plan updates to UI in real-time via Turbo Streams
- Enforces explicit completion via `mark_task_complete()` function

---

## Goals

1. **Enable structured execution**: Agents create and follow explicit plans
2. **Improve stopping conditions**: Agents must explicitly mark tasks complete
3. **Real-time visibility**: Users see plan progress as it happens
4. **Backward compatible**: Existing task agents continue to work without changes
5. **Future-proof**: Design supports migration to dedicated tables later
6. **Developer-friendly**: Planning functions are automatically injected at runtime

---

## User Stories

### As a developer, I want to:
- Enable planning mode for my task agent with a simple checkbox
- See the agent's plan before it starts executing
- Watch plan progress update in real-time as the agent works
- Understand why a task completed or failed based on the plan
- Compare plans across multiple runs to optimize my agent

### As a task agent, I should:
- Create a clear plan with specific steps before starting work
- Update step status and notes as I progress
- Add new steps if I discover additional work needed
- Explicitly mark the task complete when all steps are done
- Never complete without calling `mark_task_complete()`

---

## Architecture Overview

### Configuration

Add `planning` section to `DeployedAgent.task_config`:

```ruby
{
  "initial_prompt": "Monitor technology news and create a daily summary",
  "variables": { "topic": "technology" },
  "planning": {
    "enabled": true,
    "require_plan_before_execution": true,
    "allow_plan_modifications": true,
    "max_steps": 20
  },
  "execution": {
    "max_iterations": 15,  # Increased for planning agents
    "timeout_seconds": 1800
  },
  "completion_criteria": {
    "type": "explicit"  # Automatically set when planning enabled
  }
}
```

### Plan Data Structure (JSONB in TaskRun.metadata)

```json
{
  "plan": {
    "goal": "Monitor technology news and create a daily summary",
    "created_at": "2026-03-21T10:00:00Z",
    "updated_at": "2026-03-21T10:05:00Z",
    "status": "in_progress",
    "steps": [
      {
        "id": "step_1",
        "order": 1,
        "description": "Search for AI news articles",
        "status": "completed",
        "notes": "Found 21,667 articles, selected top 5",
        "started_at": "2026-03-21T10:00:30Z",
        "completed_at": "2026-03-21T10:01:00Z"
      },
      {
        "id": "step_2",
        "order": 2,
        "description": "Search for cloud computing news",
        "status": "in_progress",
        "notes": "Fetching articles...",
        "started_at": "2026-03-21T10:01:05Z",
        "completed_at": null
      },
      {
        "id": "step_3",
        "order": 3,
        "description": "Synthesize findings into summary",
        "status": "pending",
        "notes": null,
        "started_at": null,
        "completed_at": null
      }
    ],
    "completion_summary": null
  }
}
```

### Planning Functions (Auto-injected at Runtime)

When `planning.enabled = true`, these functions are automatically added to the agent's available functions:

```ruby
# 1. Create initial plan (required first step)
create_plan(goal: string, steps: array<string>)
# Returns: { plan_id, goal, steps: [{id, description, status, order}] }

# 2. Get current plan
get_plan()
# Returns: { goal, status, steps: [...], progress_percentage }

# 3. Update step status
update_step(step_id: string, status: string, notes: string)
# Status: "pending" | "in_progress" | "completed" | "skipped" | "failed"
# Returns: { step_id, status, notes, completed_at }

# 4. Add new step (optional, if allow_plan_modifications = true)
add_step(description: string, after_step_id: string)
# Returns: { step_id, description, status, order }

# 5. Mark task complete (required to finish)
mark_task_complete(summary: string)
# Returns: { success: true, summary, plan_status: "completed" }
```

---

## Implementation Details

### Phase 1: Core Planning (Hybrid Approach)

**Storage Strategy:**
- Store plan in `TaskRun.metadata[:plan]` (JSONB column)
- No new database tables initially
- Design function interface to support future migration to dedicated tables

**Function Injection:**
- Planning functions are **not** stored in `FunctionDefinition` table
- Injected dynamically in `TaskAgentRuntimeService` when planning enabled
- Similar to how built-in tools work (file_search, code_interpreter)

**Runtime Service Changes:**

```ruby
# In TaskAgentRuntimeService#call
def call
  # 1. Check if planning is enabled
  if planning_enabled?
    # 2. Inject planning functions into available functions
    @available_functions = inject_planning_functions(@available_functions)

    # 3. Enhance system prompt with planning instructions
    @system_prompt = enhance_system_prompt_with_planning(@system_prompt)

    # 4. Enforce plan creation on first iteration
    enforce_plan_creation if first_iteration?
  end

  # 5. Run normal execution loop
  run_execution_loop
end

private

def inject_planning_functions(functions)
  return functions unless planning_enabled?

  planning_functions = [
    build_create_plan_function,
    build_get_plan_function,
    build_update_step_function,
    build_add_step_function,
    build_mark_task_complete_function
  ]

  functions + planning_functions
end

def build_create_plan_function
  {
    name: "create_plan",
    description: "Create an execution plan with specific steps. MUST be called before starting work.",
    parameters: {
      type: "object",
      required: ["goal", "steps"],
      properties: {
        goal: { type: "string", description: "Clear statement of what you're trying to achieve" },
        steps: {
          type: "array",
          description: "List of specific steps to accomplish the goal",
          items: { type: "string" }
        }
      }
    },
    handler: ->(args) { PlanningService.create_plan(@task_run, args) }
  }
end

def enhance_system_prompt_with_planning(original_prompt)
  planning_instructions = <<~INSTRUCTIONS

    ## PLANNING REQUIREMENTS

    You MUST follow this workflow:

    1. **Create a Plan First**: Before doing any work, call `create_plan()` with:
       - A clear goal statement
       - 3-7 specific steps to achieve the goal

    2. **Execute Steps**: For each step:
       - Call `update_step(step_id, "in_progress", "Starting work on...")`
       - Perform the necessary function calls
       - Call `update_step(step_id, "completed", "Summary of what was done")`

    3. **Adapt if Needed**: If you discover new work:
       - Call `add_step()` to add it to the plan
       - Update existing steps if priorities change

    4. **Complete Explicitly**: When ALL steps are done:
       - Call `mark_task_complete(summary)` with a comprehensive summary
       - DO NOT stop without calling this function

    5. **Never Over-Iterate**:
       - If you've completed your plan, call `mark_task_complete()`
       - Don't perform redundant searches or unnecessary follow-ups
       - Trust your initial findings unless there's a clear gap

    You can check your current plan anytime with `get_plan()`.
  INSTRUCTIONS

  original_prompt + planning_instructions
end
```

**Stopping Condition Changes:**

```ruby
# Current stopping logic (without planning)
def should_stop?
  @iteration >= @max_iterations || @last_response.tool_calls.empty?
end

# New stopping logic (with planning)
def should_stop?
  if planning_enabled?
    # Only stop if:
    # 1. Task explicitly marked complete, OR
    # 2. Max iterations reached (safety), OR
    # 3. Error occurred
    @task_run.metadata.dig("plan", "status") == "completed" ||
      @iteration >= @max_iterations ||
      @error_occurred
  else
    # Legacy behavior for non-planning agents
    @iteration >= @max_iterations || @last_response.tool_calls.empty?
  end
end
```

---

### Phase 2: Real-Time Streaming

**Turbo Stream Integration:**

When plan is created or updated, broadcast changes to the UI:

```ruby
# In PlanningService
class PlanningService
  def self.create_plan(task_run, args)
    plan_data = {
      goal: args[:goal],
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601,
      status: "in_progress",
      steps: args[:steps].map.with_index do |description, i|
        {
          id: "step_#{i + 1}",
          order: i + 1,
          description: description,
          status: "pending",
          notes: nil,
          started_at: nil,
          completed_at: nil
        }
      end,
      completion_summary: nil
    }

    # Store in metadata
    task_run.metadata ||= {}
    task_run.metadata["plan"] = plan_data
    task_run.save!

    # Broadcast to UI
    broadcast_plan_update(task_run, "created")

    { success: true, plan: plan_data }
  end

  def self.update_step(task_run, args)
    plan = task_run.metadata["plan"]
    step = plan["steps"].find { |s| s["id"] == args[:step_id] }

    return { error: "Step not found" } unless step

    # Update step
    step["status"] = args[:status]
    step["notes"] = args[:notes] if args[:notes]
    step["started_at"] ||= Time.current.iso8601 if args[:status] == "in_progress"
    step["completed_at"] = Time.current.iso8601 if ["completed", "failed", "skipped"].include?(args[:status])

    plan["updated_at"] = Time.current.iso8601
    task_run.save!

    # Broadcast to UI
    broadcast_plan_update(task_run, "step_updated", step_id: args[:step_id])

    { success: true, step: step }
  end

  def self.mark_task_complete(task_run, args)
    plan = task_run.metadata["plan"]
    plan["status"] = "completed"
    plan["completion_summary"] = args[:summary]
    plan["updated_at"] = Time.current.iso8601

    task_run.output_summary = args[:summary]
    task_run.save!

    # Broadcast to UI
    broadcast_plan_update(task_run, "completed")

    { success: true, summary: args[:summary] }
  end

  private

  def self.broadcast_plan_update(task_run, event_type, extra_data = {})
    Turbo::StreamsChannel.broadcast_replace_to(
      "task_run_#{task_run.id}",
      target: "execution_plan",
      partial: "prompt_tracker/task_runs/execution_plan",
      locals: { task_run: task_run, event: event_type }.merge(extra_data)
    )
  end
end
```

**UI Component (app/views/prompt_tracker/task_runs/_execution_plan.html.erb):**

```erb
<div id="execution_plan" class="card mb-4">
  <div class="card-header">
    <h5>
      <i class="bi bi-list-check"></i> Execution Plan
      <% if task_run.metadata.dig("plan", "status") == "completed" %>
        <span class="badge bg-success">Completed</span>
      <% elsif task_run.metadata.dig("plan", "status") == "in_progress" %>
        <span class="badge bg-primary">In Progress</span>
      <% else %>
        <span class="badge bg-secondary">Pending</span>
      <% end %>
    </h5>
  </div>
  <div class="card-body">
    <% if task_run.metadata["plan"] %>
      <% plan = task_run.metadata["plan"] %>

      <div class="mb-3">
        <strong>Goal:</strong> <%= plan["goal"] %>
      </div>

      <div class="progress mb-3" style="height: 25px;">
        <% completed = plan["steps"].count { |s| s["status"] == "completed" } %>
        <% total = plan["steps"].size %>
        <% percentage = (completed.to_f / total * 100).round %>
        <div class="progress-bar" role="progressbar" style="width: <%= percentage %>%">
          <%= completed %> / <%= total %> steps
        </div>
      </div>

      <div class="list-group">
        <% plan["steps"].each do |step| %>
          <div class="list-group-item">
            <div class="d-flex justify-content-between align-items-start">
              <div class="flex-grow-1">
                <div class="d-flex align-items-center mb-1">
                  <% case step["status"] %>
                  <% when "completed" %>
                    <i class="bi bi-check-circle-fill text-success me-2"></i>
                  <% when "in_progress" %>
                    <i class="bi bi-arrow-repeat text-primary me-2"></i>
                  <% when "failed" %>
                    <i class="bi bi-x-circle-fill text-danger me-2"></i>
                  <% when "skipped" %>
                    <i class="bi bi-skip-forward text-secondary me-2"></i>
                  <% else %>
                    <i class="bi bi-circle text-muted me-2"></i>
                  <% end %>
                  <strong><%= step["description"] %></strong>
                </div>

                <% if step["notes"] %>
                  <div class="text-muted small ms-4">
                    <%= step["notes"] %>
                  </div>
                <% end %>

                <% if step["completed_at"] %>
                  <div class="text-muted small ms-4">
                    Completed: <%= Time.parse(step["completed_at"]).strftime("%H:%M:%S") %>
                  </div>
                <% end %>
              </div>

              <span class="badge bg-<%= step_status_color(step["status"]) %>">
                <%= step["status"].titleize %>
              </span>
            </div>
          </div>
        <% end %>
      </div>

      <% if plan["completion_summary"] %>
        <div class="alert alert-success mt-3">
          <strong>Summary:</strong> <%= plan["completion_summary"] %>
        </div>
      <% end %>
    <% else %>
      <p class="text-muted">No plan created yet. Waiting for agent to create plan...</p>
    <% end %>
  </div>
</div>
```

**Turbo Stream Subscription (in task_runs/show.html.erb):**

```erb
<%= turbo_stream_from "task_run_#{@task_run.id}" %>

<div class="container">
  <h1>Task Run #<%= @task_run.id %></h1>

  <!-- Execution Plan (updates in real-time) -->
  <%= render "execution_plan", task_run: @task_run %>

  <!-- Execution Timeline -->
  <%= render "execution_timeline", task_run: @task_run %>
</div>
```

---

## Database Schema Changes

**No new tables in Phase 1** - Using existing `TaskRun.metadata` JSONB column.

**Future Phase 2 (Optional)** - If we need better querying/indexing:

```ruby
create_table :prompt_tracker_task_plans do |t|
  t.references :task_run, null: false, foreign_key: { to_table: :prompt_tracker_task_runs }
  t.text :goal, null: false
  t.string :status, null: false, default: "pending"
  t.text :completion_summary
  t.timestamps
end

create_table :prompt_tracker_task_plan_steps do |t|
  t.references :task_plan, null: false, foreign_key: { to_table: :prompt_tracker_task_plans }
  t.integer :order, null: false
  t.text :description, null: false
  t.string :status, null: false, default: "pending"
  t.text :notes
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end
```

---

## Configuration UI

**In DeployedAgent form (app/views/prompt_tracker/deployed_agents/_form.html.erb):**

```erb
<% if @agent.task? %>
  <div class="card mb-3">
    <div class="card-header">
      <h5>Planning Configuration</h5>
    </div>
    <div class="card-body">
      <div class="form-check mb-3">
        <%= f.check_box :planning_enabled,
            class: "form-check-input",
            data: { action: "change->planning-config#toggle" } %>
        <%= f.label :planning_enabled, class: "form-check-label" do %>
          <strong>Enable Planning Mode</strong>
          <div class="text-muted small">
            Requires agent to create explicit plans and mark tasks complete.
            Improves goal tracking and prevents over-iteration.
          </div>
        <% end %>
      </div>

      <div id="planning_options" style="<%= 'display: none;' unless @agent.planning_enabled? %>">
        <div class="mb-3">
          <%= f.label :max_plan_steps, "Maximum Plan Steps", class: "form-label" %>
          <%= f.number_field :max_plan_steps,
              value: @agent.task_config.dig("planning", "max_steps") || 20,
              class: "form-control",
              min: 3,
              max: 50 %>
          <div class="form-text">
            Maximum number of steps allowed in a plan (3-50)
          </div>
        </div>

        <div class="form-check">
          <%= f.check_box :allow_plan_modifications,
              checked: @agent.task_config.dig("planning", "allow_plan_modifications") != false,
              class: "form-check-input" %>
          <%= f.label :allow_plan_modifications, class: "form-check-label" do %>
            Allow plan modifications during execution
            <div class="text-muted small">
              Agent can add new steps or modify existing ones as it learns more
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

---

## Testing Strategy

### Unit Tests

```ruby
# spec/services/prompt_tracker/planning_service_spec.rb
RSpec.describe PromptTracker::PlanningService do
  describe ".create_plan" do
    it "creates a plan with steps in metadata" do
      task_run = create(:task_run)
      result = described_class.create_plan(task_run, {
        goal: "Fetch and summarize tech news",
        steps: ["Search for AI news", "Search for cloud news", "Create summary"]
      })

      expect(result[:success]).to be true
      expect(task_run.reload.metadata["plan"]["goal"]).to eq("Fetch and summarize tech news")
      expect(task_run.metadata["plan"]["steps"].size).to eq(3)
      expect(task_run.metadata["plan"]["steps"].first["status"]).to eq("pending")
    end
  end

  describe ".update_step" do
    it "updates step status and notes" do
      task_run = create(:task_run_with_plan)
      step_id = task_run.metadata["plan"]["steps"].first["id"]

      result = described_class.update_step(task_run, {
        step_id: step_id,
        status: "completed",
        notes: "Found 21,667 articles"
      })

      expect(result[:success]).to be true
      step = task_run.reload.metadata["plan"]["steps"].first
      expect(step["status"]).to eq("completed")
      expect(step["notes"]).to eq("Found 21,667 articles")
      expect(step["completed_at"]).to be_present
    end
  end
end
```

### Integration Tests

```ruby
# spec/services/prompt_tracker/task_agent_runtime_service_spec.rb
RSpec.describe PromptTracker::TaskAgentRuntimeService do
  context "with planning enabled" do
    it "injects planning functions" do
      agent = create(:deployed_agent, :task, :with_planning)
      task_run = create(:task_run, deployed_agent: agent)

      service = described_class.new(agent, task_run)
      functions = service.send(:available_functions)

      expect(functions.map { |f| f[:name] }).to include(
        "create_plan",
        "get_plan",
        "update_step",
        "mark_task_complete"
      )
    end

    it "requires explicit completion" do
      agent = create(:deployed_agent, :task, :with_planning)
      task_run = create(:task_run, deployed_agent: agent)

      # Simulate agent creating plan but not completing
      PlanningService.create_plan(task_run, {
        goal: "Test goal",
        steps: ["Step 1"]
      })

      service = described_class.new(agent, task_run)
      service.call

      # Should not be marked complete without mark_task_complete call
      expect(task_run.reload.status).not_to eq("completed")
    end
  end
end
```

---

## Rollout Plan

### Phase 1: Core Planning (Week 1-2)
- ✅ Create PRD (this document)
- [ ] Implement `PlanningService` with JSONB storage
- [ ] Add function injection to `TaskAgentRuntimeService`
- [ ] Update system prompt enhancement logic
- [ ] Add planning configuration to `DeployedAgent`
- [ ] Write unit tests

### Phase 2: UI & Streaming (Week 2-3)
- [ ] Create execution plan partial
- [ ] Implement Turbo Stream broadcasting
- [ ] Add planning configuration UI
- [ ] Add helper methods for status badges
- [ ] Write integration tests

### Phase 3: Testing & Refinement (Week 3-4)
- [ ] Test with real task agents
- [ ] Optimize system prompt instructions
- [ ] Add analytics/metrics for plan effectiveness
- [ ] Documentation and examples

### Phase 4: Optional Enhancements (Future)
- [ ] Migrate to dedicated tables if needed
- [ ] Add plan templates
- [ ] Add plan comparison across runs
- [ ] Add AI-powered plan suggestions

---

## Success Metrics

1. **Reduced over-iteration**: Task runs complete in fewer iterations
2. **Improved completion accuracy**: Agents correctly identify when done
3. **Better user visibility**: Users can see progress in real-time
4. **Higher quality outputs**: Structured planning leads to better results
5. **Developer adoption**: % of task agents using planning mode

---

## Open Questions

1. **Should planning be optional or required for all task agents?**
   - Decision: Required when enabled (no fallback to non-planning mode)

2. **How many steps should be recommended?**
   - Recommendation: 3-7 steps for most tasks, max 20

3. **Should we allow plan deletion/reset mid-execution?**
   - Decision: No - plans are immutable once created (can only update status/notes)

4. **What happens if agent never calls create_plan?**
   - Decision: Fail after 2 iterations with clear error message

5. **Should we support sub-steps or nested plans?**
   - Decision: Not in Phase 1 - keep it simple with flat step list

---

## Appendix: Example Planning Workflow

**Task**: "Monitor technology news and create a daily summary"

**Agent's Planning Workflow:**

```
Iteration 1:
  LLM: Calls create_plan({
    goal: "Gather and summarize latest tech news on AI, cloud, and cybersecurity",
    steps: [
      "Search for AI news articles",
      "Search for cloud computing news",
      "Search for cybersecurity news",
      "Synthesize findings into comprehensive summary"
    ]
  })
  Response: Plan created with 4 steps

Iteration 2:
  LLM: Calls update_step("step_1", "in_progress", "Starting AI news search")
  LLM: Calls fetch_news_articles({ topic: "AI", page_size: 5 })
  LLM: Calls update_step("step_1", "completed", "Found 21,667 articles, selected top 5")

Iteration 3:
  LLM: Calls update_step("step_2", "in_progress", "Starting cloud news search")
  LLM: Calls fetch_news_articles({ topic: "cloud computing", page_size: 5 })
  LLM: Calls update_step("step_2", "completed", "Found 3,140 articles, selected top 5")

Iteration 4:
  LLM: Calls update_step("step_3", "in_progress", "Starting cybersecurity news search")
  LLM: Calls fetch_news_articles({ topic: "cybersecurity", page_size: 5 })
  LLM: Calls update_step("step_3", "completed", "Found 14,325 articles, selected top 5")

Iteration 5:
  LLM: Calls update_step("step_4", "in_progress", "Creating summary")
  LLM: Generates comprehensive summary
  LLM: Calls mark_task_complete("Created comprehensive tech news summary covering AI (Pentagon adopts Palantir), cloud (Nvidia-Amazon deal), and cybersecurity (Canadian military EV concerns). All sources cited with dates.")

Task Run Status: completed ✅
```

**Key Improvements Over Current Behavior:**
- ✅ Clear plan visible from start
- ✅ Progress tracked step-by-step
- ✅ Explicit completion signal
- ✅ No over-iteration (stops after step 4 complete)
- ✅ Summary captures actual work done
