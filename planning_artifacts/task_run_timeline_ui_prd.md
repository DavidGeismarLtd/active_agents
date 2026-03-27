# Task Run Timeline UI - Product Requirements Document

## 📋 Overview

**Goal:** Transform the Task Run show page timeline from a simple chronological list into an interactive, granular, and insightful execution viewer that helps developers understand exactly what the agent did, why, and how.

**Current State:**
- Simple timeline with two event types: "LLM Response" and "Function Execution"
- Large, always-expanded cards that make the page very long
- No distinction between LLM's intent (tool calls) and actual execution results
- Missing planning context, iteration boundaries, and decision points
- No interactivity (filtering, collapsing, searching)

**Target State:**
- Granular timeline showing: Iterations → LLM Calls → Tool Call Intents → Function Executions → Planning Updates
- Collapsible cards with smart previews
- Clear visual hierarchy and flow indicators
- Planning step context integrated throughout
- Interactive controls (expand/collapse all, filter, search)
- Performance metrics and insights

---

## 🎯 User Stories

### Primary Users: Developers debugging/monitoring task agents

**US-1:** As a developer, I want to see iteration boundaries clearly so I understand the agent's thought cycles.

**US-2:** As a developer, I want to distinguish between "LLM decided to call function X" and "Function X returned Y" so I understand the agent's intent vs. reality.

**US-3:** As a developer, I want to see which planning step the agent was working on during each action so I can track progress against the plan.

**US-4:** As a developer, I want to collapse large JSON responses so I can scan the timeline quickly without scrolling through walls of text.

**US-5:** As a developer, I want to see why the agent stopped (completed, max iterations, timeout, error) so I can diagnose issues.

**US-6:** As a developer, I want to filter timeline events by type (LLM calls, functions, planning) so I can focus on specific aspects.

**US-7:** As a developer, I want to see cumulative metrics (time, cost, tokens) as I scroll through the timeline.

---

## 📊 Timeline Event Types

### 1. **Iteration Marker** (NEW)
- **Purpose:** Group events by iteration cycle
- **Data Source:** `LlmResponse.context[:iteration]`
- **Display:**
  - Iteration number badge
  - Duration (time between iterations)
  - Event count (LLM calls + function calls)
  - Collapsible section containing all events in that iteration

### 2. **LLM Call** (ENHANCED)
- **Purpose:** Show what the LLM received and what it decided to do
- **Data Source:** `LlmResponse`
- **Display:**
  - **Collapsed:** Model, tokens, duration, tool call count
  - **Expanded:** Full prompt, system prompt, response text, tool calls (intent), usage stats
  - **New:** Show tool calls as "Intent" badges (e.g., "Decided to call: create_plan, fetch_news")

### 3. **Tool Call Intent** (NEW)
- **Purpose:** Show LLM's decision to call a function BEFORE execution
- **Data Source:** Extract from `LlmResponse` (need to store tool_calls in response)
- **Display:**
  - Function name
  - Arguments (collapsed by default)
  - "Executing..." indicator
  - Link to corresponding execution result

### 4. **Function Execution** (ENHANCED)
- **Purpose:** Show actual execution result
- **Data Source:** `FunctionExecution`
- **Display:**
  - **Collapsed:** Function name, success/failure, duration
  - **Expanded:** Arguments, result, error message
  - **New:** Link back to tool call intent
  - **New:** Planning step reference (if applicable)

### 5. **Planning Event** (NEW)
- **Purpose:** Show planning function calls (create_plan, update_step, etc.)
- **Data Source:** `FunctionExecution` where function is a planning function
- **Display:**
  - Planning action (e.g., "Created plan", "Updated step 2: completed")
  - Step details
  - Status change visualization
  - Link to execution plan card

### 6. **Decision Marker** (NEW)
- **Purpose:** Show agent's decision to continue or stop
- **Data Source:** Inferred from iteration flow + task_run status
- **Display:**
  - "Continuing to next iteration..." (if more iterations follow)
  - "Task completed" (if plan status = completed)
  - "Stopped: Max iterations reached" (if forced completion)
  - "Stopped: Timeout" (if timeout)

---

## 🎨 UI Components

### Component 1: Iteration Group Card
```
┌─────────────────────────────────────────────────────────┐
│ 🔄 Iteration 1                          [Expand/Collapse]│
│ ⏱️ 2.3s  |  💬 1 LLM call  |  ⚙️ 3 functions            │
├─────────────────────────────────────────────────────────┤
│ [Nested timeline events when expanded]                  │
│   ├─ LLM Call #1                                        │
│   ├─ Tool Intent: create_plan                           │
│   ├─ Function Execution: create_plan ✅                 │
│   ├─ Tool Intent: fetch_news                            │
│   ├─ Function Execution: fetch_news ✅                  │
│   └─ Decision: Continue to iteration 2                  │
└─────────────────────────────────────────────────────────┘
```

### Component 2: LLM Call Card (Collapsed)
```
┌─────────────────────────────────────────────────────────┐
│ 💬 LLM Call #1  |  gpt-4o  |  ⏱️ 1.2s  |  🎫 234 tokens │
│ 🎯 Tool Calls: create_plan, fetch_news                  │
│ 📋 Working on: Step 1 - Gather news articles            │
│                                          [Expand ▼]      │
└─────────────────────────────────────────────────────────┘
```

### Component 3: LLM Call Card (Expanded)
```
┌─────────────────────────────────────────────────────────┐
│ 💬 LLM Call #1  |  gpt-4o  |  ⏱️ 1.2s  |  🎫 234 tokens │
│ 🎯 Tool Calls: create_plan, fetch_news                  │
│ 📋 Working on: Step 1 - Gather news articles            │
│                                          [Collapse ▲]    │
├─────────────────────────────────────────────────────────┤
│ **Prompt Sent:**                                        │
│ [Syntax-highlighted prompt with copy button]            │
│                                                          │
│ **Response Text:**                                       │
│ "I'll start by creating a plan..."                      │
│                                                          │
│ **Tool Calls (Intent):**                                │
│ 1. create_plan({ goal: "...", steps: [...] })          │
│ 2. fetch_news({ query: "AI" })                         │
│                                                          │
│ **Metrics:**                                             │
│ Prompt: 180 tokens | Completion: 54 tokens | $0.0023   │
└─────────────────────────────────────────────────────────┘
```

### Component 4: Function Execution Card (Collapsed)
```
┌─────────────────────────────────────────────────────────┐
│ ⚙️ fetch_news  |  ✅ Success  |  ⏱️ 450ms                │
│ 📋 For: Step 1 - Gather news articles                   │
│                                          [Expand ▼]      │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Implementation Plan

### Phase 1: Data Layer (Backend)
**Goal:** Ensure all necessary data is available

1. **Store tool calls in LlmResponse**
   - Add `tool_calls` jsonb column to `llm_responses` table
   - Update `TaskAgentRuntimeService.track_llm_response` to store tool calls from RubyLLM response
   - Structure: `[{ id: "call_1", name: "create_plan", arguments: {...} }]`

2. **Add planning step reference to FunctionExecution**
   - Add `planning_step_id` string column to `function_executions` table
   - Update function executor to detect current step from plan and store reference
   - Example: `"step_2"` when executing during step 2

3. **Store iteration metadata**
   - Already available in `LlmResponse.context[:iteration]`
   - Ensure consistent across all records

4. **Add decision markers**
   - Store in `TaskRun.metadata[:decisions]` array
   - Structure: `[{ iteration: 1, type: "continue", reason: "..." }]`

### Phase 2: View Layer (Frontend)
**Goal:** Build interactive UI components

1. **Reuse existing Stimulus controllers (where possible):**
   - ✅ **`prompt_search_controller.js`** - Can be reused for timeline search
     - Already handles: search input, filtering items by query, auto-expanding matches
     - Needs: Minor adaptation to search within timeline events (prompts, responses, arguments)

   - ✅ **`column_visibility_controller.js`** - Can be adapted for event type filtering
     - Already handles: toggle visibility, localStorage persistence, show/hide all
     - Needs: Rename to work with event types instead of columns

   - ❌ **`linked_filters_controller.js`** - Not applicable (specific to provider/model dropdowns)

2. **Create NEW Stimulus controller: `task_timeline_controller.js`**
   - Actions:
     - `expandAll()` - Expand all iteration groups and cards
     - `collapseAll()` - Collapse all iteration groups and cards
     - `toggleIteration(event)` - Toggle specific iteration group
     - `toggleCard(event)` - Toggle specific event card
   - Targets:
     - `iterationGroup` - All iteration group containers
     - `eventCard` - All expandable event cards
     - `expandAllButton` - Expand all button
     - `collapseAllButton` - Collapse all button
   - Values:
     - `storageKey` - localStorage key for persistence (optional Phase 3)

3. **Create partials:**
   - `_iteration_group.html.erb` - Iteration boundary card
   - `_llm_call_card.html.erb` - Enhanced LLM call (replace current)
   - `_tool_call_intent.html.erb` - NEW: Tool call intent marker
   - `_function_execution_card.html.erb` - Enhanced (replace current)
   - `_planning_event.html.erb` - NEW: Planning-specific display
   - `_decision_marker.html.erb` - NEW: Decision point marker

4. **Update controller: `TaskRunsController#show`**
   - Build hierarchical timeline structure (iterations → events)
   - Group events by iteration
   - Inject decision markers
   - Calculate cumulative metrics

### Phase 3: Interactivity
**Goal:** Add user controls

1. **Expand/Collapse** (via `task_timeline_controller.js`)
   - Individual cards (click card header)
   - All cards in iteration (click iteration header)
   - All iterations (toolbar buttons)
   - State persistence in localStorage (optional)

2. **Filtering** (adapt `column_visibility_controller.js` → `timeline_event_filter_controller.js`)
   - By event type: LLM Calls, Function Executions, Planning Events, Tool Intents
   - By status: Success, Failed
   - Checkboxes in toolbar
   - Persist filter state in localStorage

3. **Search** (reuse `prompt_search_controller.js`)
   - Search within: prompts, responses, function arguments, function results
   - Auto-expand matching events
   - Highlight search terms (optional enhancement)
   - Clear search button

4. **Copy to Clipboard** (new functionality in `task_timeline_controller.js`)
   - Copy individual event JSON (button on each card)
   - Copy full iteration JSON (button on iteration header)
   - Copy entire timeline JSON (toolbar button)
   - Show "Copied!" toast notification

---

## 🔄 Stimulus Controller Reusability Analysis

### ✅ Controllers We Can Reuse

**1. `prompt_search_controller.js`** - Timeline Search
- **Current use:** Search prompts and versions in accordion
- **Reuse for:** Search timeline events (prompts, responses, arguments, results)
- **Adaptation needed:**
  - Change `data-prompt-name` to `data-searchable-content`
  - Search within nested JSON content
  - Auto-expand matching iteration groups
- **Benefit:** Already handles auto-expand, show/hide logic, query normalization

**2. `column_visibility_controller.js`** - Event Type Filtering
- **Current use:** Show/hide table columns with localStorage persistence
- **Reuse for:** Show/hide event types (LLM calls, functions, planning, intents)
- **Adaptation needed:**
  - Rename to `timeline_event_filter_controller.js`
  - Change `data-column` to `data-event-type`
  - Apply to timeline events instead of table cells
- **Benefit:** Already handles localStorage persistence, show/hide all, checkbox state

### ❌ Controllers We Cannot Reuse

**1. `linked_filters_controller.js`** - Too specific to provider/model dropdowns
**2. `batch_select_controller.js`** - For batch operations, not expand/collapse
**3. `playground_*_controller.js`** - All playground-specific

### 🆕 New Controller Needed

**`task_timeline_controller.js`** - Expand/Collapse & Copy
- Handles iteration group expand/collapse
- Handles individual card expand/collapse
- Copy to clipboard functionality
- Optional: State persistence

---

## 📐 Data Structure Changes

### Migration 1: Add tool_calls to llm_responses
```ruby
add_column :prompt_tracker_llm_responses, :tool_calls, :jsonb, default: []
```

### Migration 2: Add planning_step_id to function_executions
```ruby
add_column :prompt_tracker_function_executions, :planning_step_id, :string
add_index :prompt_tracker_function_executions, :planning_step_id
```

---

## 🎯 Success Metrics

1. **Usability:** Developers can understand a task run's execution flow in < 30 seconds
2. **Performance:** Timeline loads in < 1 second for runs with 100+ events
3. **Clarity:** 90% of timeline events are collapsed by default, showing only essential info
4. **Insight:** Planning step context visible for all relevant events
5. **Debugging:** Developers can identify failure points in < 10 seconds

---

## 📸 Visual Mockup

### Before (Current State):
```
Timeline
├─ LLM Response #1 [HUGE CARD - always expanded]
│  └─ [Full prompt, full response, all metadata visible]
├─ Function: create_plan [HUGE CARD]
│  └─ [Full arguments, full result visible]
├─ Function: fetch_news [HUGE CARD]
│  └─ [Full arguments, full result visible]
├─ LLM Response #2 [HUGE CARD]
│  └─ [Everything visible]
└─ ...

❌ Problems:
- No iteration grouping
- No distinction between intent and execution
- Everything always expanded
- No planning context
- Hard to scan
```

### After (Target State):
```
[🔍 Search] [Filter: All ▼] [⬇️ Expand All] [⬆️ Collapse All]

┌─ 🔄 Iteration 1 ────────────────────────────────── [▼] ─┐
│ ⏱️ 2.3s  |  💬 1 LLM  |  ⚙️ 3 functions  |  📋 Step 1    │
│                                                           │
│  08:32:11.123 💬 LLM Call #1                      [▼]    │
│  ├─ gpt-4o | 234 tokens | 1.2s | $0.0023               │
│  ├─ 🎯 Decided to call: create_plan, fetch_news         │
│  └─ 📋 Working on: Step 1 - Gather news                 │
│                                                           │
│  08:32:11.456 🎯 Tool Intent: create_plan                │
│  └─ Arguments: { goal: "...", steps: [...] }            │
│                                                           │
│  08:32:11.489 ⚙️ Function: create_plan          ✅ [▼]  │
│  └─ 45ms | Planning function                            │
│                                                           │
│  08:32:11.490 📋 Planning: Plan created                  │
│  └─ 5 steps defined                                      │
│                                                           │
│  08:32:11.567 🎯 Tool Intent: fetch_news                 │
│  └─ Arguments: { query: "AI advances" }                 │
│                                                           │
│  08:32:12.012 ⚙️ Function: fetch_news           ✅ [▼]  │
│  └─ 450ms | 21,667 results                              │
│                                                           │
│  08:32:12.123 ➡️ Decision: Continue to iteration 2       │
└───────────────────────────────────────────────────────────┘

┌─ 🔄 Iteration 2 ────────────────────────────────── [▼] ─┐
│ ⏱️ 1.8s  |  💬 1 LLM  |  ⚙️ 2 functions  |  📋 Step 2    │
│ [Collapsed - click to expand]                            │
└───────────────────────────────────────────────────────────┘

┌─ 🔄 Iteration 3 ────────────────────────────────── [▼] ─┐
│ ⏱️ 1.5s  |  💬 1 LLM  |  ⚙️ 1 function   |  📋 Step 3    │
│ [Collapsed - click to expand]                            │
└───────────────────────────────────────────────────────────┘

🏁 Task Completed
└─ Reason: Agent called mark_task_complete()
└─ Total: 5.6s | 3 iterations | $0.0089

✅ Benefits:
- Clear iteration boundaries
- Intent vs. execution separated
- Collapsed by default
- Planning context everywhere
- Easy to scan and drill down
```

---

## 🚀 Next Steps

1. Review and approve this PRD
2. Create implementation tasks
3. Start with Phase 1 (Data Layer)
4. Build Phase 2 (View Layer) with basic display
5. Add Phase 3 (Interactivity) incrementally

---

## 💡 Open Questions

1. **Should we show the full conversation history in each LLM call?**
   - Pro: Complete context visibility
   - Con: Very verbose, especially in later iterations
   - **Proposal:** Show only the latest user message by default, with "View full conversation" link

2. **How to handle planning functions in the timeline?**
   - Option A: Show them as regular function executions
   - Option B: Show them as special "Planning Events" with custom styling
   - **Proposal:** Option B - they're conceptually different from business logic functions

3. **Should we persist expand/collapse state across page refreshes?**
   - Pro: Better UX for debugging long runs
   - Con: Adds complexity (localStorage or URL params)
   - **Proposal:** Start without persistence, add if users request it

4. **How to display the "decision to continue" marker?**
   - Option A: Separate timeline event
   - Option B: Footer of iteration card
   - **Proposal:** Option B - it's metadata about the iteration, not a separate event
