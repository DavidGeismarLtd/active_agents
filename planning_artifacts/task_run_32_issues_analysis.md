# Task Run #32 - Issues Analysis

## 🔍 Issues Found

### Issue 1: Planning Phase Card Shows "Planning phase data not found" ❌

**Symptom:**
- Execution Plan card shows all steps correctly
- Planning Phase card says "Planning phase data not found in LLM responses"
- Both exist simultaneously (contradictory state)

**Root Cause:**
The view was looking for `tc["name"]` but RubyLLM stores tool calls with `tc["function_name"]`.

**Actual tool_calls structure:**
```json
{
  "id": "call_MW2O7kkuiJMwIyfr2EF1UQk5",
  "type": "function",
  "function_name": "create_plan",  // ← Uses "function_name" not "name"
  "arguments": { ... }
}
```

**Fix Applied:**
Updated `app/views/prompt_tracker/task_runs/show.html.erb` to check both fields:
```ruby
# Line 160: Find planning response
planning_response = @llm_responses.find { |r| 
  r.tool_calls&.any? { |tc| 
    tc["function_name"] == "create_plan" || tc["name"] == "create_plan" 
  } 
}

# Line 179: Display function name
<span class="badge bg-primary"><%= tc["function_name"] || tc["name"] %></span>
```

---

### Issue 2: All Steps Show "Pending" Despite Task Completion ⚠️

**Symptom:**
- Task status: "completed"
- Plan status: "completed"
- All 5 steps show status: "pending"
- Completion summary exists

**Root Cause:**
The LLM agent **skipped calling `update_step()` functions** during execution. It:
1. Created the plan (Iteration 0)
2. Executed all the work (fetched news, analyzed)
3. Called `mark_task_complete()` directly
4. Never updated individual step statuses

**Evidence from logs:**
```
Line 23: create_plan() called ✅
Line 26-43: fetch_news_articles() called 3 times ✅
Line 62: mark_task_complete() called ✅
Missing: update_step() calls ❌
```

**Why This Happened:**
The LLM decided to execute all steps in one iteration without updating progress. This is a **prompt engineering issue**, not a code bug.

**Possible Solutions:**

**Option A: Stricter System Prompt** (Recommended)
Add explicit instructions to the execution phase prompt:
```
IMPORTANT: After completing each step, you MUST call update_step() to mark it as completed.
Example workflow:
1. Call update_step(step_id="step_1", status="in_progress")
2. Execute the work for step 1
3. Call update_step(step_id="step_1", status="completed", notes="...")
4. Move to step 2
```

**Option B: Auto-Update Steps Based on Function Calls**
Track which functions were called and auto-update related steps:
- If `fetch_news_articles(topic="AI")` → mark step_1 as completed
- Requires mapping between functions and steps

**Option C: Post-Completion Step Inference**
When `mark_task_complete()` is called, automatically mark all pending steps as "completed":
```ruby
# In PlanningService.mark_task_complete
plan[:steps].each do |step|
  step[:status] = "completed" if step[:status] == "pending"
  step[:completed_at] = Time.current
end
```

---

## 📊 Task Run #32 Summary

**What Actually Happened:**
1. ✅ Planning Phase (Iteration 0): Created plan with 5 steps
2. ✅ Iteration 0: Executed all 3 fetch_news_articles calls
3. ✅ Iteration 1: Analyzed results
4. ✅ Iteration 2: Called mark_task_complete with summary
5. ❌ Never called update_step() for any step

**Metadata State:**
```json
{
  "plan": {
    "status": "completed",
    "steps": [
      { "id": "step_1", "status": "pending" },  // ← Should be "completed"
      { "id": "step_2", "status": "pending" },  // ← Should be "completed"
      { "id": "step_3", "status": "pending" },  // ← Should be "completed"
      { "id": "step_4", "status": "pending" },  // ← Should be "completed"
      { "id": "step_5", "status": "pending" }   // ← Should be "completed"
    ],
    "completion_summary": "The latest news reveals..."
  }
}
```

---

## ✅ Fixes Applied

1. **Planning Phase Display** - Fixed ✅
   - Updated view to use `tc["function_name"]` instead of `tc["name"]`
   - Planning Phase card now shows correctly

2. **Step Status Updates** - Needs Decision ⚠️
   - Choose one of the 3 options above
   - Recommend: Option A (stricter prompt) + Option C (auto-complete fallback)

---

## 🎯 Recommendation

Implement **both Option A and Option C**:

1. **Update system prompt** to explicitly require `update_step()` calls
2. **Add fallback logic** in `mark_task_complete()` to auto-complete pending steps

This provides:
- ✅ Clear guidance to the LLM (reduces skipping)
- ✅ Graceful degradation (if LLM still skips, steps get completed anyway)
- ✅ Accurate UI (steps always reflect reality)

