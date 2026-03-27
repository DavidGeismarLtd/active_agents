# Task Run Improvements Summary

## Changes Implemented

### 1. ✅ Dedicated Logging System

**What**: Each task run now creates its own log file at `log/task_executions/task_run_X.log`

**Why**: Makes it easy to analyze individual task runs without searching through the main Rails log

**Files Changed**:
- `app/jobs/prompt_tracker/execute_task_agent_job.rb`
- `app/services/prompt_tracker/task_agent_runtime_service.rb`

**Log Contents**:
- Execution start/end markers
- Metadata and execution overrides (e.g., `max_iterations: 9`)
- All LLM calls and function executions
- Exception details with full backtraces

---

### 2. ✅ Improved Function Descriptions (fetch_news_articles)

**What**: Updated the `fetch_news_articles` function description to explicitly state API constraints

**Why**: Prevents the LLM from making invalid queries (e.g., using commas which cause syntax errors)

**Files Changed**:
- `test/dummy/db/seeds/12_functions.rb`

**Before**:
```
"description": "Fetch latest news articles from GNews API for a given topic"
```

**After**:
```
"description": "Fetch latest news articles from GNews API for a given topic. 
IMPORTANT: The 'topic' parameter must be a simple search phrase without commas 
or special characters. Use spaces to separate keywords (e.g., 'artificial intelligence' 
or 'cybersecurity news'). Do NOT use commas like 'AI, machine learning' - this will 
cause a syntax error."
```

**Parameter Description Updated**:
```
"topic": {
  "description": "News topic or search query. Use simple phrases with spaces only 
  (e.g., 'artificial intelligence', 'climate change policy'). Do NOT use commas, 
  quotes, or special operators."
}
```

---

### 3. ✅ Enhanced Planning Instructions

**What**: Updated the system prompt to guide the LLM to properly manage step states

**Why**: Prevents steps from being stuck in "in_progress" or "pending" when the task completes

**Files Changed**:
- `app/services/prompt_tracker/task_agent_runtime_service.rb` (method: `enhance_system_prompt_with_planning`)

**Key Additions**:

#### Step Execution Guidance:
```
2. **Execute Steps Sequentially** (Subsequent Iterations):
   - Work on ONE step at a time
   - ALWAYS update the step status before moving to the next step
   - At the end of each iteration, reflect: Did I complete/fail the current step?
```

#### Cleanup Before Completion (NEW):
```
5. **Clean Up Before Completion** (CRITICAL):
   - BEFORE calling `mark_task_complete()`, you MUST clean up all step statuses:
     * Any steps still "in_progress" → update to "completed", "failed", or "skipped"
     * Any steps still "pending" that won't be done → update to "skipped"
   - Example cleanup sequence:
     update_step("step_3", "completed", "Finished analysis")
     update_step("step_4", "skipped", "Not needed due to earlier errors")
     update_step("step_5", "skipped", "Cannot proceed without step 2 data")
     mark_task_complete("Summary of what was accomplished...")
```

#### User-Facing Reminder:
```
REMEMBER: The UI shows step statuses to users. Always keep them accurate and up-to-date!
```

---

## Design Decisions

### Why NOT Auto-Transition Steps?

**Decision**: Let the LLM manage step states instead of auto-transitioning them in code

**Rationale**:
1. **LLM has context**: The LLM knows WHY a step wasn't completed (error, skipped, etc.)
2. **Better notes**: The LLM can add meaningful notes explaining what happened
3. **More flexible**: Different scenarios need different handling (failed vs skipped vs completed)
4. **Aligns with workflow**: The LLM is already managing the plan, so it should manage cleanup too

**Alternative Considered**: Auto-transition in `PlanningService.mark_task_complete`
- Would be simpler but loses context
- Generic notes like "Auto-completed on task finish" aren't helpful

---

### Why NOT Custom Error Parsing?

**Decision**: Update function descriptions instead of adding error parsing logic

**Rationale**:
1. **Scalable**: Each function documents its own constraints
2. **Self-documenting**: The LLM sees the rules when it calls the function
3. **No code changes**: Just update the seed data, no service layer changes
4. **Flexible**: Different functions have different rules

**Alternative Considered**: Parse API errors and return helpful messages
- Would require custom logic for each API
- Not scalable as we add more functions
- Function descriptions are the right place for this info

---

## Testing Instructions

### 1. Test Dedicated Logging
```bash
# Reseed the database to get updated function descriptions
cd test/dummy && bin/rails db:seed

# Run a task agent
# Then check the log file:
cat log/task_executions/task_run_23.log
```

### 2. Test Function Description Updates
- Run a task that uses `fetch_news_articles`
- The LLM should NOT use commas in the topic parameter
- If it does, it should self-correct after seeing the error

### 3. Test Planning Step Cleanup
- Run a task with planning enabled
- Let it complete (or fail)
- Check the timeline - all steps should have final statuses:
  - ✅ No steps stuck in "in_progress"
  - ✅ No steps stuck in "pending" (should be "skipped")
  - ✅ Each step has meaningful notes

---

## Expected Behavior Changes

### Before:
```json
{
  "plan": {
    "status": "completed",
    "steps": [
      {"id": "step_1", "status": "in_progress"},  // ❌ Stuck
      {"id": "step_2", "status": "failed"},
      {"id": "step_3", "status": "pending"}       // ❌ Stuck
    ]
  }
}
```

### After:
```json
{
  "plan": {
    "status": "completed",
    "steps": [
      {"id": "step_1", "status": "completed", "notes": "Fetched 10 articles"},
      {"id": "step_2", "status": "failed", "notes": "API syntax error"},
      {"id": "step_3", "status": "skipped", "notes": "Cannot proceed without step 2 data"}
    ]
  }
}
```

