# Assistant Conversation Testing - Implementation Checklist (UPDATED)

## Phase 0: Unified Testable Index & Creation Wizard ⏱️ 3-4 hours

### 0.1 Unified Testable Index
- [ ] Create `app/controllers/prompt_tracker/testing/testables_controller.rb`
  - [ ] `index` action (query PromptVersions + Assistants)
  - [ ] Calculate pass rates for each testable
  - [ ] Pagination support
- [ ] Create `app/views/prompt_tracker/testing/testables/index.html.erb`
  - [ ] Table showing all testables (type, name, tests, pass rate, last run)
  - [ ] Filters (by type, by pass rate, by last run date)
  - [ ] Search functionality
  - [ ] "Create New Testable" button
- [ ] Update routes: `root to: "testables#index"` in testing namespace
- [ ] Write controller specs
- [ ] Write system specs for index view

### 0.2 Creation Wizard Modal
- [ ] Create `app/views/prompt_tracker/testing/testables/_creation_wizard_modal.html.erb`
  - [ ] Step 1: Select testable type (Prompt or Assistant)
  - [ ] Step 2: Assistant selector (if Assistant selected)
  - [ ] Descriptions and examples for each type
- [ ] Create `app/javascript/controllers/testable_creation_controller.js` (Stimulus)
  - [ ] `openModal` action
  - [ ] `selectPrompt` action (redirect to playground)
  - [ ] `selectAssistant` action (show assistant selector)
  - [ ] `goToAssistant` action (redirect to assistant show)
- [ ] Add modal-fix controller for z-index issues
- [ ] Write system specs for wizard flow

### 0.3 Model Renames
- [ ] Rename `PromptTest` → `Test`
  - [ ] Generate migration to rename table `prompt_tracker_prompt_tests` → `prompt_tracker_tests`
  - [ ] Rename model file `prompt_test.rb` → `test.rb`
  - [ ] Update class name `PromptTest` → `Test`
  - [ ] Update all references in models
  - [ ] Update all references in controllers
  - [ ] Update all references in views
  - [ ] Update all references in services
  - [ ] Update factories
  - [ ] Update specs
- [ ] Rename `PromptTestRun` → `TestRun`
  - [ ] Generate migration to rename table `prompt_tracker_prompt_test_runs` → `prompt_tracker_test_runs`
  - [ ] Rename model file `prompt_test_run.rb` → `test_run.rb`
  - [ ] Update class name `PromptTestRun` → `TestRun`
  - [ ] Update all references in codebase
  - [ ] Update factories
  - [ ] Update specs
- [ ] Run full test suite to ensure nothing broke

## Phase 1: Core Models ⏱️ 2-3 hours

### 1.1 Create Assistant Model
- [ ] Generate migration for `assistants` table
  - [ ] `assistant_id` (string, unique, indexed)
  - [ ] `name` (string)
  - [ ] `provider` (string, default: "openai_assistants")
  - [ ] `description` (text)
  - [ ] `category` (string)
  - [ ] `metadata` (jsonb) - stores instructions, model, tools, file_ids, last_synced_at
  - [ ] timestamps
- [ ] Create `app/models/prompt_tracker/assistant.rb`
  - [ ] Validations (presence of assistant_id, name, provider; uniqueness of assistant_id)
  - [ ] Associations (has_many :tests, has_many :datasets, has_many :test_runs)
  - [ ] Callbacks (after_create :fetch_from_openai)
  - [ ] `run_test(test:, dataset_row:)` method
  - [ ] `fetch_from_openai!` method (NEW - fetches instructions, model, tools from OpenAI API)
- [ ] Create factory `spec/factories/prompt_tracker/assistants.rb`
  - [ ] Default factory
  - [ ] `:skip_callbacks` trait for faster tests
- [ ] Write model specs `spec/models/prompt_tracker/assistant_spec.rb`
  - [ ] Validations
  - [ ] Associations
  - [ ] Callbacks (test fetch_from_openai)
  - [ ] `fetch_from_openai!` method (with VCR cassettes)
  - [ ] `run_test` method

### 1.2 Make Tests Polymorphic
- [ ] Generate migration to add polymorphic testable to `tests` table
  - [ ] Add `testable_type` (string)
  - [ ] Add `testable_id` (integer)
  - [ ] Add index on `[testable_type, testable_id]`
  - [ ] Backfill existing tests (testable_type = 'PromptTracker::PromptVersion', testable_id = prompt_version_id)
  - [ ] Remove `prompt_version_id` column (or keep for backward compat - decide based on existing usage)
- [ ] Update `app/models/prompt_tracker/test.rb`
  - [ ] Change `belongs_to :prompt_version` to `belongs_to :testable, polymorphic: true`
  - [ ] Update `run!` method to delegate to `testable.run_test(test: self, dataset_row: dataset_row)`
- [ ] Update `app/models/prompt_tracker/prompt_version.rb`
  - [ ] Change `has_many :prompt_tests` to `has_many :tests, as: :testable`
  - [ ] Add `run_test(test:, dataset_row:)` method (delegates to existing PromptTestRunner)
- [ ] Update `app/models/prompt_tracker/assistant.rb`
  - [ ] Add `has_many :tests, as: :testable`
  - [ ] Add `run_test(test:, dataset_row:)` method (delegates to AssistantTestRunner)
- [ ] Update factory `spec/factories/prompt_tracker/tests.rb`
  - [ ] Default association to PromptVersion
  - [ ] Add `:for_assistant` trait
  - [ ] Add `:with_conversation_judge` trait
- [ ] Update model specs
  - [ ] Test polymorphic association with PromptVersion
  - [ ] Test polymorphic association with Assistant
  - [ ] Test `run!` delegation

### 1.3 Add Conversation Data to Test Runs
- [ ] Generate migration for `test_runs` table
  - [ ] Add `conversation_data` (jsonb, default: [])
  - [ ] Add GIN index for querying conversation_data
- [ ] Update `app/models/prompt_tracker/test_run.rb`
  - [ ] Add accessor methods for conversation_data
  - [ ] Add helper methods: `conversation?`, `turn_count`, `assistant_message_count`, `user_message_count`
- [ ] Update factory `spec/factories/prompt_tracker/test_runs.rb`
  - [ ] Add `:with_conversation` trait
  - [ ] Add `:with_evaluations` trait (includes message_scores in metadata)
- [ ] Update model specs
  - [ ] Test conversation_data storage
  - [ ] Test helper methods

### 1.4 Update Dataset for Polymorphic Testable
- [ ] Generate migration to add polymorphic testable to `datasets` table
  - [ ] Add `testable_type` (string)
  - [ ] Add `testable_id` (integer)
  - [ ] Add index on `[testable_type, testable_id]`
  - [ ] Backfill existing datasets (testable_type = 'PromptTracker::PromptVersion', testable_id = prompt_version_id)
  - [ ] Remove `prompt_version_id` column
- [ ] Update `app/models/prompt_tracker/dataset.rb`
  - [ ] Change `belongs_to :prompt_version` to `belongs_to :testable, polymorphic: true`
- [ ] Update factories and specs

---

## Phase 2: User Simulator Service ⏱️ 2-3 hours

### 2.1 Service Implementation
- [ ] Create `app/services/prompt_tracker/user_simulator_service.rb`
  - [ ] Initialize with `persona_prompt`, `max_turns`
  - [ ] `generate_message(conversation_history:)` method
  - [ ] Use global config `user_simulator_model` (gpt-3.5-turbo)
  - [ ] Temperature: 0.8 for natural variation
  - [ ] Flip roles in conversation history (user ↔ assistant)
  - [ ] Return nil when conversation should end
  - [ ] Handle errors gracefully
- [ ] Create `spec/services/prompt_tracker/user_simulator_service_spec.rb`
  - [ ] Test message generation with empty history
  - [ ] Test contextual responses based on conversation history
  - [ ] Test role flipping
  - [ ] Test conversation ending (returns nil)
  - [ ] Test model configuration
  - [ ] Use VCR cassettes for API calls

### 2.2 Configuration
- [ ] Add to `lib/prompt_tracker/configuration.rb`
  - [ ] `user_simulator_model` attribute (default: "gpt-3.5-turbo")
- [ ] Update initializer template
  - [ ] Add `config.user_simulator_model = "gpt-3.5-turbo"`

---

## Phase 3: Assistant Test Runner ⏱️ 3-4 hours

### 3.1 Service Implementation
- [ ] Create `app/services/prompt_tracker/assistant_test_runner.rb`
  - [ ] Initialize with `assistant`, `dataset_row`, `test:`
  - [ ] `run!` method (main execution)
  - [ ] Create thread via OpenaiAssistantService
  - [ ] Initialize UserSimulatorService
  - [ ] Conversation loop (up to max_turns)
  - [ ] Store conversation_data in test_run
  - [ ] Store thread_id in metadata
  - [ ] Handle timeouts gracefully
  - [ ] Raise error if assistant requires_action (tool calls)
- [ ] Create `spec/services/prompt_tracker/assistant_test_runner_spec.rb`
  - [ ] Test full conversation execution
  - [ ] Test max_turns limit
  - [ ] Test early conversation ending
  - [ ] Test thread_id storage
  - [ ] Test error handling for tool calls
  - [ ] Use VCR cassettes

---

## Phase 4: Conversation Judge Evaluator (PER-MESSAGE SCORING) ⏱️ 3-4 hours

### 4.1 Evaluator Implementation
- [ ] Create `app/services/prompt_tracker/evaluators/conversation_judge_evaluator.rb`
  - [ ] Initialize with `test_run:`, `config:`
  - [ ] `evaluate` method (returns full result hash)
  - [ ] `evaluate_score` method (returns overall score)
  - [ ] `generate_feedback` method (returns overall feedback)
  - [ ] Format conversation with message indices
  - [ ] Build judge prompt requesting per-message scores
  - [ ] Call LLM judge (use global `conversation_judge_model`)
  - [ ] Parse JSON response with message_scores array
  - [ ] Calculate overall_score = average of message scores
  - [ ] Only score assistant messages (not user messages)
- [ ] Config schema (SIMPLIFIED - NO criteria):
  ```ruby
  {
    evaluation_prompt: "Evaluate each assistant message...",
    judge_model: nil  # Uses global config
  }
  ```
- [ ] Output format:
  ```ruby
  {
    overall_score: 88,
    message_scores: [
      { message_index: 0, role: "assistant", score: 90, reason: "..." },
      ...
    ],
    overall_feedback: "..."
  }
  ```
- [ ] Create `spec/services/prompt_tracker/evaluators/conversation_judge_evaluator_spec.rb`
  - [ ] Test per-message scoring (only assistant messages)
  - [ ] Test overall score calculation (average)
  - [ ] Test overall feedback generation
  - [ ] Test global model configuration
  - [ ] Test empty conversation handling
  - [ ] Use VCR cassettes

### 4.2 Form Partial
- [ ] Create `app/views/prompt_tracker/evaluators/forms/_conversation_judge.html.erb`
  - [ ] Textarea for `evaluation_prompt`
  - [ ] Help text explaining per-message scoring
  - [ ] Note that judge_model uses global config

### 4.3 Template Partial
- [ ] Create `app/views/prompt_tracker/evaluators/templates/_conversation_judge.html.erb`
  - [ ] Display overall score prominently
  - [ ] Display overall feedback
  - [ ] Table of message scores (message index, content preview, score, reason)
  - [ ] Visual indicators for high/low scores

### 4.4 Registry
- [ ] Register in `EvaluatorRegistry`
  ```ruby
  EvaluatorRegistry.register(
    key: :conversation_judge,
    name: "Conversation Judge (Per-Message)",
    description: "Scores each assistant message individually using LLM",
    evaluator_class: ConversationJudgeEvaluator,
    icon: "chat-dots",
    default_config: {
      evaluation_prompt: "Evaluate each assistant message for quality, empathy, and accuracy. Score each message from 0-100.",
      judge_model: nil
    }
  )
  ```

### 4.5 Configuration
- [ ] Add to `lib/prompt_tracker/configuration.rb`
  - [ ] `conversation_judge_model` attribute (default: "gpt-4")
- [ ] Update initializer template
  - [ ] Add `config.conversation_judge_model = "gpt-4"`

---

## Phase 5: Test Interface (Polymorphic) ⏱️ 3-4 hours

### 5.1 Update Test Runner
- [ ] Update `app/services/prompt_tracker/prompt_test_runner.rb`
  - [ ] Detect testable type
  - [ ] Delegate to testable.run_test for polymorphic handling
  - [ ] Keep existing logic for PromptVersion tests

### 5.2 Update Job
- [ ] Update `app/jobs/prompt_tracker/run_test_job.rb`
  - [ ] Handle both PromptVersion and Assistant tests
  - [ ] Store conversation_data for assistant tests
  - [ ] Run evaluators (including ConversationJudgeEvaluator)

---

## Phase 6: UI (Assistant Show + Inline Message Scores) ⏱️ 5-6 hours

### 6.1 Assistant Controller
- [ ] Create `app/controllers/prompt_tracker/testing/assistants_controller.rb`
  - [ ] `index` action (list all assistants)
  - [ ] `show` action (auto-fetch from OpenAI API)
  - [ ] `sync` action (manual sync from OpenAI API)
- [ ] Write controller specs
  - [ ] Test auto-fetch on show
  - [ ] Test manual sync
  - [ ] Use VCR cassettes

### 6.2 Assistant Views
- [ ] Create `app/views/prompt_tracker/testing/assistants/index.html.erb`
  - [ ] List all assistants
  - [ ] Show pass rates, last run
  - [ ] Link to show page
- [ ] Create `app/views/prompt_tracker/testing/assistants/show.html.erb`
  - [ ] Display assistant metadata (instructions, model, tools) - auto-fetched from OpenAI
  - [ ] Show loading state while fetching
  - [ ] Manual sync button
  - [ ] Display tests (list of all tests)
  - [ ] Button to create new test
  - [ ] Display datasets
  - [ ] Button to create dataset
  - [ ] Button to run test
- [ ] Create `app/views/prompt_tracker/testing/assistants/_conversation_result.html.erb`
  - [ ] Display conversation as chat bubbles
  - [ ] **Inline message scores** for each assistant message
  - [ ] Visual indicators (color-coded by score)
  - [ ] Overall score at top
  - [ ] Overall feedback
  - [ ] Metadata (turns, thread_id, execution time)

### 6.3 Dataset Row Form (for Assistants)
- [ ] Update dataset row form to detect testable type
- [ ] For assistants, show:
  - [ ] `user_prompt` textarea (large, with help text: "Describe the user persona and scenario")
  - [ ] `max_turns` number input (default: 10)
  - [ ] NO evaluation fields (evaluation config is in Test → EvaluatorConfig, not in dataset rows)
  - [ ] Help text explaining: "Dataset rows contain test scenarios only. Evaluation settings are configured in each test."

### 6.4 Routes
- [ ] Update `config/routes.rb`
  - [ ] `namespace :testing do`
  - [ ] `root to: "testables#index"` (NEW)
  - [ ] `resources :assistants, only: [:index, :show] do`
  - [ ] `post :sync, on: :member`

---

## Phase 7: Integration & Testing ⏱️ 3-4 hours

### 7.1 Integration Specs
- [ ] Create `spec/system/assistant_conversation_testing_spec.rb`
  - [ ] Test full flow: create assistant → create dataset → add row → run test → view results
  - [ ] Test creation wizard flow
  - [ ] Test unified testable index
  - [ ] Test per-message scores display
  - [ ] Use VCR cassettes

### 7.2 Edge Cases
- [ ] Test timeout handling
- [ ] Test API errors (OpenAI down)
- [ ] Test tool call errors (assistant requires_action)
- [ ] Test empty conversations
- [ ] Test max_turns reached

### 7.3 Documentation
- [ ] Update README with assistant testing examples
- [ ] Add inline code comments
- [ ] Update API documentation

---

## ✅ Definition of Done

- [ ] All migrations run successfully
- [ ] All models have 100% test coverage
- [ ] All services have 95%+ test coverage
- [ ] All controllers have 90%+ test coverage
- [ ] Integration tests pass for full flow
- [ ] UI displays correctly (unified index, creation wizard, assistant show, inline scores)
- [ ] OpenAI API integration works (with VCR cassettes)
- [ ] Per-message scoring works correctly
- [ ] Global configuration works
- [ ] Multiple tests per assistant supported
- [ ] Documentation updated

---

## 📊 Estimated Total Time

| Phase | Hours |
|-------|-------|
| Phase 0: Unified Index & Wizard | 3-4 |
| Phase 1: Core Models | 2-3 |
| Phase 2: User Simulator | 2-3 |
| Phase 3: Test Runner | 3-4 |
| Phase 4: Judge Evaluator | 3-4 |
| Phase 5: Test Interface | 3-4 |
| Phase 6: UI | 5-6 |
| Phase 7: Testing | 3-4 |
| **TOTAL** | **24-32 hours** |

**~4-5 days of focused work**
