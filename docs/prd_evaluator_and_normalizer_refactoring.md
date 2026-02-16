# PRD: Evaluator Simplification & LLM Response Normalizers

## Overview

This PRD outlines the refactoring of the evaluator hierarchy and the introduction of well-structured LLM response normalizer classes. The goal is to:

1. **Simplify evaluators**: Remove `BaseNormalizedEvaluator` and move helper methods to a concern
2. **Create testable normalizers**: Introduce `LlmResponseNormalizers` namespace with one normalizer per provider/API
3. **Rename value object**: `NormalizedResponse` → `NormalizedLlmResponse` (since `LlmResponse` model already exists)

**No backward compatibility required** - we will delete/update as needed.

---

## Part 1: Evaluator Simplification

### Current State

```
BaseEvaluator (abstract)
  └─ BaseNormalizedEvaluator (adds data normalization + helper accessors)
       ├─ LengthEvaluator
       ├─ KeywordEvaluator
       ├─ FormatEvaluator
       ├─ ExactMatchEvaluator
       ├─ PatternMatchEvaluator
       ├─ LlmJudgeEvaluator
       ├─ ConversationJudgeEvaluator
       ├─ FileSearchEvaluator
       ├─ WebSearchEvaluator
       ├─ CodeInterpreterEvaluator
       └─ FunctionCallEvaluator
```

**Problems with `BaseNormalizedEvaluator`:**
1. Normalization methods are no longer needed (data comes pre-normalized from runners)
2. Helper accessors (`response_text`, `messages`, `tool_usage`, etc.) are useful but don't justify a separate class
3. Two inheritance levels make the code harder to follow

### Target State

```
BaseEvaluator (includes ConversationDataAccessors)
  ├─ LengthEvaluator
  ├─ KeywordEvaluator
  ├─ FormatEvaluator
  ├─ ExactMatchEvaluator
  ├─ PatternMatchEvaluator
  ├─ LlmJudgeEvaluator
  ├─ ConversationJudgeEvaluator
  ├─ FileSearchEvaluator
  ├─ WebSearchEvaluator
  ├─ CodeInterpreterEvaluator
  └─ FunctionCallEvaluator
```

### Changes Required

#### 1.1 Create `ConversationDataAccessors` concern

**File**: `app/services/prompt_tracker/evaluators/concerns/conversation_data_accessors.rb`

Extract these methods from `BaseNormalizedEvaluator`:
- `messages` - array of all messages
- `last_message` - last message in conversation
- `response_text` - text from last assistant message
- `assistant_messages` - all assistant messages
- `user_messages` - all user messages
- `tool_usage` - aggregated tool usage
- `web_search_results` - web search results
- `code_interpreter_results` - code interpreter results
- `file_search_results` - file search results
- `run_steps` - Assistants API run steps
- `run_steps_available?` - check if run steps exist
- `response_metadata` - response metadata

**NOTE**: Remove all normalization logic (`normalize_input`, `normalize_messages`). Data is already normalized.

#### 1.2 Update `BaseEvaluator`

**File**: `app/services/prompt_tracker/evaluators/base_evaluator.rb`

- Add `include ConversationDataAccessors`
- Add `attr_reader :data` and `alias_method :conversation_data, :data`
- Update `initialize` to accept `(data, config = {})` and store `@data`
- Add `compatible_with_apis` default implementation returning `[:all]`
- Add `compatible_with` default implementation returning `[PromptTracker::PromptVersion]`

#### 1.3 Update all evaluators to inherit from `BaseEvaluator`

**Files to update** (12 evaluators):
- `length_evaluator.rb`
- `keyword_evaluator.rb`
- `format_evaluator.rb`
- `exact_match_evaluator.rb`
- `pattern_match_evaluator.rb`
- `llm_judge_evaluator.rb`
- `conversation_judge_evaluator.rb`
- `file_search_evaluator.rb`
- `web_search_evaluator.rb`
- `code_interpreter_evaluator.rb`
- `function_call_evaluator.rb`

Change: `class XyzEvaluator < BaseNormalizedEvaluator` → `class XyzEvaluator < BaseEvaluator`

#### 1.4 Delete `BaseNormalizedEvaluator`

**File to delete**: `app/services/prompt_tracker/evaluators/base_normalized_evaluator.rb`

---

## Part 2: LLM Response Normalizers

### Current State

Normalization logic is scattered across multiple services:

| Service | Normalization Method | Lines of Code |
|---------|---------------------|---------------|
| `OpenaiResponseService` | `normalize_response` + 10 extract methods | ~150 lines |
| `OpenaiAssistantService` | Inline in `retrieve_response` | ~60 lines |
| `LlmClientService` | `normalize_response` + extract methods | ~40 lines |
| `NormalizedResponse` | `normalize_tool_calls`, `normalize_usage` | ~50 lines |

**Problems:**
1. Services have two responsibilities: API calls + normalization
2. `NormalizedResponse` does normalization (should be pure value object)
3. No clear pattern for adding new providers/APIs
4. Hard to test normalization in isolation

### Target State

```
app/services/prompt_tracker/
├── llm_response_normalizers/
│   ├── base.rb                           # Abstract base with common utilities
│   ├── openai/
│   │   ├── chat_completions.rb           # Normalizes RubyLLM responses
│   │   ├── responses_api.rb              # Normalizes Response API responses
│   │   └── assistants_api.rb             # Normalizes Assistants API responses
│   └── anthropic/
│       └── messages.rb                   # Future: Anthropic Messages API
└── normalized_llm_response.rb            # Pure value object (renamed)
```

### Changes Required

#### 2.1 Create `LlmResponseNormalizers::Base`

**File**: `app/services/prompt_tracker/llm_response_normalizers/base.rb`

```ruby
module PromptTracker
  module LlmResponseNormalizers
    class Base
      # @param raw_response [Object] the raw API response
      # @return [NormalizedLlmResponse]
      def self.normalize(raw_response)
        new(raw_response).normalize
      end

      def initialize(raw_response)
        @raw_response = raw_response
      end

      def normalize
        raise NotImplementedError
      end

      private

      attr_reader :raw_response

      # Common utility methods
      def parse_json_arguments(args)
        return {} if args.nil?
        return args if args.is_a?(Hash)
        JSON.parse(args)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
```

#### 2.2 Create `LlmResponseNormalizers::Openai::Responses`

**File**: `app/services/prompt_tracker/llm_response_normalizers/openai/responses.rb`

Move from `OpenaiResponseService`:
- `extract_text_from_output`
- `extract_tool_calls_from_output`
- `parse_tool_arguments`
- `extract_usage`
- `extract_file_search_results`
- `extract_web_search_results`
- `extract_code_interpreter_results`
- `extract_url_citations`
- `extract_web_search_query`
- `extract_web_search_sources`

#### 2.3 Create `LlmResponseNormalizers::Openai::Assistants`

**File**: `app/services/prompt_tracker/llm_response_normalizers/openai/assistants.rb`

Move from `OpenaiAssistantService`:
- `extract_file_search_results`
- `extract_tool_calls`
- Content extraction from messages

#### 2.4 Create `LlmResponseNormalizers::Openai::ChatCompletions`

**File**: `app/services/prompt_tracker/llm_response_normalizers/openai/chat_completions.rb`

Move from `LlmClientService`:
- `extract_usage`
- `extract_tool_calls`
- Handle RubyLLM message format

#### 2.5 Update services to use normalizers

**OpenaiResponseService**:
```ruby
def normalize_response(response)
  LlmResponseNormalizers::Openai::Responses.normalize(response)
end
```

**OpenaiAssistantService**:
```ruby
def retrieve_response(thread_id, run_id)
  # ... existing code to get messages, run, usage, run_steps ...
  LlmResponseNormalizers::Openai::Assistants.normalize({
    content: content,
    run: run,
    usage: usage,
    run_steps: run_steps
  })
end
```

**LlmClientService**:
```ruby
def normalize_response(response)
  LlmResponseNormalizers::Openai::ChatCompletions.normalize(response)
end
```

---

## Part 3: Rename NormalizedResponse to NormalizedLlmResponse

### Why?

- `LlmResponse` model already exists (ActiveRecord model for production tracking)
- `NormalizedResponse` is confusing when we have an `LlmResponse`
- `NormalizedLlmResponse` clearly indicates this is a normalized version of LLM response data

### Changes Required

#### 3.1 Rename the file and class

**Old**: `app/services/prompt_tracker/normalized_response.rb`
**New**: `app/services/prompt_tracker/normalized_llm_response.rb`

Class: `NormalizedResponse` → `NormalizedLlmResponse`

#### 3.2 Remove normalization methods

The following methods should be REMOVED (normalization now happens in normalizers):
- `normalize_usage`
- `normalize_tool_calls`
- `normalize_arguments`

The class becomes a pure value object with validation only:
```ruby
class NormalizedLlmResponse
  REQUIRED_KEYS = [:text, :usage, :model].freeze

  attr_reader :text, :usage, :model, :tool_calls, :file_search_results,
              :web_search_results, :code_interpreter_results, :api_metadata, :raw_response

  def initialize(text:, usage:, model:, tool_calls: [], ...)
    @text = text || ""
    @usage = usage  # No normalization, expect correct format
    @model = model
    @tool_calls = tool_calls || []  # No normalization
    # ... rest of assignment
    validate!
  end

  def validate!
    raise ArgumentError, "text must be a String" unless @text.is_a?(String)
    raise ArgumentError, "usage must be a Hash" unless @usage.is_a?(Hash)
    raise ArgumentError, "model is required" if @model.nil?
  end

  # Keep convenience methods
  def thread_id; api_metadata[:thread_id]; end
  def run_id; api_metadata[:run_id]; end
  def response_id; api_metadata[:response_id]; end
  # ...
end
```

#### 3.3 Update all references

Search and replace `NormalizedResponse` → `NormalizedLlmResponse` in:
- All 3 services
- All 3 runners
- All normalizers (after creation)
- All specs

---

## Implementation Plan

### Phase 1: Create Normalizers (safe, additive)

| Step | Task | Files |
|------|------|-------|
| 1.1 | Create `LlmResponseNormalizers::Base` | 1 new file |
| 1.2 | Create `LlmResponseNormalizers::Openai::ResponsesApi` | 1 new file |
| 1.3 | Create `LlmResponseNormalizers::Openai::AssistantsApi` | 1 new file |
| 1.4 | Create `LlmResponseNormalizers::Openai::ChatCompletions` | 1 new file |
| 1.5 | Write specs for each normalizer | 3 new spec files |

### Phase 2: Update Services to Use Normalizers

| Step | Task | Files |
|------|------|-------|
| 2.1 | Update `OpenaiResponseService.normalize_response` | 1 file |
| 2.2 | Update `OpenaiAssistantService.retrieve_response` | 1 file |
| 2.3 | Update `LlmClientService.normalize_response` | 1 file |
| 2.4 | Delete extraction methods from services | 3 files |
| 2.5 | Run service specs | - |

### Phase 3: Rename NormalizedResponse

| Step | Task | Files |
|------|------|-------|
| 3.1 | Rename file and class | 1 file |
| 3.2 | Remove normalization methods | 1 file |
| 3.3 | Add validation | 1 file |
| 3.4 | Update all references | ~15 files |
| 3.5 | Run all specs | - |

### Phase 4: Simplify Evaluators

| Step | Task | Files |
|------|------|-------|
| 4.1 | Create `ConversationDataAccessors` concern | 1 new file |
| 4.2 | Update `BaseEvaluator` to include concern | 1 file |
| 4.3 | Update all evaluators to inherit from `BaseEvaluator` | 12 files |
| 4.4 | Delete `BaseNormalizedEvaluator` | 1 file |
| 4.5 | Update specs | ~5 files |
| 4.6 | Run all evaluator specs | - |

---

## Test Plan

### New Specs to Create

1. **`spec/services/prompt_tracker/llm_response_normalizers/openai/responses_api_spec.rb`**
   - Test each extraction method with real API response fixtures
   - Test edge cases (empty output, missing fields)

2. **`spec/services/prompt_tracker/llm_response_normalizers/openai/assistants_api_spec.rb`**
   - Test file search extraction from run_steps
   - Test tool call extraction
   - Test content extraction

3. **`spec/services/prompt_tracker/llm_response_normalizers/openai/chat_completions_spec.rb`**
   - Test RubyLLM message format
   - Test tool call extraction

4. **`spec/services/prompt_tracker/evaluators/concerns/conversation_data_accessors_spec.rb`**
   - Test all accessor methods

### Existing Specs to Update

1. **Service specs** - Update to verify normalizers are called
2. **Evaluator specs** - Update inheritance assertions
3. **Runner specs** - May need updates if they reference `NormalizedResponse`

---

## Files Summary

| Action | Count | Files |
|--------|-------|-------|
| **Create** | 8 | 4 normalizers, 3 normalizer specs, 1 concern |
| **Modify** | ~20 | 3 services, 12 evaluators, 3 runners, 2+ specs |
| **Delete** | 1 | `base_normalized_evaluator.rb` |
| **Rename** | 1 | `normalized_response.rb` → `normalized_llm_response.rb` |

---

## Success Criteria

1. ✅ All existing tests pass
2. ✅ Each normalizer is independently testable
3. ✅ Services have single responsibility (API calls only)
4. ✅ `NormalizedLlmResponse` is a pure value object (no transformation)
5. ✅ Evaluator inheritance is flat (one level)
6. ✅ Adding a new provider/API normalizer is straightforward

---

## Questions / Decisions Made

| Question | Decision |
|----------|----------|
| Keep `NormalizedResponse` or rename? | Rename to `NormalizedLlmResponse` |
| Normalizers as modules or classes? | Classes with `.normalize(raw_response)` class method |
| Where to put normalizers? | `app/services/prompt_tracker/llm_response_normalizers/` |
| Keep backward compatibility? | No - delete/update freely |
