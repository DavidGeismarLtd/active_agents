# Evaluator Refactoring Plan

## Overview
Refactor evaluators to use inheritance-based design with multiple base classes instead of type switching. Follow Ruby duck typing principles - trust clients to pass the right data.

## Problems Being Solved

1. **ConversationJudgeEvaluator creates Evaluation directly** - violates single responsibility
2. **Evaluators accept full objects but only need specific data** - over-coupling
3. **No filtering of evaluators by testable type** - all evaluators show for all tests
4. **Inconsistent initialization patterns** - some accept `llm_response`, some `test_run`

## Design Principles

1. **Duck typing** - No type checking, trust clients to pass correct data
2. **Inheritance over conditionals** - Use base classes instead of `case` statements
3. **Single responsibility** - Only `BaseEvaluator#evaluate` creates `Evaluation` records
4. **Minimal coupling** - Evaluators only receive the data they actually use
5. **Config for extras** - Pass additional context (like `rendered_prompt`) via config hash

## New Hierarchy

```
BaseEvaluator (abstract)
  ├─ BasePromptVersionEvaluator (accepts response_text: String)
  │    ├─ LengthEvaluator
  │    ├─ KeywordEvaluator
  │    ├─ FormatEvaluator
  │    ├─ ExactMatchEvaluator
  │    ├─ PatternMatchEvaluator
  │    └─ LlmJudgeEvaluator (gets rendered_prompt via config)
  │
  └─ BaseOpenAiAssistantEvaluator (accepts conversation_data: Hash)
       └─ ConversationJudgeEvaluator
```

## Implementation Steps

### Phase 1: Create Base Classes (New Files)

1. **Update `BaseEvaluator`** (`app/services/prompt_tracker/evaluators/base_evaluator.rb`)
   - Remove `@llm_response` instance variable
   - Keep only `@config`
   - `#evaluate` method creates `Evaluation` records (single responsibility)
   - Add `self.compatible_with` class method (returns array of compatible classes)
   - Add `self.compatible_with?(testable)` class method

2. **Create `BasePromptVersionEvaluator`** (`app/services/prompt_tracker/evaluators/base_prompt_version_evaluator.rb`)
   - Inherits from `BaseEvaluator`
   - Accepts `response_text` (String) in `initialize`
   - Stores `@response_text`
   - `self.compatible_with` returns `[PromptTracker::PromptVersion]`

3. **Create `BaseOpenAiAssistantEvaluator`** (`app/services/prompt_tracker/evaluators/base_openai_assistant_evaluator.rb`)
   - Inherits from `BaseEvaluator`
   - Accepts `conversation_data` (Hash) in `initialize`
   - Stores `@conversation_data`
   - `self.compatible_with` returns `[PromptTracker::Openai::Assistant]`

### Phase 2: Update Existing Evaluators

4. **Update PromptVersion Evaluators** (6 files)
   - Change parent class to `BasePromptVersionEvaluator`
   - Change `initialize(llm_response, config)` to `initialize(response_text, config)`
   - Replace `llm_response.response_text` with `response_text`
   - Remove `#evaluate` method (inherited from `BaseEvaluator`)
   - Keep `#evaluate_score`, `#generate_feedback`, `#metadata`, `#passed?`

   Files:
   - `app/services/prompt_tracker/evaluators/length_evaluator.rb`
   - `app/services/prompt_tracker/evaluators/keyword_evaluator.rb`
   - `app/services/prompt_tracker/evaluators/format_evaluator.rb`
   - `app/services/prompt_tracker/evaluators/exact_match_evaluator.rb`
   - `app/services/prompt_tracker/evaluators/pattern_match_evaluator.rb`
   - `app/services/prompt_tracker/evaluators/llm_judge_evaluator.rb`

5. **Update ConversationJudgeEvaluator**
   - Change parent class to `BaseOpenAiAssistantEvaluator`
   - Change `initialize(test_run, config)` to `initialize(conversation_data, config)`
   - Replace `@test_run.conversation_data` with `@conversation_data`
   - **Remove `#evaluate` method** (use inherited version)
   - Keep `#evaluate_score`, `#generate_feedback`, `#metadata`, `#passed?`

### Phase 3: Update Registry

6. **Update `EvaluatorRegistry`** (`app/services/prompt_tracker/evaluator_registry.rb`)
   - Add `self.for_testable(testable)` method - filters evaluators by compatibility
   - Update `self.build(key, context, config)` signature (keep it simple)
   - **NO type checking** - trust clients to pass correct data
   - Clients are responsible for:
     - Extracting `response_text` from `llm_response` or `test_run`
     - Extracting `conversation_data` from `test_run`
     - Passing `rendered_prompt` in config for `LlmJudgeEvaluator`

### Phase 4: Update Callers

7. **Update Test Runners** (2 files)
   - `app/services/prompt_tracker/test_runners/prompt_version_runner.rb`
     - Extract `response_text` from `test_run.llm_response.response_text`
     - Pass `llm_response: test_run.llm_response, test_run: test_run` in config

   - `app/services/prompt_tracker/test_runners/openai/assistant_runner.rb`
     - Extract `conversation_data` from `test_run.conversation_data`
     - Pass `test_run: test_run` in config

8. **Update Jobs** (3 files)
   - `app/jobs/prompt_tracker/run_evaluators_job.rb`
   - `app/jobs/prompt_tracker/llm_judge_evaluation_job.rb`
   - `app/jobs/prompt_tracker/evaluation_job.rb`
   - Update to extract appropriate data before calling `EvaluatorRegistry.build`

9. **Update AutoEvaluationService**
   - `app/services/prompt_tracker/auto_evaluation_service.rb`
   - Extract `response_text` from `llm_response`
   - Pass `llm_response` in config

### Phase 5: Update Views

10. **Update Test Form** (`app/views/prompt_tracker/testing/tests/_form.html.erb`)
    - Change `PromptTracker::EvaluatorRegistry.all` to `PromptTracker::EvaluatorRegistry.for_testable(testable)`
    - Get `testable` from `test.testable` or context

### Phase 6: Update Tests

11. **Update Evaluator Specs** (7+ files)
    - Update all `new(llm_response, config)` calls to `new(response_text, config)`
    - Update `ConversationJudgeEvaluator` specs to use `conversation_data` hash
    - Update expectations for `#evaluate` method

12. **Update Registry Specs**
    - Add tests for `for_testable` filtering
    - Update `build` tests to pass correct data types

13. **Update Integration Specs**
    - Update test runner specs
    - Update job specs

## Files to Create

- `app/services/prompt_tracker/evaluators/base_prompt_version_evaluator.rb` (NEW)
- `app/services/prompt_tracker/evaluators/base_openai_assistant_evaluator.rb` (NEW)

## Files to Modify

### Core (3 files)
- `app/services/prompt_tracker/evaluators/base_evaluator.rb`
- `app/services/prompt_tracker/evaluator_registry.rb`
- `app/models/prompt_tracker/evaluator_config.rb`

### Evaluators (7 files)
- `app/services/prompt_tracker/evaluators/length_evaluator.rb`
- `app/services/prompt_tracker/evaluators/keyword_evaluator.rb`
- `app/services/prompt_tracker/evaluators/format_evaluator.rb`
- `app/services/prompt_tracker/evaluators/exact_match_evaluator.rb`
- `app/services/prompt_tracker/evaluators/pattern_match_evaluator.rb`
- `app/services/prompt_tracker/evaluators/llm_judge_evaluator.rb`
- `app/services/prompt_tracker/evaluators/conversation_judge_evaluator.rb`

### Services & Jobs (5 files)
- `app/services/prompt_tracker/test_runners/prompt_version_runner.rb`
- `app/services/prompt_tracker/test_runners/openai/assistant_runner.rb`
- `app/services/prompt_tracker/auto_evaluation_service.rb`
- `app/jobs/prompt_tracker/run_evaluators_job.rb`
- `app/jobs/prompt_tracker/evaluation_job.rb`

### Views (1 file)
- `app/views/prompt_tracker/testing/tests/_form.html.erb`

### Specs (10+ files)
- All evaluator specs
- Registry spec
- Test runner specs
- Job specs

## Duck Typing Examples

### Good (Duck Typing)
```ruby
# Registry just passes data through
def self.build(key, input, config = {})
  evaluator_class = get(key)[:evaluator_class]
  evaluator_class.new(input, config)
end

# Caller extracts the right data
response_text = test_run.llm_response.response_text
config = { llm_response: test_run.llm_response, test_run: test_run }
evaluator = EvaluatorRegistry.build(:length, response_text, config)
```

### Bad (Type Checking - AVOID)
```ruby
# DON'T DO THIS
def self.build(key, context, config = {})
  if context.is_a?(String)
    input = context
  elsif context.respond_to?(:response_text)
    input = context.response_text
  end
  # ... more type checking
end
```

## Success Criteria

- [ ] All evaluators inherit from appropriate base class
- [ ] Only `BaseEvaluator#evaluate` creates `Evaluation` records
- [ ] No type checking in `EvaluatorRegistry`
- [ ] Evaluators only receive data they actually use
- [ ] Test form filters evaluators by testable type
- [ ] All tests pass
- [ ] No breaking changes to public API (where possible)

## Migration Notes

This is a **breaking change** for:
- Direct instantiation of evaluators (signature changes)
- Custom evaluators (must inherit from new base classes)

This is **NOT breaking** for:
- Using `EvaluatorRegistry.build` (callers just need to pass different data)
- Evaluation results (same schema)
- UI (improved - shows only relevant evaluators)
