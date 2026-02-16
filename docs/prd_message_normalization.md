# PRD: Message Format Normalization

## Executive Summary

This document outlines a plan to simplify and unify message format handling across PromptTracker. Currently, normalization logic is scattered across multiple layers (services, runners, evaluators) with no single source of truth. This creates maintenance burden and inconsistencies.

**Goal**: Normalize messages at the **service level** once, so that downstream consumers (runners, evaluators) receive consistent data without needing to re-normalize.

---

## Current State Analysis

### 1. Where Normalization Currently Happens

| Layer | Location | What It Does | Problem |
|-------|----------|--------------|---------|
| **Evaluator** | `evaluators/normalizers/*.rb` (5 files) | Transform API responses for evaluators | Wrong location - evaluators shouldn't normalize |
| **Evaluator** | `BaseNormalizedEvaluator#normalize_input` | Defensive re-normalization | Compensates for inconsistent upstream data |
| **Evaluator** | `EvaluatorRegistry#normalizer_for` | Returns normalizer by API type | Implies evaluators are responsible for normalization |
| **Service** | `OpenaiResponseService` | Partial normalization (lines 294-314) | Good, but format differs from other services |
| **Service** | `OpenaiAssistantService` | Partial normalization (lines 194-213) | Missing fields, format differs from ResponseService |
| **Service** | `LlmClientService` | Minimal normalization (lines 224-230) | Only returns text, usage, model, raw |
| **Runner** | Each `simulated_conversation_runner.rb` | Builds messages with different fields | **Each runner stores different message fields** |

### 2. Message Format Inconsistency in Runners

Each runner builds assistant messages with different fields:

**Chat Completions Runner** (lines 96-101):
```ruby
{
  "role" => "assistant",
  "content" => response[:text],
  "turn" => turn,
  "usage" => response[:usage]
}
```

**Responses API Runner** (lines 113-120):
```ruby
{
  "role" => "assistant",
  "content" => response[:text],
  "turn" => turn,
  "response_id" => response[:response_id],
  "usage" => aggregated_usage,
  "tool_calls" => all_tool_calls
}
```

**Assistants API Runner** (lines 100-109):
```ruby
{
  "role" => "assistant",
  "content" => response[:text],
  "turn" => turn,
  "usage" => response[:usage],
  "thread_id" => response[:thread_id],
  "run_id" => response[:run_id],
  "annotations" => response[:annotations],
  "file_search_results" => response[:file_search_results]
}
```

### 3. What Evaluators Expect

`BaseNormalizedEvaluator` (lines 15-27) expects this format:

```ruby
{
  messages: [
    { role: "user", content: "...", tool_calls: [...], turn: 1 },
    { role: "assistant", content: "...", tool_calls: [...], turn: 2 }
  ],
  tool_usage: [...],
  web_search_results: [...],
  code_interpreter_results: [...],
  file_search_results: [...],
  run_steps: [...],
  metadata: { model: "...", ... }
}
```

### 4. Problems

1. **No single source of truth** - Each normalizer implements its own format interpretation
2. **Wrong location** - Normalizers in `evaluators/` folder implies evaluators should normalize
3. **Defensive programming** - `BaseNormalizedEvaluator#normalize_input` tries to fix inconsistencies
4. **Data loss** - Different runners store different fields, evaluators only extract subset
5. **Symbol/String key chaos** - Code handles both `msg[:role]` and `msg["role"]` everywhere
6. **Maintenance burden** - Changes require updates in multiple places

---

## Proposed Architecture

### Core Principle

**Normalization happens ONCE at the service level.** Everything downstream uses the same format.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           LLM SERVICES                                   │
│  OpenaiAssistantService | OpenaiResponseService | LlmClientService      │
│                                                                          │
│  Each returns NORMALIZED response:                                       │
│  {                                                                       │
│    text: String,                                                         │
│    usage: { prompt_tokens:, completion_tokens:, total_tokens: },        │
│    model: String,                                                        │
│    tool_calls: [...],        # Unified format                           │
│    file_search_results: [...],                                          │
│    web_search_results: [...],                                           │
│    code_interpreter_results: [...],                                     │
│    api_metadata: { ... },    # API-specific data (thread_id, etc.)     │
│    raw: { ... }                                                         │
│  }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    SIMULATED CONVERSATION RUNNERS                        │
│  All runners build messages using IDENTICAL structure:                   │
│  {                                                                       │
│    "role" => "assistant",                                                │
│    "content" => response[:text],                                         │
│    "turn" => turn,                                                       │
│    "usage" => response[:usage],                                          │
│    "tool_calls" => response[:tool_calls],                               │
│    "api_metadata" => response[:api_metadata]                            │
│  }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           build_output_data()                            │
│  Builds test_run.output_data with:                                       │
│  {                                                                       │
│    "messages" => [...],      # Consistent message format                │
│    "file_search_results" => [...],  # Aggregated from all turns        │
│    "web_search_results" => [...],                                       │
│    "code_interpreter_results" => [...],                                 │
│    "tool_usage" => [...],    # Aggregated tool calls                   │
│    "metadata" => { model:, provider:, ... }                             │
│  }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              EVALUATORS                                  │
│  Receive already-normalized data from test_run.output_data              │
│  NO normalization needed - just use the data                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Unified Response Contract

### Service Response Format (Single Call)

All LLM services MUST return this exact format:

```ruby
{
  # Core fields (REQUIRED)
  text: String,                    # The text response content
  usage: {                         # Token usage
    prompt_tokens: Integer,
    completion_tokens: Integer,
    total_tokens: Integer
  },
  model: String,                   # Model name used

  # Tool results (OPTIONAL - empty array if not applicable)
  tool_calls: [                    # Unified tool call format
    {
      id: String,                  # Call ID
      type: String,                # "function" | "file_search" | "web_search" | "code_interpreter"
      function_name: String,       # Function name (for type="function")
      arguments: Hash              # Parsed arguments
    }
  ],
  file_search_results: [...],      # File search results (if any)
  web_search_results: [...],       # Web search results (if any)
  code_interpreter_results: [...], # Code interpreter results (if any)

  # API-specific metadata (REQUIRED - can be empty hash)
  api_metadata: {
    # Assistants API
    thread_id: String?,
    run_id: String?,
    annotations: Array?,
    run_steps: Array?,

    # Responses API
    response_id: String?,

    # All APIs can include
    finish_reason: String?
  },

  # Raw response (REQUIRED)
  raw: Object                      # Original API response for debugging
}
```

### Message Format in Runners

All runners build messages using this IDENTICAL structure:

```ruby
{
  "role" => "assistant" | "user",
  "content" => String,             # Message text
  "turn" => Integer,               # Turn number (1-based)
  "usage" => Hash,                 # Token usage for this message
  "tool_calls" => Array,           # Tool calls (empty array if none)
  "api_metadata" => Hash           # API-specific data (empty hash if none)
}
```

### Test Run output_data Format

The `test_run.output_data` contains:

```ruby
{
  # Core fields
  "rendered_prompt" => String,     # The system prompt used
  "model" => String,
  "provider" => String,
  "status" => "completed" | "error",
  "total_turns" => Integer,

  # Messages array
  "messages" => [
    {
      "role" => String,
      "content" => String,
      "turn" => Integer,
      "usage" => Hash,
      "tool_calls" => Array,
      "api_metadata" => Hash
    }
  ],

  # Aggregated tool results (from all turns)
  "tool_usage" => Array,           # All tool calls across conversation
  "file_search_results" => Array,  # All file search results
  "web_search_results" => Array,   # All web search results
  "code_interpreter_results" => Array,

  # Metadata
  "metadata" => {
    "api_type" => String,          # "openai_chat_completions", "openai_responses", etc.
    "run_steps" => Array?          # Assistants API only
  }
}
```


---

## Implementation Plan

### Phase 1: Create Single Source of Truth

**Create `app/services/prompt_tracker/normalized_response.rb`**

A value object that enforces the response contract:

```ruby
module PromptTracker
  class NormalizedResponse
    REQUIRED_KEYS = [:text, :usage, :model].freeze

    def initialize(attrs)
      validate_required_keys!(attrs)
      @data = normalize(attrs)
    end

    def to_h
      @data
    end

    # Accessor methods
    def text; @data[:text]; end
    def usage; @data[:usage]; end
    # ... etc
  end
end
```

### Phase 2: Update Services to Return Normalized Responses

**Files to modify:**

1. **`app/services/prompt_tracker/openai_assistant_service.rb`**
   - Line ~200: Update `build_response` to return normalized format
   - Add missing: `tool_calls`, `web_search_results`, `code_interpreter_results`
   - Move `thread_id`, `run_id`, `annotations` to `api_metadata`

2. **`app/services/prompt_tracker/openai_response_service.rb`**
   - Line ~294: Update response format
   - Move `response_id` to `api_metadata`
   - Already has good normalization, just restructure

3. **`app/services/prompt_tracker/llm_client_service.rb`**
   - Line ~224: Update `normalize_response`
   - Add empty arrays for tool fields
   - Add `api_metadata: {}` and `tool_calls: []`

### Phase 3: Update Runners to Use Consistent Message Format

**Files to modify:**

1. **`app/services/prompt_tracker/test_runners/openai/chat_completions/simulated_conversation_runner.rb`**
   - Line ~96: Update message building to include all standard fields

2. **`app/services/prompt_tracker/test_runners/openai/responses/simulated_conversation_runner.rb`**
   - Line ~113: Restructure to use `api_metadata` instead of top-level `response_id`

3. **`app/services/prompt_tracker/test_runners/openai/assistants/simulated_conversation_runner.rb`**
   - Line ~100: Restructure to use `api_metadata` instead of top-level `thread_id`, `run_id`, etc.

### Phase 4: Update Base Runner to Build Complete output_data

**File to modify: `app/services/prompt_tracker/test_runners/simulated_conversation_runner.rb`**

Update `build_output_data` to:
- Accept and aggregate tool results from all turns
- Include all required fields in output_data
- Add `tool_usage`, `file_search_results`, `web_search_results`, `code_interpreter_results`

### Phase 5: Simplify Evaluators

**Files to modify:**

1. **`app/services/prompt_tracker/evaluators/base_normalized_evaluator.rb`**
   - Remove `normalize_input` method (or make it a no-op)
   - Data should already be normalized from `test_run.output_data`
   - Keep accessor methods like `messages`, `tool_usage`, etc.

2. **`app/services/prompt_tracker/evaluator_registry.rb`**
   - Remove `normalizer_for` method
   - Remove association between evaluators and normalizers

### Phase 6: Delete or Move Normalizers

**Files to delete or archive:**

```
app/services/prompt_tracker/evaluators/normalizers/
├── base_normalizer.rb           # DELETE
├── assistants_api_normalizer.rb # DELETE
├── chat_completion_normalizer.rb # DELETE
├── response_api_normalizer.rb   # MOVE extraction helpers to services
└── anthropic_normalizer.rb      # DELETE
```

Some helper methods (like `extract_file_search_results`) can be moved to the respective services.

---

## Migration Strategy

### Order of Changes (to avoid breaking tests)

1. **Create `NormalizedResponse` value object** (no impact yet)

2. **Update services one at a time**, keeping backward compatibility:
   - Add new normalized fields alongside old ones initially
   - Update tests for each service

3. **Update runners one at a time**:
   - Update message format
   - Update `build_output_data` calls
   - Update tests

4. **Update evaluators**:
   - Simplify `BaseNormalizedEvaluator`
   - Update evaluator tests

5. **Delete normalizers** after all tests pass

### Test Strategy

- Run full test suite after each phase
- Focus on:
  - `spec/services/prompt_tracker/openai_assistant_service_spec.rb`
  - `spec/services/prompt_tracker/openai_response_service_spec.rb`
  - `spec/services/prompt_tracker/llm_client_service_spec.rb`
  - `spec/services/prompt_tracker/test_runners/` (all runner specs)
  - `spec/services/prompt_tracker/evaluators/` (all evaluator specs)

---

## Files Affected Summary

### Create (1 file)
- `app/services/prompt_tracker/normalized_response.rb`

### Modify (10 files)
- `app/services/prompt_tracker/openai_assistant_service.rb`
- `app/services/prompt_tracker/openai_response_service.rb`
- `app/services/prompt_tracker/llm_client_service.rb`
- `app/services/prompt_tracker/test_runners/simulated_conversation_runner.rb`
- `app/services/prompt_tracker/test_runners/openai/chat_completions/simulated_conversation_runner.rb`
- `app/services/prompt_tracker/test_runners/openai/responses/simulated_conversation_runner.rb`
- `app/services/prompt_tracker/test_runners/openai/assistants/simulated_conversation_runner.rb`
- `app/services/prompt_tracker/evaluators/base_normalized_evaluator.rb`
- `app/services/prompt_tracker/evaluator_registry.rb`
- Multiple test files

### Delete (5 files)
- `app/services/prompt_tracker/evaluators/normalizers/base_normalizer.rb`
- `app/services/prompt_tracker/evaluators/normalizers/assistants_api_normalizer.rb`
- `app/services/prompt_tracker/evaluators/normalizers/chat_completion_normalizer.rb`
- `app/services/prompt_tracker/evaluators/normalizers/response_api_normalizer.rb`
- `app/services/prompt_tracker/evaluators/normalizers/anthropic_normalizer.rb`

---

## Open Questions

1. **Should `api_metadata` use symbol or string keys internally?**
   - Recommendation: Use symbol keys internally (Ruby idiom), stringify only when serializing to JSON

2. **Should we keep `raw` response in production or only in development?**
   - Recommendation: Keep for debugging but consider size implications

3. **How to handle backward compatibility with existing test_run records?**
   - Option A: Migration to update existing records
   - Option B: Handle both formats in evaluators temporarily (not preferred)
   - Recommendation: Option A - migrate data

---

## Success Criteria

- [ ] All services return identical response structure
- [ ] All runners build messages with identical structure
- [ ] `test_run.output_data` has consistent format regardless of API type
- [ ] Evaluators receive pre-normalized data (no `normalize_input` needed)
- [ ] No more `msg[:key] || msg["key"]` defensive patterns
- [ ] Single source of truth for format definition
- [ ] All tests pass
- [ ] Normalizers deleted from evaluators folder
