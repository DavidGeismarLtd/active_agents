# Option A: UI/Controllers Implementation Plan

## Overview

Build the complete UI/Controllers for OpenAI Assistants feature, enabling users to create, test, and monitor assistants through the web interface.

## Phase 1: Seed Data Refactoring ✅ PLANNED

**Goal**: Split monolithic seed file into modular files and add assistant examples

### Tasks
- [x] Create `test/dummy/db/seeds/` directory
- [x] Create PLAN.md with detailed refactoring plan
- [x] Create 07_assistants_openai_PLAN.md with assistant seed plan
- [x] Create README.md with usage documentation
- [ ] Extract existing seeds into 10 separate files (01-10, 99)
- [ ] Create new `07_assistants_openai.rb` with 3 assistant examples
- [ ] Update main `seeds.rb` to load all seed files
- [ ] Test: `cd test/dummy && bin/rails db:reset`

**Files to Create**:
```
test/dummy/db/seeds/
├── 01_cleanup.rb                 # Delete all data
├── 02_prompts_customer_support.rb
├── 03_prompts_email_generation.rb
├── 04_prompts_code_review.rb
├── 05_tests_basic.rb
├── 06_tests_advanced.rb
├── 07_assistants_openai.rb       # ⭐ NEW
├── 08_llm_responses.rb
├── 09_evaluations.rb
├── 10_ab_tests.rb
└── 99_summary.rb
```

**Estimated Time**: 2-3 hours

---

## Phase 2: Routes & Controllers

**Goal**: Create routes and controllers for assistant CRUD operations

### 2.1 Routes Configuration

**File**: `config/routes.rb`

Add under `namespace :testing`:
```ruby
namespace :testing do
  # ... existing prompts routes ...
  
  # NEW: OpenAI Assistants
  namespace :openai do
    resources :assistants do
      # Tests nested under assistants (reuse Test model)
      resources :tests, controller: "assistant_tests", only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        member do
          post :run
        end
      end
      
      # Datasets nested under assistants (reuse Dataset model)
      resources :datasets, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        member do
          post :generate_rows
        end
        resources :dataset_rows, only: [:create, :update, :destroy], path: "rows"
      end
    end
  end
end
```

**URLs Generated**:
- `/prompt_tracker/testing/openai/assistants` - Index
- `/prompt_tracker/testing/openai/assistants/new` - New
- `/prompt_tracker/testing/openai/assistants/:id` - Show
- `/prompt_tracker/testing/openai/assistants/:id/edit` - Edit
- `/prompt_tracker/testing/openai/assistants/:id/tests` - Tests index
- `/prompt_tracker/testing/openai/assistants/:id/datasets` - Datasets index

### 2.2 Controllers to Create

#### `app/controllers/prompt_tracker/testing/openai/assistants_controller.rb`
**Actions**: index, show, new, create, edit, update, destroy
**Purpose**: CRUD for OpenAI Assistants
**Size**: ~150 lines

#### `app/controllers/prompt_tracker/testing/openai/assistant_tests_controller.rb`
**Actions**: index, new, create, show, edit, update, destroy, run
**Purpose**: Manage tests for assistants (reuse Test model)
**Size**: ~120 lines
**Note**: Similar to PromptTestsController but for assistants

#### `app/controllers/prompt_tracker/testing/openai/datasets_controller.rb`
**Actions**: index, new, create, show, edit, update, destroy, generate_rows
**Purpose**: Manage datasets for assistants (reuse Dataset model)
**Size**: ~100 lines
**Note**: Similar to existing DatasetsController but for assistants

**Estimated Time**: 3-4 hours

---

## Phase 3: Views - Assistant CRUD

**Goal**: Create views for creating and managing assistants

### 3.1 Assistant Index
**File**: `app/views/prompt_tracker/testing/openai/assistants/index.html.erb`
**Features**:
- List all assistants with cards
- Show assistant name, description, tags
- Show test count, last test run status
- Search and filter by tags
- "New Assistant" button

**Size**: ~100 lines

### 3.2 Assistant Show
**File**: `app/views/prompt_tracker/testing/openai/assistants/show.html.erb`
**Features**:
- Assistant details (name, description, assistant_id, model, tools)
- Tabs: Overview | Tests | Datasets | Test Runs
- Quick stats (total tests, pass rate, last run)
- Edit/Delete buttons

**Size**: ~150 lines

### 3.3 Assistant Form
**File**: `app/views/prompt_tracker/testing/openai/assistants/_form.html.erb`
**Features**:
- Name, description fields
- Assistant ID input (from OpenAI)
- Model dropdown (from config.available_models)
- Tools configuration (JSON editor or checkboxes)
- Instructions textarea
- Tags input

**Size**: ~120 lines

### 3.4 Assistant Card Partial
**File**: `app/views/prompt_tracker/testing/openai/assistants/_assistant_card.html.erb`
**Features**:
- Compact card for index view
- Shows key info and stats
- Click to view details

**Size**: ~50 lines

**Estimated Time**: 4-5 hours

---

## Phase 4: Views - Tests & Datasets

**Goal**: Create views for managing tests and datasets for assistants

### 4.1 Tests Index
**File**: `app/views/prompt_tracker/testing/openai/assistant_tests/index.html.erb`
**Features**:
- List all tests for assistant
- Show test name, evaluators, enabled status
- Run test button
- New test button

**Size**: ~80 lines

### 4.2 Test Form
**File**: `app/views/prompt_tracker/testing/openai/assistant_tests/_form.html.erb`
**Features**:
- Test name, description
- Dataset selector
- Evaluator configs (focus on ConversationJudgeEvaluator)
- Enabled checkbox

**Size**: ~100 lines

### 4.3 Test Show (with Conversation Display)
**File**: `app/views/prompt_tracker/testing/openai/assistant_tests/show.html.erb`
**Features**:
- Test details
- Recent test runs table
- **Conversation display** with per-message scores
- Evaluator results

**Size**: ~150 lines

### 4.4 Conversation Display Partial
**File**: `app/views/prompt_tracker/testing/openai/_conversation.html.erb`
**Features**:
- Chat-style message display
- User messages (left) vs Assistant messages (right)
- Per-message scores from ConversationJudgeEvaluator
- Color-coded scores (green = high, yellow = medium, red = low)
- Expandable feedback for each message

**Size**: ~80 lines

**Estimated Time**: 5-6 hours

---

## Phase 5: Unified Testables Index

**Goal**: Create a unified index showing both prompts and assistants

### 5.1 Testables Controller
**File**: `app/controllers/prompt_tracker/testing/testables_controller.rb`
**Actions**: index
**Purpose**: Show all testables (prompts + assistants) in one view

**Size**: ~60 lines

### 5.2 Testables Index View
**File**: `app/views/prompt_tracker/testing/testables/index.html.erb`
**Features**:
- Tabs: All | Prompts | Assistants
- Unified card layout
- Filter by type, tags, status
- Search across both types
- "Create New" dropdown (Prompt or Assistant)

**Size**: ~120 lines

### 5.3 Update Routes
Add to `config/routes.rb`:
```ruby
namespace :testing do
  get "/", to: "testables#index", as: :root  # Change from dashboard
  # ... rest of routes ...
end
```

**Estimated Time**: 2-3 hours

---

## Phase 6: Integration & Polish

**Goal**: Integrate all pieces and add polish

### 6.1 Navigation Updates
- Update sidebar to include "Assistants" link
- Update breadcrumbs for assistant pages
- Add "Create Assistant" to quick actions

### 6.2 Turbo Streams
- Add broadcasts for assistant test runs
- Real-time updates when tests complete
- Live conversation display updates

### 6.3 Styling
- Ensure consistent styling with existing UI
- Add icons for assistants (different from prompts)
- Color-code conversation messages
- Responsive design for mobile

### 6.4 Error Handling
- Validation errors in forms
- Graceful handling of missing assistant_id
- Clear error messages

**Estimated Time**: 3-4 hours

---

## Phase 7: Testing & Documentation

**Goal**: Ensure everything works and is documented

### 7.1 Manual Testing
- [ ] Create assistant via UI
- [ ] Create dataset for assistant
- [ ] Create test with ConversationJudgeEvaluator
- [ ] Run test and view results
- [ ] View conversation with per-message scores
- [ ] Edit and delete assistant

### 7.2 Update Documentation
- [ ] Update README with assistant feature
- [ ] Add screenshots to docs
- [ ] Update CHANGELOG

**Estimated Time**: 2-3 hours

---

## Total Estimated Time

| Phase | Description | Time |
|-------|-------------|------|
| 1 | Seed Data Refactoring | 2-3 hours |
| 2 | Routes & Controllers | 3-4 hours |
| 3 | Views - Assistant CRUD | 4-5 hours |
| 4 | Views - Tests & Datasets | 5-6 hours |
| 5 | Unified Testables Index | 2-3 hours |
| 6 | Integration & Polish | 3-4 hours |
| 7 | Testing & Documentation | 2-3 hours |
| **Total** | | **21-28 hours** |

## Success Criteria

- [ ] Users can create assistants via UI
- [ ] Users can create tests for assistants
- [ ] Users can run tests and view conversation results
- [ ] Per-message scores are displayed clearly
- [ ] Unified testables index shows both prompts and assistants
- [ ] All seed data loads successfully
- [ ] No console errors or warnings
- [ ] Responsive design works on mobile
- [ ] Documentation is complete

## Next Steps

1. **Start with Phase 1** (Seed Data Refactoring) - Foundation for testing
2. **Then Phase 2** (Routes & Controllers) - Backend structure
3. **Then Phase 3-4** (Views) - User interface
4. **Finally Phase 5-7** (Integration & Polish) - Complete feature

Ready to proceed? 🚀

