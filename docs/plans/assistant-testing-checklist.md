# Assistant Conversation Testing - Implementation Checklist

## Phase 1: Core Models ⏱️ 2-3 hours

### Database Migrations
- [ ] Create `assistants` table migration
  - [ ] Fields: assistant_id, name, provider, description, category, metadata
  - [ ] Indexes: assistant_id (unique), provider, category
- [ ] Add polymorphic `testable` to `prompt_tests`
  - [ ] Add testable_type, testable_id columns
  - [ ] Backfill existing tests (testable = prompt_version)
  - [ ] Add indexes
- [ ] Add `conversation_data` to `prompt_test_runs`
  - [ ] JSONB column with default []
  - [ ] GIN index for querying
- [ ] Run migrations and verify schema

### Models
- [ ] Create `Assistant` model
  - [ ] Associations: has_many :tests (polymorphic)
  - [ ] Validations: assistant_id (unique), name, provider
  - [ ] Class methods: from_config, sync_from_config
  - [ ] Instance method: run_test(test:, dataset_row:)
- [ ] Update `PromptTest` model
  - [ ] Change to polymorphic: belongs_to :testable
  - [ ] Keep prompt_version association for backward compat
  - [ ] Add delegation: testable.run_test
- [ ] Update `PromptTestRun` model
  - [ ] Add conversation_data accessor methods
  - [ ] Add helper: conversation? (checks if conversation_data present)
- [ ] Update `PromptVersion` model
  - [ ] Add: has_many :tests, as: :testable
  - [ ] Add: run_test(test:, dataset_row:) method

### Tests
- [ ] `spec/models/prompt_tracker/assistant_spec.rb`
  - [ ] Validations
  - [ ] Associations
  - [ ] from_config class method
  - [ ] sync_from_config class method
- [ ] Update `spec/models/prompt_tracker/prompt_test_spec.rb`
  - [ ] Test polymorphic association
  - [ ] Test with PromptVersion
  - [ ] Test with Assistant
- [ ] Update `spec/models/prompt_tracker/prompt_test_run_spec.rb`
  - [ ] Test conversation_data storage
  - [ ] Test conversation? helper

---

## Phase 2: User Simulator Service ⏱️ 2-3 hours

### Service Implementation
- [ ] Create `UserSimulatorService`
  - [ ] Constants: SIMULATOR_MODEL, SIMULATOR_TEMPERATURE, COMPLETION_TOKEN
  - [ ] Initialize with persona_prompt, max_turns
  - [ ] generate_message(conversation_history:) method
  - [ ] build_system_prompt private method
  - [ ] build_messages private method (flip roles)
  - [ ] Handle COMPLETION_TOKEN detection

### Tests
- [ ] `spec/services/prompt_tracker/user_simulator_service_spec.rb`
  - [ ] Test message generation
  - [ ] Test role flipping in conversation history
  - [ ] Test COMPLETION_TOKEN detection
  - [ ] Test with empty conversation
  - [ ] Test with multi-turn conversation
  - [ ] Mock LlmClientService calls

---

## Phase 3: Assistant Test Runner ⏱️ 3-4 hours

### Service Implementation
- [ ] Create `AssistantTestRunner`
  - [ ] Initialize with assistant, dataset_row, test
  - [ ] run! method (main entry point)
  - [ ] create_test_run private method
  - [ ] execute_conversation private method
  - [ ] create_thread private method
  - [ ] call_assistant private method
  - [ ] run_evaluators private method
  - [ ] Error handling and status updates

### OpenaiAssistantService Updates
- [ ] Update to accept optional thread_id parameter
- [ ] Return thread_id in response metadata
- [ ] Handle thread reuse

### Tests
- [ ] `spec/services/prompt_tracker/assistant_test_runner_spec.rb`
  - [ ] Test successful conversation execution
  - [ ] Test with max_turns limit
  - [ ] Test early termination (COMPLETION_TOKEN)
  - [ ] Test error handling
  - [ ] Test evaluator execution
  - [ ] Mock OpenaiAssistantService and UserSimulatorService

---

## Phase 4: Conversation Judge Evaluator ⏱️ 2-3 hours

### Evaluator Implementation
- [ ] Create `ConversationJudgeEvaluator`
  - [ ] Inherit from BaseEvaluator (or custom base)
  - [ ] Override initialize (accept conversation, not llm_response)
  - [ ] evaluate_score method
  - [ ] generate_feedback method
  - [ ] build_judge_prompt private method
  - [ ] format_conversation private method
  - [ ] parse_score, parse_feedback private methods
  - [ ] Handle JSON parsing errors

### Registry & Forms
- [ ] Register in `EvaluatorRegistry`
  - [ ] Key: :conversation_judge
  - [ ] Name, description, icon
  - [ ] Default config
- [ ] Create form partial: `app/views/prompt_tracker/evaluators/forms/_conversation_judge.html.erb`
  - [ ] Judge model dropdown
  - [ ] Criteria array input
  - [ ] Custom instructions textarea
- [ ] Create template partial: `app/views/prompt_tracker/evaluators/templates/_conversation_judge.html.erb`
  - [ ] Display overall score
  - [ ] Display criteria scores
  - [ ] Display feedback

### Tests
- [ ] `spec/services/prompt_tracker/evaluators/conversation_judge_evaluator_spec.rb`
  - [ ] Test score calculation
  - [ ] Test feedback generation
  - [ ] Test JSON parsing
  - [ ] Test with different criteria
  - [ ] Test error handling
  - [ ] Mock LlmClientService

---

## Phase 5: Test Interface (Polymorphic) ⏱️ 3-4 hours

### Model Updates
- [ ] Update `PromptTest#run!` to delegate to testable
- [ ] Add `PromptVersion#run_test` method
  - [ ] Call existing PromptTestRunner
- [ ] Add `Assistant#run_test` method
  - [ ] Call new AssistantTestRunner

### Service Updates
- [ ] Update `PromptTestRunner` if needed
  - [ ] Ensure compatibility with polymorphic tests

### Tests
- [ ] Integration test: PromptVersion test execution
- [ ] Integration test: Assistant test execution
- [ ] Test polymorphic delegation

---

## Phase 6: Basic UI ⏱️ 4-5 hours

### Controllers
- [ ] Create `Testing::AssistantsController`
  - [ ] index: List all assistants
  - [ ] show: Assistant details + tests
  - [ ] sync: Sync from config
- [ ] Update `Testing::PromptTestsController`
  - [ ] Support polymorphic testable
  - [ ] Handle assistant tests

### Views - Assistant List
- [ ] `app/views/prompt_tracker/testing/assistants/index.html.erb`
  - [ ] Table of assistants (name, category, tests count)
  - [ ] Sync button
  - [ ] Link to create test

### Views - Assistant Show
- [ ] `app/views/prompt_tracker/testing/assistants/show.html.erb`
  - [ ] Assistant details
  - [ ] List of tests
  - [ ] Create test button

### Views - Test Results
- [ ] Update `app/views/prompt_tracker/testing/prompt_test_runs/show.html.erb`
  - [ ] Detect conversation vs single response
  - [ ] Render conversation as chat bubbles
  - [ ] Show conversation metadata (turns, thread_id)
- [ ] Create `_conversation_result.html.erb` partial
  - [ ] Chat bubble UI
  - [ ] User/assistant styling

### Views - Dataset Forms
- [ ] Update dataset row form to detect testable type
  - [ ] For PromptVersion: show variable inputs
  - [ ] For Assistant: show user_prompt, max_turns, expected_outcome

### Routes
- [ ] Add routes for assistants
  - [ ] GET /testing/assistants
  - [ ] GET /testing/assistants/:id
  - [ ] POST /testing/assistants/sync

---

## Phase 7: Integration & Testing ⏱️ 2-3 hours

### Integration Tests
- [ ] Full flow: Create assistant test → Run → View results
- [ ] Test with real OpenAI assistant (if available)
- [ ] Test error scenarios
- [ ] Test with multiple dataset rows

### Edge Cases
- [ ] Handle timeout in conversation
- [ ] Handle assistant requiring action (tool calls)
- [ ] Handle empty conversation
- [ ] Handle malformed dataset rows

### Documentation
- [ ] Update README with assistant testing section
- [ ] Add code examples
- [ ] Document dataset row schema for assistants
- [ ] Add troubleshooting guide

---

## 🎯 Definition of Done

- [ ] All migrations run successfully
- [ ] All tests passing (unit + integration)
- [ ] Can create assistant from config
- [ ] Can create test for assistant
- [ ] Can run test and see conversation
- [ ] Conversation judge evaluates correctly
- [ ] UI displays results properly
- [ ] Documentation updated
- [ ] Code reviewed
- [ ] Demo video recorded

---

## 📊 Progress Tracking

- [ ] Phase 1: Core Models (0/4 tasks)
- [ ] Phase 2: User Simulator (0/2 tasks)
- [ ] Phase 3: Test Runner (0/3 tasks)
- [ ] Phase 4: Judge Evaluator (0/3 tasks)
- [ ] Phase 5: Test Interface (0/3 tasks)
- [ ] Phase 6: UI (0/6 tasks)
- [ ] Phase 7: Testing (0/3 tasks)

**Total: 0/24 major tasks completed**

