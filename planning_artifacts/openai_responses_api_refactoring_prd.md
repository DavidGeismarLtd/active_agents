# PRD: OpenAI Responses API Refactoring

## Status: ✅ COMPLETED

All phases have been implemented successfully.

## Overview

This document outlines the bugs and architectural improvements needed for the OpenAI Responses API integration in PromptTracker.

## Context

During test runs using the OpenAI Responses API with function calling, we encountered a 400 error:
```
"No tool call found for function call output with call_id"
```

Investigation revealed both a critical bug and several architectural issues that need to be addressed.

---

## 1. Critical Bug: Function Call Output Format

### Problem
When sending `function_call_output` items to the Responses API, the current implementation only sends the outputs without the original `function_call` items.

**Current behavior** (incorrect):
```ruby
input: [
  { type: "function_call_output", call_id: "call_xyz", output: "..." }
]
```

**Required behavior** (per OpenAI docs):
```ruby
input: [
  { type: "function_call", call_id: "call_xyz", name: "get_weather", arguments: "{...}" },
  { type: "function_call_output", call_id: "call_xyz", output: "..." }
]
```

### Affected Files
- `app/services/prompt_tracker/test_runners/helpers/function_call_handler.rb`
  - `call_api_with_function_outputs` method (line 134-143)
  - `build_function_outputs` method needs to also return original function calls

### Fix Required
Modify `call_api_with_function_outputs` to:
1. Accept the original `tool_calls` (not just outputs)
2. Build an input array that pairs each `function_call` with its `function_call_output`

---

## 2. Namespace: FunctionCallHandler Location

### Problem
`FunctionCallHandler` is currently located in a generic `Helpers` namespace but is specific to the OpenAI Responses API.

**Current location:**
```
PromptTracker::TestRunners::Helpers::FunctionCallHandler
```

**Evidence it's Responses API-specific:**
- Docstring says "Handles function call loops for OpenAI Response API"
- Directly calls `OpenaiResponseService.call_with_context`
- Uses `previous_response_id` (Responses API concept)
- NOT used by `ChatCompletions::SimulatedConversationRunner`

### Proposed Location
```
PromptTracker::Openai::Responses::FunctionCallHandler
```

Or within the test runners:
```
PromptTracker::TestRunners::Openai::Responses::FunctionCallHandler
```

---

## 3. Architecture: OpenaiResponseService Responsibilities

### Problem
`OpenaiResponseService` is handling too many concerns:
- API client management
- Request parameter building (`build_parameters`)
- Tool formatting (`format_tools`, `format_file_search_tool`, `format_function_tools`)
- Response normalization (already delegated ✓)
- Error handling

### Current vs Proposed Structure

**Current:**
```
app/services/prompt_tracker/
├── openai_response_service.rb          # Does everything
├── llm_response_normalizers/openai/
│   └── responses.rb                     # Response normalization ✓
```

**Proposed:**
```
app/services/prompt_tracker/
├── openai_response_service.rb          # Thin orchestrator only
├── openai/
│   └── responses/
│       ├── request_builder.rb          # build_parameters logic
│       ├── input_builder.rb            # Input array construction (including function_call pairing)
│       ├── tool_formatter.rb           # format_tools, format_file_search_tool, format_function_tools
│       └── function_call_handler.rb    # MOVED from test_runners/helpers/
├── llm_response_normalizers/openai/
│   └── responses.rb                     # Response normalization ✓
```

### Benefits
1. **Single Responsibility** - Each class has one job
2. **Testability** - Request building can be unit tested
3. **Consistency** - Follows existing `openai/assistants/` pattern
4. **Bug visibility** - Input pairing logic would be obvious in `InputBuilder`

---

## 4. Naming: `user_prompt` Parameter

### Problem
The `user_prompt` parameter in `OpenaiResponseService` is misleadingly named. It becomes `input` in the API call, which can be:
- A string (simple user message)
- An array of items (messages, function calls, function outputs, etc.)

### Current Code (confusing):
```ruby
params = {
  model: model,
  input: user_prompt  # user_prompt can be an array of function_call_output items!
}
```

### Proposed
Rename to `input` to match the Responses API parameter name:
```ruby
def initialize(model:, input:, ...)  # was: user_prompt
```

---

## 5. Clarification: tool_calls vs function_calls

### Understanding
Not all `tool_calls` are `function_calls`. In the Responses API:

| Type | Description | Requires Output? |
|------|-------------|------------------|
| `function_call` | Custom functions defined by developer | ✅ YES - must send `function_call_output` |
| `web_search_call` | Built-in web search | ❌ NO - handled by OpenAI |
| `file_search_call` | Built-in file/vector search | ❌ NO - handled by OpenAI |
| `code_interpreter_call` | Built-in code execution | ❌ NO - handled by OpenAI |

### Current Behavior (correct)
The `extract_tool_calls_from_output` in `LlmResponseNormalizers::Openai::Responses` correctly filters to only `function_call` types:
```ruby
def extract_tool_calls_from_output
  output.filter_map do |item|
    next unless item["type"] == "function_call"  # Only functions
    ...
  end
end
```

### No Change Needed
This is already correct - `FunctionCallHandler` only processes actual function calls.

---

## Implementation Plan

### Phase 1: Fix Critical Bug (High Priority)
1. Modify `FunctionCallHandler#call_api_with_function_outputs` to include original function calls
2. Update `FunctionCallHandler#process_with_function_handling` to pass tool_calls to the method
3. Add tests for function call continuation

### Phase 2: Refactor Namespace (Medium Priority)
1. Create `app/services/prompt_tracker/openai/responses/` directory
2. Move `FunctionCallHandler` to new namespace
3. Update all references in `SimulatedConversationRunner`

### Phase 3: Extract Request Building (Medium Priority)
1. Create `Openai::Responses::RequestBuilder` class
2. Create `Openai::Responses::InputBuilder` class
3. Create `Openai::Responses::ToolFormatter` class
4. Refactor `OpenaiResponseService` to use these classes
5. Rename `user_prompt` to `input`

---

## Success Criteria

1. ✅ Function calling tests pass with real OpenAI API
2. ✅ All existing tests continue to pass
3. ✅ `FunctionCallHandler` is properly namespaced
4. ✅ `OpenaiResponseService` is a thin orchestrator
5. ✅ Request building logic is testable in isolation
6. ✅ Parameter naming matches OpenAI API conventions
