# Iteration 0 Proposal: Move Planning Outside Main Loop

## 🎯 Problem Statement

Currently, the `create_plan()` function call happens **inside Iteration 1**, which is confusing:

### Current Flow (Confusing ❌)
```
Iteration 1:
  - LLM Response with tool_calls: [create_plan, fetch_news, ...]
  - Execute: create_plan() → creates the plan
  - Execute: fetch_news() → fetches articles
  - Execute: other functions
  - Add results to conversation history
```

This makes the UI confusing because:
- Iteration 1 shows 4+ events (plan creation + actual work)
- The "plan" is conceptually separate from "executing the plan"
- It's unclear when planning ends and execution begins

## ✅ Proposed Solution: Iteration 0 (Setup Phase)

### New Flow (Clear ✅)
```
Iteration 0 (Setup/Planning):
  - LLM Response with tool_calls: [create_plan]
  - Execute: create_plan() → creates the plan
  - Add result to conversation history
  - Check if planning is complete

Iteration 1 (Execution):
  - LLM Response with tool_calls: [get_plan, update_step, fetch_news]
  - Execute: get_plan() → retrieves the plan
  - Execute: update_step(step_1, "in_progress")
  - Execute: fetch_news()
  - Execute: update_step(step_1, "completed")
  - Add results to conversation history

Iteration 2 (Execution):
  - LLM Response with tool_calls: [get_plan, update_step, ...]
  - Work on step 2
  - ...
```

## 🔧 Implementation Plan

### Option A: Dedicated Planning Phase (Recommended)
Add a separate `execute_planning_phase()` method that runs BEFORE the main loop:

```ruby
def execute
  # ... existing setup ...

  # Add initial user message to conversation history
  @conversation_history << { role: "user", content: initial_prompt }

  # NEW: Execute planning phase if enabled
  if @planning_enabled
    execute_planning_phase()
  end

  # Phase 2: Autonomous multi-turn execution loop
  final_output = execute_autonomous_loop(max_iterations, timeout_seconds)

  # ... rest of method ...
end

def execute_planning_phase
  @logger.info "[TaskAgentRuntimeService] 🎯 Starting Planning Phase (Iteration 0)"

  # Call LLM to create plan
  llm_response = call_llm(@conversation_history)

  # Add assistant response to conversation history
  @conversation_history << { role: "assistant", content: llm_response[:text] }

  # Track LLM response (but don't increment iteration count yet)
  track_llm_response(llm_response)

  # If there were function calls, add their results to conversation history
  if @current_iteration_function_calls.present?
    @current_iteration_function_calls.each do |func_call|
      @conversation_history << {
        role: "user",
        content: "Function '#{func_call[:name]}' returned: #{func_call[:result]}"
      }
    end
  end

  @logger.info "[TaskAgentRuntimeService] ✅ Planning Phase Complete"
end
```

### Option B: Iteration 0 Inside Loop
Keep the loop but start `@iteration_count` at 0 and treat iteration 0 specially:

```ruby
def execute_autonomous_loop(max_iterations, timeout_seconds)
  last_response_text = nil

  loop do
    # Check timeout/iteration limits (but skip for iteration 0)
    if @iteration_count > 0
      # ... existing timeout/iteration checks ...
    end

    # Execute iteration
    llm_response = execute_iteration
    last_response_text = llm_response[:text]

    # For iteration 0 (planning), continue to iteration 1
    if @iteration_count == 0 && @planning_enabled
      @iteration_count += 1
      next
    end

    # Check if task is complete
    if task_complete?(llm_response)
      @logger.info "[TaskAgentRuntimeService] Task completed after #{@iteration_count} iteration(s)"
      return last_response_text
    end

    @iteration_count += 1
  end
end
```

## 📊 Comparison

| Aspect | Option A (Dedicated Phase) | Option B (Iteration 0 in Loop) |
|--------|---------------------------|-------------------------------|
| **Clarity** | ✅ Very clear separation | ⚠️ Requires special-casing |
| **Code Complexity** | ✅ Simple, linear flow | ⚠️ More conditionals in loop |
| **UI Display** | ✅ Can show "Planning" separately | ✅ Shows as "Iteration 0" |
| **Flexibility** | ✅ Easy to add multi-step planning | ⚠️ Harder to extend |
| **Iteration Count** | ✅ Iterations 1-N are pure execution | ⚠️ Need to explain iteration 0 |

## 🎯 Recommendation

**Use Option A (Dedicated Planning Phase)** because:
1. Clearer conceptual separation between planning and execution
2. Easier to understand and maintain
3. More flexible for future enhancements (e.g., multi-step planning)
4. Iteration counts are more intuitive (1, 2, 3... instead of 0, 1, 2...)
5. UI can show "Planning Phase" as a distinct section

## 📝 Implementation Status

1. ✅ **DONE**: Implement `execute_planning_phase()` method
   - Added dedicated method that runs before `execute_autonomous_loop`
   - Stores planning phase metadata in `task_run.metadata["planning_phase"]`
   - Tracks duration and status

2. ✅ **DONE**: Update `call_llm` to accept phase parameter
   - Added `phase: :planning` or `phase: :execution` parameter
   - Passes phase to `enhance_system_prompt_with_planning`

3. ✅ **DONE**: Update system prompt to clarify planning vs execution phases
   - Planning phase: Focus ONLY on calling `create_plan()`
   - Execution phase: Focus on executing steps with `get_plan()`, `update_step()`, etc.

4. ✅ **DONE**: Update UI to show planning phase separately from iterations
   - Added prominent blue-bordered card before Execution Timeline
   - Shows "Planning Phase (Iteration 0)" header
   - Displays planning LLM call and function calls
   - Shows duration and status

5. ⏳ **TODO**: Test with a new task run
6. ⏳ **TODO**: Verify logs show clear separation
