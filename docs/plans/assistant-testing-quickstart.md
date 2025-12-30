# Assistant Conversation Testing - Quick Start Guide

## 🚀 TL;DR

This feature lets you test OpenAI Assistants with **realistic, LLM-simulated conversations** instead of scripted test cases.

**Key Innovation:** An LLM plays the role of the user, generating natural conversation turns based on a scenario description. Each assistant message is scored individually by an LLM judge.

**Example:**
```ruby
# Instead of scripting:
turn_1: "I have a headache"
turn_2: "It's been 2 days"
turn_3: "What should I do?"

# You describe the scenario:
user_prompt: "You are a patient with a severe headache that started 2 days ago..."

# The simulator LLM generates natural conversation turns
# The assistant responds naturally
# A judge LLM scores EACH assistant message individually
# Overall score = average of all message scores
```

## 🎯 Key Architectural Decisions

1. **Unified Testable Index**: All testables (Prompts + Assistants) shown in one view
2. **Creation Wizard**: Modal to select testable type, then guided flow
3. **Multiple Tests Per Assistant**: Each assistant can have multiple tests with different evaluators (ConversationJudgeEvaluator, ToolCallEvaluator, etc.)
4. **Per-Message Scoring**: Judge scores each assistant message (0-100) + reason
5. **Separation of Test Data and Evaluation**: Dataset rows contain ONLY test scenarios (`user_prompt`, `max_turns`). Evaluation config lives in Test → EvaluatorConfig. This allows reusing datasets across multiple tests.
6. **Global Configuration**: Judge model configured in initializer
7. **Auto-sync from OpenAI**: Assistant details fetched automatically on show page

---

## 📖 Reading Order

### 1️⃣ First Time? Start Here

**[Architecture Diagrams](./assistant-testing-architecture.md)** (5 min read)
- Visual overview of how everything fits together
- See the conversation flow
- Understand the data model

### 2️⃣ Understand the Approach

**[Key Decisions](./assistant-testing-decisions.md)** (10 min read)
- Why polymorphic testable?
- Why LLM-simulated conversations?
- What trade-offs were made?
- What's NOT in MVP?

### 3️⃣ See It In Action

**[Usage Examples](./assistant-testing-examples.md)** (15 min read)
- Real code examples
- Common use cases
- How to create tests
- How to interpret results

### 4️⃣ Ready to Build?

**[MVP Plan](./assistant-conversation-testing-mvp.md)** (30 min read)
- Complete technical specification
- Database schema
- Service implementations
- Phase-by-phase breakdown

**[Implementation Checklist](./assistant-testing-checklist.md)** (Reference)
- Detailed task list
- Track your progress
- Ensure nothing is missed

---

## 🎯 Core Concepts

### 1. Unified Testable Index

All testables (PromptVersions and Assistants) are shown in a single index view:

```
/testing (root path)
  ├─ PromptVersion: "Customer Support Greeting" (3 tests)
  ├─ PromptVersion: "Email Generator" (2 tests)
  ├─ Assistant: "Dr Alain Firmier" (1 test)
  └─ Assistant: "Coach Rocky Bal-Yoga" (1 test)
```

**Creation Wizard:**
1. Click "Create New Testable"
2. Modal shows: "Prompt" or "Assistant"
3. If Prompt → Redirect to `/testing/playground`
4. If Assistant → Select assistant → Redirect to `/testing/assistants/:id`

### 2. Polymorphic Test Model

Tests belong to **either** a PromptVersion **or** an Assistant:

```ruby
# Prompt test (existing)
test = Test.create!(testable: prompt_version)

# Assistant test (new)
test = Test.create!(testable: assistant)
```

**For Assistants (MVP):**
- One test per assistant
- One evaluator config per test (ConversationJudgeEvaluator only)
- Multiple datasets per assistant (different scenarios)

### 3. User Simulator

An LLM that plays the user role:

```ruby
simulator = UserSimulatorService.new(
  persona_prompt: "You are a patient with a headache...",
  max_turns: 10
)

message = simulator.generate_message(conversation_history: [...])
# => "Hi doctor, I have a really bad headache"
```

**Model:** Fixed to `gpt-3.5-turbo` (configured globally)

### 4. Conversation Loop

```
1. Simulator generates user message
2. Send to assistant via OpenAI Assistants API
3. Assistant responds
4. Add both to conversation history
5. Repeat until:
   - Simulator returns "CONVERSATION_COMPLETE"
   - max_turns reached
   - Error occurs
```

### 5. Per-Message Conversation Judge

An LLM that scores **each assistant message individually**:

```ruby
judge = ConversationJudgeEvaluator.new(
  conversation: [...],
  test_run: test_run,
  config: {
    evaluation_prompt: "Evaluate each assistant message for quality...",
    judge_model: nil  # Uses global config
  }
)

result = judge.evaluate
# => {
#   overall_score: 88,  # Average of message scores
#   message_scores: [
#     { message_index: 0, role: "assistant", score: 90, reason: "Good opening" },
#     { message_index: 2, role: "assistant", score: 85, reason: "Relevant questions" },
#     { message_index: 4, role: "assistant", score: 90, reason: "Appropriate advice" }
#   ],
#   overall_feedback: "The assistant handled the conversation well..."
# }
```

**Key Points:**
- ❌ NO criteria scores (removed for simplicity)
- ✅ Score each assistant message (0-100)
- ✅ Overall score = average of message scores
- ✅ Judge model configured globally in initializer

---

## 🏗️ Architecture at a Glance

```
Unified Testable Index (/testing)
    ↓
Click "Create New Testable"
    ↓
Modal: Choose "Prompt" or "Assistant"
    ↓
If Assistant → Select Assistant → Assistant Show Page
    ↓
Auto-fetch from OpenAI API (instructions, model, tools)
    ↓
Create Dataset with Scenarios
    ↓
Add DatasetRow (user_prompt + max_turns)
    ↓
Run Test
    ↓
UserSimulator generates message
    ↓
Send to Assistant (via OpenAI Assistants API)
    ↓
Assistant responds
    ↓
Add to conversation history
    ↓
Repeat until done or max_turns
    ↓
ConversationJudge scores EACH assistant message
    ↓
Calculate overall score (average)
    ↓
Create TestRun with conversation_data + message_scores
```

---

## 📊 What Gets Created

### Models
- `Assistant` - Represents OpenAI assistants (synced from config + OpenAI API)
- `Test` - Renamed from PromptTest, polymorphic testable
- `TestRun` - Renamed from PromptTestRun, with conversation_data field
- `Dataset` - Updated to polymorphic testable
- `EvaluatorConfig` - ConversationJudgeEvaluator config per test

### Services
- `UserSimulatorService` - Generates user messages (uses gpt-3.5-turbo)
- `AssistantTestRunner` - Orchestrates conversation execution
- `ConversationJudgeEvaluator` - Scores each assistant message individually

### UI
- `/testing` - **Unified testable index** (Prompts + Assistants)
- **Creation wizard modal** - Select testable type
- `/testing/assistants/:id` - Assistant show page with OpenAI data
- **Test results** - Conversation as chat bubbles with inline message scores

---

## ⏱️ Timeline

| Phase | Hours | What You'll Build |
|-------|-------|-------------------|
| 1. Core Models | 2-3 | Assistant model, migrations, polymorphic tests |
| 2. User Simulator | 2-3 | LLM that generates user messages |
| 3. Test Runner | 3-4 | Conversation orchestration |
| 4. Judge Evaluator | 2-3 | LLM-based evaluation |
| 5. Test Interface | 3-4 | Polymorphic test support |
| 6. UI | 4-5 | Assistant list, test creation, results |
| 7. Testing | 2-3 | Integration tests, edge cases |
| **TOTAL** | **18-25 hours** | **~3-4 days** |

---

## ✅ MVP Success Criteria

You're done when you can:

1. ✅ View unified testable index (Prompts + Assistants together)
2. ✅ Use creation wizard to select testable type
3. ✅ Sync assistants from config
4. ✅ Auto-fetch assistant details from OpenAI API
5. ✅ Create a test for an assistant (auto-created with ConversationJudgeEvaluator)
6. ✅ Add dataset rows with user_prompt + max_turns
7. ✅ Run the test and see natural conversation
8. ✅ View conversation with per-message scores inline
9. ✅ See overall score (average of message scores)
10. ✅ Configure judge model globally in initializer

---

## 🚫 What's NOT in MVP

- ❌ Thread reuse (always new thread per test run)
- ❌ Tool call handling (raise error if assistant uses tools)
- ❌ Deterministic conversations (always stochastic)
- ❌ Pre-built personas (manual per row)
- ❌ Real-time preview (run then view)
- ❌ Playground integration (separate feature)
- ❌ Row-level evaluation config (global config only)
- ❌ Criteria scores (per-message scores only)
- ❌ Multiple tests per assistant (one test per assistant for MVP)

These can be added post-MVP if needed.

---

## 🎓 Key Learnings

### Why LLM Simulation?

**Traditional approach (scripted):**
```ruby
turn_1: "I have a headache"
turn_2: "It's been 2 days"
turn_3: "What should I do?"
```
❌ Robotic, doesn't adapt to assistant responses

**LLM simulation approach:**
```ruby
user_prompt: "You are a patient with a headache..."
```
✅ Natural, adaptive, explores edge cases

### Why Polymorphic?

**Separate models:**
```ruby
PromptTest belongs_to :prompt_version
AssistantTest belongs_to :assistant
```
❌ Duplicate code, hard to extend

**Polymorphic:**
```ruby
Test belongs_to :testable  # PromptVersion OR Assistant
```
✅ Reusable, extensible, DRY

---

## 📚 Next Steps

1. **Read the architecture diagrams** to visualize the system
2. **Review key decisions** to understand trade-offs
3. **Check out examples** to see it in action
4. **Read the MVP plan** for full technical details
5. **Follow the checklist** to implement

---

## 💡 Pro Tips

1. **Start with Phase 1** - Get the models right first
2. **Test incrementally** - Don't wait until the end
3. **Use real assistants** - Test with actual OpenAI assistants early
4. **Keep it simple** - Resist feature creep, stick to MVP
5. **Document as you go** - Future you will thank you

---

## 🆘 Need Help?

- **Confused about architecture?** → Read [Architecture Diagrams](./assistant-testing-architecture.md)
- **Don't understand a decision?** → Read [Key Decisions](./assistant-testing-decisions.md)
- **Want to see code?** → Read [Usage Examples](./assistant-testing-examples.md)
- **Ready to implement?** → Read [MVP Plan](./assistant-conversation-testing-mvp.md)
- **Need a task list?** → Read [Implementation Checklist](./assistant-testing-checklist.md)

---

**Ready to build something awesome? Let's go! 🚀**
