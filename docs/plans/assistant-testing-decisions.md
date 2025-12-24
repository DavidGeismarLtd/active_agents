# Assistant Conversation Testing - Key Decisions & Trade-offs (UPDATED)

## 🆕 NEW DECISIONS (Based on User Requirements)

### 0.1. Unified Testable Index

**Decision:** Show all testables (Prompts + Assistants) in a single index view at `/testing`

**Alternatives:**
- A) Separate sections: `/testing/prompts` and `/testing/assistants`
- B) Unified index with filters (CHOSEN)
- C) Tabs within the same page

**Rationale:**
- ✅ **Single source of truth**: Users see all testables in one place
- ✅ **Better UX**: No navigation between sections
- ✅ **Consistent with polymorphic architecture**: Treats all testables equally
- ✅ **Easier comparison**: Compare pass rates across types
- ✅ **Simpler navigation**: One entry point

**Trade-offs:**
- ⚠️ More complex controller logic (query multiple models)
- ⚠️ Potential performance impact (mitigated with pagination)
- ✅ **Worth it**: Better UX > implementation complexity

---

### 0.2. Creation Wizard Modal

**Decision:** Use a modal wizard to guide users through testable creation

**Alternatives:**
- A) Separate "Create Prompt" and "Create Assistant" buttons
- B) Modal wizard with guided flow (CHOSEN)
- C) Dropdown menu

**Rationale:**
- ✅ **Educational**: Explains difference between testable types
- ✅ **Guided experience**: Reduces confusion
- ✅ **Contextual help**: Shows descriptions and examples
- ✅ **Flexible**: Easy to add more testable types
- ✅ **Clean UI**: Doesn't clutter interface

**Trade-offs:**
- ⚠️ Extra click required
- ✅ **Worth it**: Better onboarding > speed for power users

---

### 0.3. Auto-fetch from OpenAI API

**Decision:** Automatically fetch assistant details from OpenAI API on show page load

**Alternatives:**
- A) Manual sync button only
- B) Auto-fetch on show page load (CHOSEN)
- C) Auto-fetch on creation only

**Rationale:**
- ✅ **Always up-to-date**: Latest assistant configuration
- ✅ **Better UX**: No manual action required
- ✅ **Transparent**: See what assistant actually does
- ✅ **Debugging**: Easier to spot configuration issues

**Trade-offs:**
- ⚠️ Slower page load (mitigated with caching)
- ⚠️ API rate limits (mitigated with last_synced_at check)
- ✅ **Worth it**: Accuracy > speed

**Implementation:**
- Cache for 5 minutes
- Show loading state
- Graceful degradation if API fails

---

### 0.4. Per-Message Scoring (NOT Criteria-Based)

**Decision:** Judge scores each assistant message individually (0-100) with reasons

**Alternatives:**
- A) Criteria-based scoring (Empathy: 90, Accuracy: 85, etc.)
- B) Per-message scoring (CHOSEN)
- C) Overall score only

**Rationale:**
- ✅ **Granular feedback**: Know exactly which messages were good/bad
- ✅ **Actionable**: Can improve specific responses
- ✅ **Simpler**: No need to define criteria upfront
- ✅ **Flexible**: Evaluation prompt can cover any aspect
- ✅ **Transparent**: See reasoning for each score

**Trade-offs:**
- ⚠️ More LLM tokens (evaluating each message separately)
- ⚠️ Longer evaluation time
- ✅ **Worth it**: Actionable feedback > speed

**Output format:**
```ruby
{
  overall_score: 88,  # Average of message scores
  message_scores: [
    { message_index: 0, role: "assistant", score: 90, reason: "Good opening" },
    { message_index: 2, role: "assistant", score: 85, reason: "Relevant questions" },
    { message_index: 4, role: "assistant", score: 90, reason: "Appropriate advice" }
  ],
  overall_feedback: "The assistant handled the conversation well..."
}
```

---

### 0.5. Global Configuration (NOT Row-Level)

**Decision:** Configure judge model globally in initializer, not per dataset row

**Alternatives:**
- A) Row-level evaluation config
- B) Test-level evaluation config (CHOSEN)
- C) Global configuration only

**Rationale:**
- ✅ **Simpler**: Less configuration overhead
- ✅ **Consistent**: All tests use same judge model
- ✅ **Easier to change**: Update one place, affects all tests
- ✅ **MVP-appropriate**: Can add row-level config later if needed

**Trade-offs:**
- ⚠️ Less flexibility (can't use different models per scenario)
- ✅ **Worth it**: Simplicity > flexibility for MVP

**Configuration:**
```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  config.conversation_judge_model = "gpt-4"
  config.user_simulator_model = "gpt-3.5-turbo"
end
```

---

### 0.6. Multiple Tests Per Assistant

**Decision:** Each assistant can have multiple tests with different evaluators

**Alternatives:**
- A) Multiple tests per assistant (CHOSEN)
- B) One test per assistant
- C) No tests (manual evaluation only)

**Rationale:**
- ✅ **More flexible**: Test different aspects of assistant behavior
- ✅ **Comprehensive testing**: Quality, tool usage, compliance, latency, etc.
- ✅ **Supports future evaluators**: ToolCallEvaluator, ResponseTimeEvaluator, ComplianceEvaluator
- ✅ **Real-world need**: Complex assistants need multiple evaluation strategies

**Examples:**
- **Test 1**: "Conversation Quality" with ConversationJudgeEvaluator
- **Test 2**: "Tool Usage" with ToolCallEvaluator (checks correct tools called)
- **Test 3**: "Response Time" with ResponseTimeEvaluator (checks latency)
- **Test 4**: "Compliance" with ComplianceEvaluator (checks for policy violations)

**Trade-offs:**
- ⚠️ Slightly more complex UI (need "Create Test" button)
- ✅ **Worth it**: Flexibility needed for real-world assistant testing

**Implementation:**
- `has_many :tests, as: :testable` (no auto-creation)
- UI: "Create New Test" button on assistant show page
- Each test can have different evaluator_configs

---

### 0.7. Model Renames (PromptTest → Test, PromptTestRun → TestRun)

**Decision:** Rename models to reflect polymorphic nature

**Alternatives:**
- A) Keep PromptTest/PromptTestRun names
- B) Rename to Test/TestRun (CHOSEN)
- C) Create new models, deprecate old ones

**Rationale:**
- ✅ **Accurate naming**: Not just for prompts anymore
- ✅ **Cleaner code**: `Test` is shorter and clearer
- ✅ **Future-proof**: Works for any testable type
- ✅ **Consistent**: Matches polymorphic architecture

**Trade-offs:**
- ⚠️ Migration complexity (rename tables, update references)
- ⚠️ Breaking change for existing code
- ✅ **Worth it**: Better naming > migration effort

**Migration strategy:**
- Rename tables in migration
- Update all model references
- Update all view references
- Update all controller references
- Run comprehensive test suite

---

## 🎯 Core Architecture Decision: Polymorphic Testable

### Decision
Use polymorphic association for tests instead of separate test types.

```ruby
# Instead of:
PromptTest belongs_to :prompt_version
AssistantTest belongs_to :assistant

# We use:
Test belongs_to :testable, polymorphic: true
# testable can be: PromptVersion OR Assistant
```

### Rationale
- ✅ **Extensible**: Can add new testable types (Workflow, Agent, RAG Pipeline) without refactoring
- ✅ **Consistent**: Same test infrastructure for all types
- ✅ **DRY**: Reuse test runs, evaluators, datasets
- ✅ **Future-proof**: Scales to any conversational AI system

### Trade-offs
- ⚠️ Migration complexity: Need to backfill existing tests
- ⚠️ Query complexity: Polymorphic queries are slightly more complex
- ✅ Worth it: Long-term flexibility outweighs short-term migration cost

---

## 🤖 User Simulation Decision: LLM-Generated Conversations

### Decision
Use an LLM to simulate user behavior instead of scripted conversation turns.

```ruby
# Instead of:
dataset_row = {
  turn_1: "I have a headache",
  turn_2: "It's been 2 days",
  turn_3: "What should I do?"
}

# We use:
dataset_row = {
  user_prompt: "You are a patient with a severe headache that started 2 days ago..."
}
```

### Rationale
- ✅ **Natural**: Conversations feel human, not robotic
- ✅ **Adaptive**: User simulator responds to assistant's questions
- ✅ **Variety**: Same scenario generates different conversation paths
- ✅ **Easier**: Describe scenario vs. script every turn
- ✅ **Coverage**: Explores edge cases you didn't think of

### Trade-offs
- ⚠️ **Non-deterministic**: Same test produces different results each run
- ⚠️ **Cost**: Uses 2 LLMs per test (simulator + assistant) + judge
- ⚠️ **Complexity**: Harder to debug when tests fail
- ✅ **Worth it**: Realistic testing > predictable testing

### Mitigation Strategies
- Use cheaper model for simulator (gpt-3.5-turbo)
- Run tests multiple times and aggregate results
- Store conversation_data for debugging
- Add max_turns limit to control cost

---

## 📊 Dataset Schema Decision: Flexible JSONB (SIMPLIFIED - Test Data Only)

### Decision
Reuse existing Dataset/DatasetRow models with flexible schema. **Dataset rows contain ONLY test scenario data, NO evaluation config.**

```ruby
# For PromptVersion tests:
row_data = { name: "Alice", issue: "billing" }

# For Assistant tests (ONLY scenario data):
row_data = {
  user_prompt: "You are a patient with a severe headache that started 2 days ago. You're worried it might be serious.",
  max_turns: 10
  # ONLY test scenario - NO evaluation_prompt, NO evaluation_config
}
```

**Evaluation config lives in Test → EvaluatorConfig:**
```ruby
# Each test has its own evaluation strategy
test = assistant.tests.create!(
  name: "Conversation Quality Test",
  evaluator_configs_attributes: [{
    evaluator_type: :conversation_judge,
    config: {
      evaluation_prompt: "Evaluate each assistant message for empathy, accuracy, and professionalism..."
    }
  }]
)
```

### Rationale
- ✅ **Separation of concerns**: Dataset = test scenarios, Test = evaluation strategy
- ✅ **Reusable datasets**: Same dataset can be used by multiple tests with different evaluators
- ✅ **Simpler dataset creation**: Just describe the scenario, don't configure evaluation
- ✅ **Multiple tests per assistant**: Each test has its own EvaluatorConfig
- ✅ **No new tables**: Reuse existing infrastructure
- ✅ **Flexible**: Each testable type defines its own schema
- ✅ **Backward compatible**: Existing datasets still work
- ✅ **Simpler for MVP**: No row-level config complexity

### Trade-offs
- ⚠️ **No schema validation**: Can't enforce structure at DB level
- ⚠️ **Type confusion**: Same table stores different data shapes
- ⚠️ **No row-level customization**: All rows use same evaluation config (MVP limitation)
- ✅ **Worth it**: Flexibility > strict schema

### Why NO row-level evaluation config?
- ✅ **Simpler**: Less configuration overhead
- ✅ **Consistent**: All scenarios evaluated the same way
- ✅ **MVP-appropriate**: Can add later if needed
- ✅ **Easier to understand**: Clear separation between data and evaluation

---

## 🎭 Evaluation Decision: Conversation Judge (LLM)

### Decision
Use LLM to evaluate entire conversation instead of per-message evaluators.

### Rationale
- ✅ **Holistic**: Evaluates conversation flow, not just individual responses
- ✅ **Nuanced**: Can judge empathy, tone, completeness
- ✅ **Flexible**: Custom criteria per test
- ✅ **Realistic**: Mimics how humans evaluate conversations

### Trade-offs
- ⚠️ **Cost**: LLM call per evaluation
- ⚠️ **Latency**: Slower than rule-based evaluators
- ⚠️ **Variability**: LLM judge may be inconsistent
- ✅ **Worth it**: Quality evaluation > fast evaluation

### Mitigation Strategies
- Use lower temperature (0.3) for consistency
- Cache judge responses
- Allow custom judge models (cheaper options)
- Provide clear criteria to reduce variability

---

## 🔄 Thread Management Decision: New Thread Per Test

### Decision (MVP)
Always create new thread for each test run. No thread reuse.

### Rationale
- ✅ **Simple**: No thread lifecycle management
- ✅ **Isolated**: Each test is independent
- ✅ **Predictable**: No state leakage between tests
- ✅ **MVP-friendly**: Defer complexity to post-MVP

### Trade-offs
- ⚠️ **Can't test context retention**: Each conversation starts fresh
- ⚠️ **Higher cost**: Thread creation overhead
- ✅ **Worth it for MVP**: Simplicity > feature completeness

### Post-MVP Enhancement
- Add `thread_id` field to tests
- Add "reuse thread" checkbox
- Store thread_id in test run metadata
- Allow testing multi-session conversations

---

## 🎨 UI Decision: Separate Assistant Section

### Decision
Create dedicated `/testing/assistants` section instead of mixing with prompts.

### Rationale
- ✅ **Clear separation**: Different mental models (prompts vs assistants)
- ✅ **Focused UX**: Purpose-built for conversation testing
- ✅ **Less confusion**: No conditional UI based on testable type
- ✅ **Easier to build**: Separate controllers/views

### Trade-offs
- ⚠️ **More code**: Duplicate some UI patterns
- ⚠️ **Navigation complexity**: Two testing sections
- ✅ **Worth it**: Clarity > code reuse

---

## 🚫 What's NOT in MVP

### 1. Playground Integration
**Why not:** Playground is for prompt drafting (single-turn). Assistants need multi-turn UI.
**Post-MVP:** Build separate "Assistant Playground" with chat interface.

### 2. Tool Call Handling
**Why not:** Adds significant complexity (mock tools, output submission).
**Post-MVP:** Add tool call mocking and automatic output submission.

### 3. Deterministic Conversations
**Why not:** Requires seeding, conversation replay, complex state management.
**Post-MVP:** Add seed parameter to user simulator for regression tests.

### 4. Pre-built Personas
**Why not:** Requires persona library, management UI, categorization.
**Post-MVP:** Build persona library with common user types.

### 5. Real-time Preview
**Why not:** Requires WebSocket/SSE, streaming UI, complex state.
**Post-MVP:** Add live conversation preview in dataset creation.

---

## 📈 Success Metrics

### MVP Success = Can Answer These Questions:
1. ✅ Can I test an OpenAI assistant with realistic conversations?
2. ✅ Can I define user scenarios without scripting every turn?
3. ✅ Can I evaluate conversation quality holistically?
4. ✅ Can I see the full conversation in test results?
5. ✅ Can I run multiple scenarios against one assistant?

### Post-MVP Success = Can Also Answer:
- Can I test multi-session conversations (thread reuse)?
- Can I test assistants with tool calls?
- Can I create deterministic regression tests?
- Can I preview conversations before running tests?
- Can I analyze conversation patterns across tests?

---

## 🎯 MVP Scope Summary

| Feature | MVP | Post-MVP |
|---------|-----|----------|
| Polymorphic tests | ✅ | - |
| LLM user simulator | ✅ | - |
| Conversation judge | ✅ | - |
| New thread per test | ✅ | Thread reuse |
| Basic UI | ✅ | Advanced UI |
| Assistant sync from config | ✅ | Assistant CRUD |
| Error handling | ✅ | - |
| Integration tests | ✅ | - |
| Tool calls | ❌ | ✅ |
| Deterministic mode | ❌ | ✅ |
| Persona library | ❌ | ✅ |
| Real-time preview | ❌ | ✅ |
| Playground integration | ❌ | ✅ |

---

**This MVP gives you 80% of the value with 20% of the complexity.** 🚀
