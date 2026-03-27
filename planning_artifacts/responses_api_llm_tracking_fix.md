# Responses API LLM Tracking Fix

## Problem

The OpenAI Responses API uses a stateful function-calling loop where:
1. Initial API call returns tool calls
2. Functions are executed
3. Continuation API call is made with function results
4. Steps 2-3 repeat until no more tool calls

**Previous Behavior:**
- Only ONE `LlmResponse` record was created at the END of the entire loop
- Function executions appeared in the timeline WITHOUT preceding LLM intent cards
- Users couldn't see WHAT the LLM decided to do before functions executed

**Example Timeline (Before Fix):**
```
Iteration 1
├─ ⚙️ Function: get_plan (07:27:08)          ❌ No LLM intent visible
├─ ⚙️ Function: update_step (07:27:59)       ❌ No LLM intent visible
├─ ⚙️ Function: fetch_news (07:28:34)        ❌ No LLM intent visible
├─ ⚙️ Function: update_step (07:30:05)       ❌ No LLM intent visible
└─ 🤖 LLM Response (07:38:28)                ✅ Only final response visible
```

## Solution

Track EACH API call (initial + all continuations) as separate `LlmResponse` records.

**New Behavior:**
- Create `LlmResponse` record after initial API call (if tool calls present)
- Create `LlmResponse` record after EACH continuation API call
- Each record shows the LLM's intent (tool calls) and reasoning

**Example Timeline (After Fix):**
```
Iteration 1
├─ 🤖 LLM Response #1 (07:27:08)             ✅ Intent: call get_plan
├─ ⚙️ Function: get_plan (07:27:08)
├─ 🤖 LLM Response #2 (07:27:59)             ✅ Intent: call update_step
├─ ⚙️ Function: update_step (07:27:59)
├─ 🤖 LLM Response #3 (07:28:34)             ✅ Intent: call fetch_news
├─ ⚙️ Function: fetch_news (07:28:34)
├─ 🤖 LLM Response #4 (07:30:05)             ✅ Intent: call update_step
├─ ⚙️ Function: update_step (07:30:05)
└─ 🤖 LLM Response #5 (07:38:28)             ✅ Final response
```

## Implementation

### Changes Made

#### 1. `app/services/prompt_tracker/task_agent_runtime_service/openai_responses.rb`

**In `call_llm` method:**
- Track initial response if it contains tool calls
- Pass `initial_prompt` to `handle_function_call_loop`

```ruby
# Track the initial LLM response to capture the initial intent (tool calls)
if response[:tool_calls].present?
  track_llm_response(response, rendered_prompt: user_prompt)
end

# Handle function call loop with initial prompt for tracking
response = handle_function_call_loop(response, model_config, initial_prompt: user_prompt)
```

**In `handle_function_call_loop` method:**
- Track each continuation response after API call
- Build descriptive prompt showing which functions were executed

```ruby
# Track each continuation response
function_summary = tool_calls.map { |tc| tc[:function_name] }.join(", ")
continuation_prompt = "Function results for: #{function_summary}"
track_llm_response(response, rendered_prompt: continuation_prompt)
```

#### 2. `app/services/prompt_tracker/task_agent_runtime_service.rb`

**In `track_llm_response` method:**
- Accept optional `rendered_prompt` parameter
- Use explicit prompt if provided, otherwise fall back to conversation history

```ruby
def track_llm_response(llm_response, rendered_prompt: nil)
  # Use explicit prompt if provided, otherwise fall back to conversation history
  rendered_prompt ||= begin
    last_user_message = @conversation_history.reverse.find { |msg| msg[:role] == "user" }
    last_user_message&.dig(:content) || ""
  end
  
  # ... rest of method unchanged ...
end
```

## Benefits

1. ✅ **Complete Visibility:** See LLM's intent before each function execution
2. ✅ **Better Debugging:** Understand why the LLM called each function
3. ✅ **Transparent Timeline:** Events appear in chronological order with proper context
4. ✅ **Backward Compatible:** Existing code continues to work (optional parameter)

## Testing

### Manual Test
Run the test script:
```bash
rails runner test_responses_api_tracking.rb
```

This will:
1. Find or create a task agent using gpt-5-pro (Responses API)
2. Execute the task
3. Count how many `LlmResponse` records were created
4. Display the timeline

### Expected Results
- Multiple `LlmResponse` records created (not just 1)
- Each function execution preceded by an LLM response showing intent
- Timeline shows complete flow of LLM reasoning

### Real-World Test
1. Execute a task agent with planning enabled
2. View the task run timeline
3. Verify that each function execution has a preceding LLM response card showing the tool call intent

## Notes

- This creates more `LlmResponse` records (10x in some cases)
- This is intentional and desired for full transparency
- Each `track_llm_response` call triggers a Turbo Stream broadcast
- Timeline updates in real-time as the agent executes

## Related Files
- `app/services/prompt_tracker/task_agent_runtime_service/openai_responses.rb`
- `app/services/prompt_tracker/task_agent_runtime_service.rb`
- `app/controllers/prompt_tracker/task_runs_controller.rb` (timeline building)
- `app/views/prompt_tracker/task_runs/_llm_call_card.html.erb` (displays tool calls)

