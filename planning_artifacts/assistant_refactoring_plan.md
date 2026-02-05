# Architectural Refactoring Plan: Remove Assistant Model & Consolidate into Generic Playground

**Date:** 2026-02-03
**Status:** Planning Phase
**Breaking Changes:** Yes (no backward compatibility required)

---

## Executive Summary

This plan outlines a major architectural refactoring to:
1. **Remove** the `PromptTracker::Openai::Assistant` model entirely
2. **Consolidate** all API testing into the generic Playground
3. **Create** a provider-agnostic VectorStoreService
4. **Simplify** test runner architecture (all testables are PromptVersion)
5. **Extract** routing logic into shared factory to eliminate duplication
6. **Standardize** naming conventions for conversation test handlers

The OpenAI Assistants API will become just another API option in the generic playground's dropdown, alongside Chat Completions and Response API.

**Key Architectural Improvements:**
- **Single Testable Type:** Only `PromptVersion` exists (no `Openai::Assistant` model)
- **Unified Runner:** `PromptVersionRunner` handles all testables (no runner routing needed)
- **Factory Routing:** `ConversationTestHandlerFactory` routes to API-specific handlers based on `model_config`
- **Centralized Routing:** API routing logic lives in one place (eliminates duplication)
- **Consistent Naming:** All conversation test handlers follow standardized naming pattern
- **Sync to PromptVersions:** "Sync with OpenAI" creates PromptVersions instead of Assistant records

---

## Current Architecture Problems

### 1. Duplicate Testable Entity
- `PromptTracker::Openai::Assistant` is a separate testable model with its own:
  - Controllers (`AssistantsController`, `AssistantPlaygroundController`, `AssistantTestsController`, `AssistantDatasetsController`)
  - Views (`app/views/prompt_tracker/testing/openai/assistants/`, `assistant_playground/`, `assistant_tests/`)
  - Routes (60+ lines in `config/routes.rb` lines 90-149)
  - Database table (`prompt_tracker_openai_assistants`)
  - Services (`AssistantPlaygroundService`, `SyncOpenaiAssistantsService`)

### 2. Architectural Coupling
- Vector store operations are coupled to `AssistantPlaygroundService`
- But vector stores are a general OpenAI feature usable across:
  - Assistants API (via `tool_resources.file_search.vector_store_ids`)
  - Response API (via `tool_config.file_search.vector_store_ids`)
  - Potentially other APIs in the future

### 3. Code Duplication
- The generic playground already supports multiple APIs via `model_config`
- Separate Assistant playground duplicates functionality:
  - Thread/conversation management
  - Message sending
  - Configuration UI
  - Test execution

### 4. Inconsistent API Handling
- `ConversationTestHandlerFactory` routes to different handlers based on API type
- But it doesn't currently handle `:openai_assistants` (lines 77-95)
- The `AssistantRunner` expects an `Assistant` testable instead of `PromptVersion`

### 5. Routing Logic Duplication
- API routing logic is duplicated across multiple services:
  - `PlaygroundExecuteService.execute_api_call` (lines 82-94) - routes based on `api` string
  - `LlmClientService.call` (lines 70-94) - routes using `ApiTypes.from_config`
  - `ConversationTestHandlerFactory.executor_class_for` (lines 73-96) - routes using `ApiTypes.from_config`
- This duplication makes it harder to add new APIs and maintain consistency

### 6. Inconsistent Naming Conventions
- Conversation test handlers have inconsistent naming:
  - `TestRunners::Openai::ResponseApiHandler` (for Response API)
  - `Openai::ConversationRunner` (for Assistants API - not in TestRunners namespace!)
  - `TestRunners::Openai::ChatCompletionHandler` (for Chat Completions)
- Base class is `ConversationTestHandler` but handlers don't follow consistent pattern

---

## Target Architecture

### 1. Single Testable Entity: PromptVersion
- **PromptVersion** becomes the only testable entity
- `model_config` determines which API to use:
  ```ruby
  {
    provider: "openai",
    api: "assistants",        # <-- Selects Assistants API
    assistant_id: "asst_abc123",  # <-- NEW: Assistant ID stored here
    model: "gpt-4o",          # <-- Actual model name (can override assistant's default)
    temperature: 0.7,
    # ... other config
  }
  ```
- **IMPORTANT:** `assistant_id` and `model` are separate fields
  - An assistant has its own model configuration
  - The `model` field can override the assistant's default model at runtime
  - This matches the OpenAI Assistants API structure

### 2. Sync with OpenAI Creates PromptVersions
- **"Sync with OpenAI" button** creates PromptVersions instead of Assistant records
- Each synced assistant becomes a PromptVersion with:
  - `name` = assistant's name
  - `system_prompt` = assistant's instructions
  - `model_config[:api] = "assistants"`
  - `model_config[:assistant_id] = "asst_abc123"`
  - `model_config[:model] = "gpt-4o"` (from assistant data)
  - `model_config[:tools]` = assistant's tools
  - `model_config[:tool_resources]` = assistant's tool_resources (vector stores, etc.)
- Users select from synced PromptVersions in the playground (no dynamic dropdown)

### 3. Provider-Agnostic VectorStoreService
- Follows the same routing pattern as `LlmClientService`
- Routes to provider-specific implementations:
  ```ruby
  VectorStoreService.list_vector_stores(provider: :openai)
  # => Delegates to Openai::VectorStoreOperations.list_vector_stores
  ```

### 4. Unified Test Runner Architecture
- **All testables are PromptVersion** - no runner routing needed
- `RunTestJob` always uses `TestRunners::PromptVersionRunner`
- `PromptVersionRunner` delegates to `ConversationTestHandlerFactory` for API-specific execution
- **Simplified flow:**
  ```
  RunTestJob
    ↓
  PromptVersionRunner (always)
    ↓
  ConversationTestHandlerFactory (routes based on model_config)
    ↓
  API-specific handler (ResponseApiHandler, ChatCompletionHandler, AssistantsHandler)
  ```

### 5. Centralized API Routing in LlmClientService
- **`LlmClientService`** is the single entry point for all LLM API calls
- Uses `ApiTypes.from_config(provider, api)` for consistent API type detection
- Routes to appropriate service based on API type:
  - `:openai_responses` → `OpenaiResponseService`
  - `:openai_assistants` → `OpenaiAssistantService`
  - All other APIs → RubyLLM client
- **Pattern:**
  ```ruby
  LlmClientService.call(
    provider: model_config[:provider],
    api: model_config[:api],
    model: model_config[:model],
    prompt: "Hello",
    temperature: 0.7
  )
  ```

### 6. Standardized Naming for Conversation Handlers
- **All conversation test handlers** follow consistent naming pattern:
  - Base class: `TestRunners::SimulatedConversationRunner`
  - Handlers: `TestRunners::{Provider}::{ApiName}::SimulatedConversationRunner`
- **Examples:**
  - `TestRunners::Openai::Responses::SimulatedConversationRunner` (was `ResponseApiHandler`)
  - `TestRunners::Openai::Assistants::SimulatedConversationRunner` (was `Openai::ConversationRunner`)
  - `TestRunners::Openai::ChatCompletions::SimulatedConversationRunner` (was `ChatCompletionHandler`)
- **Rationale:** Clear, consistent naming that indicates purpose and API type

---

## Migration Plan Overview

### Phase 1: Create New Services (No Breaking Changes)
1. Create `VectorStoreService` and `Openai::VectorStoreOperations`
2. Refactor `LlmClientService` to extract routing logic into reusable private method
3. Rename and reorganize conversation test handlers for consistency
4. Create `TestRunners::Openai::Assistants::SimulatedConversationRunner`
5. Update `ConversationTestHandlerFactory` to route to new handlers
6. Add tests for new services

### Phase 2: Update Sync Service (Additive Changes)
1. Rename `SyncOpenaiAssistantsService` to `SyncOpenaiAssistantsToPromptVersionsService`
2. Update sync service to create PromptVersions instead of Assistant records
3. Update dashboard view to reflect new sync behavior
4. Test syncing assistants to PromptVersions

### Phase 3: Simplify Test Runner Architecture (Preparation)
1. Update `RunTestJob` to always use `PromptVersionRunner` (remove routing logic)
2. Update `PromptVersionRunner` to handle all testable types
3. Test that all existing tests still work

### Phase 4: Remove Assistant Model (Breaking Changes)
1. Remove all Assistant-specific controllers
2. Remove all Assistant-specific views
3. Remove all Assistant-specific routes
4. Remove Assistant model and migration
5. Remove `AssistantRunner` (no longer needed)
6. Remove Assistant-specific services (`AssistantPlaygroundService`)
7. Remove Assistant-specific tests and factories
8. Remove Assistant-specific seeds

### Phase 5: Cleanup and Documentation
1. Update documentation
2. Remove deprecated code
3. Run full test suite
4. Update README with new architecture

---

## 5. Files to Delete

### Controllers (5 files)
```
app/controllers/prompt_tracker/testing/openai/assistants_controller.rb
app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb
app/controllers/prompt_tracker/testing/openai/assistant_tests_controller.rb
app/controllers/prompt_tracker/testing/openai/assistant_datasets_controller.rb
app/controllers/prompt_tracker/testing/openai/dataset_rows_controller.rb
```

### Views (15+ files)
```
app/views/prompt_tracker/testing/openai/assistants/index.html.erb
app/views/prompt_tracker/testing/openai/assistants/show.html.erb
app/views/prompt_tracker/testing/openai/assistant_playground/show.html.erb
app/views/prompt_tracker/testing/openai/assistant_playground/_file_management.html.erb
app/views/prompt_tracker/testing/openai/assistant_playground/_generate_instructions_modal.html.erb
app/views/prompt_tracker/testing/openai/assistant_playground/_generating_instructions_modal.html.erb
app/views/prompt_tracker/testing/openai/assistant_tests/_form.html.erb
app/views/prompt_tracker/testing/openai/assistant_tests/edit.html.erb
app/views/prompt_tracker/testing/openai/assistant_tests/index.html.erb
app/views/prompt_tracker/testing/openai/assistant_tests/new.html.erb
app/views/prompt_tracker/testing/openai/assistant_tests/show.html.erb
app/views/prompt_tracker/testing/tests/openai_assistants/test_row.html.erb (if exists)
app/views/prompt_tracker/testing/tests/openai_assistants/form.html.erb (if exists)
```

### Models (1 file)
```
app/models/prompt_tracker/openai/assistant.rb
```

### Services (6 files)
```
app/services/prompt_tracker/assistant_playground_service.rb
app/services/prompt_tracker/sync_openai_assistants_service.rb
app/services/prompt_tracker/test_runners/openai/assistant_runner.rb  # No longer needed - all testables are PromptVersion
app/services/prompt_tracker/openai/conversation_runner.rb  # Will be renamed and moved to TestRunners namespace
app/services/prompt_tracker/openai/response_api_conversation_runner.rb  # OLD - replaced by ResponseApiHandler
app/services/prompt_tracker/openai/conversation_result.rb  # Value object used only by ResponseApiConversationRunner
```

### JavaScript Controllers (1 file)
```
app/javascript/prompt_tracker/controllers/assistant_playground_controller.js
```

### Factories (1 file)
```
spec/factories/prompt_tracker/openai/assistants.rb
```

### Specs (12+ files)
```
spec/models/prompt_tracker/openai/assistant_spec.rb
spec/controllers/prompt_tracker/testing/openai/assistants_controller_spec.rb
spec/controllers/prompt_tracker/testing/openai/assistant_playground_controller_spec.rb
spec/controllers/prompt_tracker/testing/openai/assistant_tests_controller_spec.rb
spec/services/prompt_tracker/assistant_playground_service_spec.rb
spec/services/prompt_tracker/sync_openai_assistants_service_spec.rb
spec/services/prompt_tracker/test_runners/openai/assistant_runner_spec.rb
spec/services/prompt_tracker/openai/response_api_conversation_runner_spec.rb  # OLD - no longer used
spec/services/prompt_tracker/openai/conversation_result_spec.rb  # OLD - no longer used
spec/system/prompt_tracker/assistant_playground_spec.rb (if exists)
spec/system/prompt_tracker/assistant_tests_spec.rb (if exists)
```

### Seeds (2 files)
```
test/dummy/db/seeds/07_assistants_openai.rb
test/dummy/db/seeds/07_assistants_openai_PLAN.md
```

### Migration Changes
```
db/migrate/20251216000001_create_prompt_tracker_schema.rb
  - Remove lines 76-90 (prompt_tracker_openai_assistants table)
  - Remove foreign key references to assistants table (if any)
```

**Total Files to Delete:** ~44 files (includes 2 old unused services + 2 old specs)

---

## 6. Files to Create

### Services (2 files)
```
app/services/prompt_tracker/vector_store_service.rb
  - Provider-agnostic routing service for vector store operations
  - Methods: list_vector_stores, create_vector_store, list_vector_store_files, add_file_to_vector_store
  - Delegates to provider-specific implementations

app/services/prompt_tracker/openai/vector_store_operations.rb
  - OpenAI-specific vector store operations
  - Implements the actual API calls to OpenAI
  - Uses OpenAI client from configuration
```

### Test Handlers (3 files - renamed/reorganized)
```
app/services/prompt_tracker/test_runners/openai/assistants/simulated_conversation_runner.rb
  - NEW: Conversation test handler for Assistants API
  - Renamed from Openai::ConversationRunner
  - Works with PromptVersion where model_config[:api] == "assistants"
  - Extracts assistant_id from model_config[:assistant_id]
  - Inherits from TestRunners::SimulatedConversationRunner

app/services/prompt_tracker/test_runners/openai/responses/simulated_conversation_runner.rb
  - RENAMED from TestRunners::Openai::ResponseApiHandler
  - Conversation test handler for Response API
  - Inherits from TestRunners::SimulatedConversationRunner

app/services/prompt_tracker/test_runners/simulated_conversation_runner.rb
  - RENAMED from TestRunners::ConversationTestHandler
  - Base class for all conversation test handlers
  - Provides common interface and utilities
```

### Sync Service (1 file - renamed)
```
app/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service.rb
  - RENAMED from SyncOpenaiAssistantsService
  - Creates PromptVersions instead of Assistant records
  - Fetches assistants from OpenAI API
  - Maps assistant data to PromptVersion with correct model_config structure
```

### Specs (6 files)
```
spec/services/prompt_tracker/vector_store_service_spec.rb
spec/services/prompt_tracker/openai/vector_store_operations_spec.rb
spec/services/prompt_tracker/api_executor_factory_spec.rb
spec/services/prompt_tracker/test_runners/openai/assistants/simulated_conversation_runner_spec.rb
spec/services/prompt_tracker/test_runners/openai/responses/simulated_conversation_runner_spec.rb
spec/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service_spec.rb
```

### Seeds (1 file - optional)
```
test/dummy/db/seeds/07_assistants_api_examples.rb
  - Create PromptVersion examples that use Assistants API
  - Show how to configure model_config for Assistants API with assistant_id
  - Include datasets and tests for conversational testing
```

**Total Files to Create:** ~14 files (including renames)

---

## 7. Files to Modify

### Configuration (2 files)
```
lib/prompt_tracker/configuration.rb
  - Remove openai_assistants configuration (lines 59-61, 92)
  - Add assistants API to default providers configuration

test/dummy/config/initializers/prompt_tracker.rb
  - Remove openai_assistants configuration block (lines 114-123)
  - Assistants API is already defined in providers.openai.apis.assistants (lines 46-49)
```

### Routes (1 file)
```
config/routes.rb
  - Remove entire namespace :openai block (lines 90-149)
  - Keep only the generic playground routes
```

### Services (5 files)
```
app/services/prompt_tracker/conversation_test_handler_factory.rb
  - Update routing for :openai_assistants to use new SimulatedConversationRunner
  - Update case statement to use renamed handlers
  - Use ApiTypes.from_config for consistent API type detection

app/services/prompt_tracker/playground_execute_service.rb
  - RENAME to PlaygroundConversationService
  - Replace routing logic with calls to LlmClientService
  - Update to use model_config[:assistant_id] instead of model_config[:model]
  - Simplify by delegating all API calls to LlmClientService

app/services/prompt_tracker/llm_client_service.rb
  - Extract routing logic into private method for reusability
  - Update to use model_config[:assistant_id] for Assistants API (line 90)
  - Keep as single entry point for all LLM API calls
  - Ensure consistent use of ApiTypes.from_config for routing

app/services/prompt_tracker/test_runners/prompt_version_runner.rb
  - Update to handle all testable types (no changes needed - already works)
  - Verify it works with Assistants API via ConversationTestHandlerFactory

app/jobs/prompt_tracker/run_test_job.rb
  - SIMPLIFY: Remove resolve_runner_class method entirely
  - Always use TestRunners::PromptVersionRunner (all testables are PromptVersion)
  - Remove case statement routing logic
```

### Views (4 files)
```
app/views/prompt_tracker/testing/playground/_model_config_form.html.erb
  - Update to use model_config[:assistant_id] field (not model_config[:model])
  - Show assistant_id input field when api: "assistants" is selected
  - Show model field separately (can override assistant's default model)

app/views/prompt_tracker/testing/playground/show.html.erb
  - Update to handle Assistants API selection
  - Show appropriate UI for assistant configuration

app/views/prompt_tracker/testing/dashboard/index.html.erb
  - Update "Sync with OpenAI" button text/tooltip to reflect new behavior
  - Indicate that syncing creates PromptVersions (not Assistant records)

app/views/prompt_tracker/evaluator_configs/forms/_file_search.html.erb
  - Update to use VectorStoreService instead of AssistantPlaygroundService
```

### JavaScript (2 files)
```
app/javascript/prompt_tracker/controllers/playground_controller.js
  - Add handling for api: "assistants" selection
  - Fetch and populate assistant selector
  - Handle assistant-specific configuration

app/javascript/prompt_tracker/controllers/tools_config_controller.js
  - Update vector store operations to use new API endpoint
```

### Controllers (3 files)
```
app/controllers/prompt_tracker/api/vector_stores_controller.rb
  - Update to use VectorStoreService instead of AssistantPlaygroundService
  - Add show action for vector store details

app/controllers/prompt_tracker/testing/playground_controller.rb
  - Update to use PlaygroundConversationService (renamed)
  - Handle assistant_id in model_config (separate from model field)

app/controllers/prompt_tracker/testing/sync_openai_assistants_controller.rb
  - Update to use SyncOpenaiAssistantsToPromptVersionsService (renamed)
  - Update response to reflect PromptVersions created (not Assistants)
```

### Models (1 file)
```
app/services/prompt_tracker/evaluators/base_normalized_evaluator.rb
  - Remove PromptTracker::Openai::Assistant from compatible_with array (line 60)
```

### Specs (Update existing specs that reference Assistant model)
```
spec/system/prompt_tracker/file_search_evaluator_availability_spec.rb
  - Update to use VectorStoreService mocks instead of AssistantPlaygroundService
```

**Total Files to Modify:** ~20 files

---

## 8. Order of Operations

### Step 1: Create VectorStoreService (Non-Breaking)
**Goal:** Decouple vector store operations from AssistantPlaygroundService

1. Create `app/services/prompt_tracker/vector_store_service.rb`
2. Create `app/services/prompt_tracker/openai/vector_store_operations.rb`
3. Create specs for both services
4. Run tests to verify new services work

**Why First:** This is completely additive and doesn't break anything

### Step 2: Refactor LlmClientService Routing (Non-Breaking)
**Goal:** Extract routing logic into reusable private method

1. Extract routing logic in `LlmClientService` into private method `route_to_executor`
2. Update `LlmClientService.call` to use extracted routing method
3. Ensure consistent use of `ApiTypes.from_config(provider, api)` for API type detection
4. Update specs to verify routing still works correctly
5. Run tests to verify no regressions

**Why Second:** Prepares LlmClientService to be the single entry point for all API calls

### Step 3: Rename and Reorganize Conversation Handlers (Preparation)
**Goal:** Standardize naming conventions for conversation test handlers

1. Rename `TestRunners::ConversationTestHandler` → `TestRunners::SimulatedConversationRunner`
2. Rename `TestRunners::Openai::ResponseApiHandler` → `TestRunners::Openai::Responses::SimulatedConversationRunner`
3. Move `Openai::ConversationRunner` → `TestRunners::Openai::Assistants::SimulatedConversationRunner`
4. Update all references to renamed classes
5. Update `ConversationTestHandlerFactory` to use new names
6. Update specs for renamed handlers
7. Run tests to verify everything still works

**Why Third:** Standardizes naming before creating new sync service

### Step 4: Update Sync Service (Additive)
**Goal:** Create PromptVersions instead of Assistant records

1. Rename `SyncOpenaiAssistantsService` → `SyncOpenaiAssistantsToPromptVersionsService`
2. Update service to create PromptVersions with correct model_config structure:
   - `model_config[:api] = "assistants"`
   - `model_config[:assistant_id] = "asst_abc123"` (NEW field)
   - `model_config[:model] = "gpt-4o"` (actual model name)
3. Update `SyncOpenaiAssistantsController` to use renamed service
4. Update `app/views/prompt_tracker/testing/dashboard/index.html.erb` to reflect new behavior
5. Create specs for new sync service
6. Test syncing assistants to PromptVersions

**Why Fourth:** Prepares PromptVersion-based workflow before removing Assistant model

### Step 5: Simplify Test Runner Architecture (Preparation)
**Goal:** Remove runner routing logic

1. Update `app/jobs/prompt_tracker/run_test_job.rb`:
   - Remove `resolve_runner_class(testable)` method entirely
   - Always use `TestRunners::PromptVersionRunner`
   - Remove case statement routing logic
2. Update specs for RunTestJob
3. Run tests to verify all tests still work

**Why Fifth:** Simplifies architecture before removing AssistantRunner

### Step 6: Update Vector Store References (Preparation)
**Goal:** Switch from AssistantPlaygroundService to VectorStoreService

1. Update `app/controllers/prompt_tracker/api/vector_stores_controller.rb`
2. Update `app/views/prompt_tracker/evaluator_configs/forms/_file_search.html.erb`
3. Update `app/javascript/prompt_tracker/controllers/tools_config_controller.js`
4. Update `spec/system/prompt_tracker/file_search_evaluator_availability_spec.rb`
5. Run tests to verify vector store operations still work

**Why Sixth:** Removes dependency on AssistantPlaygroundService before deleting it

### Step 7: Remove Assistant Model (Breaking Changes)
**Goal:** Delete all Assistant-specific code

1. **Remove Routes** (config/routes.rb lines 90-149)
2. **Remove Controllers** (5 files)
3. **Remove Views** (15+ files)
4. **Remove Services** (4 files: AssistantPlaygroundService, old SyncOpenaiAssistantsService, AssistantRunner, old ConversationRunner)
5. **Remove Model** (app/models/prompt_tracker/openai/assistant.rb)
6. **Remove JavaScript** (assistant_playground_controller.js)
7. **Remove Factories** (spec/factories/prompt_tracker/openai/assistants.rb)
8. **Remove Specs** (10+ files)
9. **Remove Seeds** (2 files)
10. **Update Migration** (remove assistant table from schema)

**Why Seventh:** All dependencies removed, safe to delete

### Step 8: Update Configuration (Cleanup)
**Goal:** Remove separate openai_assistants configuration

1. Update `lib/prompt_tracker/configuration.rb`
   - Remove openai_assistants attr_accessor
   - Remove from initialize method
2. Update `test/dummy/config/initializers/prompt_tracker.rb`
   - Remove openai_assistants configuration block
3. Update `app/services/prompt_tracker/evaluators/base_normalized_evaluator.rb`
   - Remove Assistant from compatible_with array

**Why Eighth:** Final cleanup after all code removed

### Step 9: Database Migration (Final)
**Goal:** Drop the assistants table

1. Drop database: `cd test/dummy && RAILS_ENV=test bin/rails db:drop`
2. Recreate database: `RAILS_ENV=test bin/rails db:create`
3. Run migrations: `RAILS_ENV=test bin/rails db:migrate`
4. Run seeds: `RAILS_ENV=test bin/rails db:seed`
5. Run full test suite: `cd ../.. && bundle exec rspec`

**Why Ninth:** Ensures all code changes are complete before database changes

### Step 10: Documentation and Testing
**Goal:** Verify everything works

1. Run full test suite
2. Test manually in browser:
   - Sync assistants from OpenAI (should create PromptVersions)
   - Create PromptVersion with api: "assistants" and assistant_id
   - Select assistant from dropdown
   - Run conversation test
   - Verify vector stores work
3. Update README with new architecture
4. Create example seed file for Assistants API usage

---

## 9. Architectural Diagrams

### 9.1 Vector Store Service Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    VectorStoreService                        │
│                  (Provider-Agnostic Router)                  │
│                                                              │
│  Methods:                                                    │
│  - list_vector_stores(provider:)                            │
│  - create_vector_store(provider:, name:, file_ids:)         │
│  - list_vector_store_files(provider:, vector_store_id:)     │
│  - add_file_to_vector_store(provider:, vector_store_id:,    │
│                              file_id:)                       │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       │ Routes based on provider
                       │
         ┌─────────────┴─────────────┐
         │                           │
         ▼                           ▼
┌────────────────────┐      ┌────────────────────┐
│ Openai::           │      │ Future::           │
│ VectorStore        │      │ VectorStore        │
│ Operations         │      │ Operations         │
│                    │      │                    │
│ - Uses OpenAI      │      │ - Uses other       │
│   client           │      │   provider client  │
│ - Implements       │      │ - Implements       │
│   actual API calls │      │   actual API calls │
└────────────────────┘      └────────────────────┘
```

**Usage Example:**
```ruby
# In controller or view
VectorStoreService.list_vector_stores(provider: :openai)
# => Delegates to Openai::VectorStoreOperations.list_vector_stores

# Works from any context (Response API, Assistants API, etc.)
VectorStoreService.create_vector_store(
  provider: :openai,
  name: "Customer Support Docs",
  file_ids: ["file_abc123"]
)
```

### 9.2 Sync with OpenAI Creates PromptVersions

```
┌──────────────────────────────────────────────────────────────┐
│              Dashboard: "Sync with OpenAI" Button             │
│                                                               │
│  [Sync with OpenAI]  ← User clicks                          │
└───────────────────────┬───────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│   SyncOpenaiAssistantsToPromptVersionsService                │
│                                                               │
│  1. Fetch assistants from OpenAI API                         │
│  2. For each assistant, create PromptVersion:                │
│     - name = assistant.name                                   │
│     - system_prompt = assistant.instructions                  │
│     - model_config = {                                        │
│         provider: "openai",                                   │
│         api: "assistants",                                    │
│         assistant_id: "asst_abc123",  ← NEW field           │
│         model: "gpt-4o",              ← Actual model         │
│         tools: [...],                                         │
│         tool_resources: {...}                                 │
│       }                                                       │
└───────────────────────┬───────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│              PromptVersions Created                           │
│                                                               │
│  Users can now select these PromptVersions in:               │
│  - Generic Playground                                         │
│  - Test creation                                              │
│  - Dataset creation                                           │
│                                                               │
│  No dynamic dropdown - just regular PromptVersion selection  │
└───────────────────────────────────────────────────────────────┘
```

**Key Points:**
- **assistant_id** and **model** are separate fields in model_config
- An assistant has its own model configuration (e.g., "gpt-4o")
- The model field can override the assistant's default model at runtime
- No dynamic assistant dropdown - users select from synced PromptVersions

### 9.3 Unified Test Runner Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    User Runs Test                             │
│                                                               │
│  PromptVersion (testable):                                   │
│    model_config: {                                            │
│      provider: "openai",                                      │
│      api: "assistants",                                       │
│      assistant_id: "asst_abc123",  ← NEW field              │
│      model: "gpt-4o"               ← Actual model            │
│    }                                                          │
└───────────────────────────────────────────────────────────────┘
                       │
                       │ User clicks "Run Test"
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                    RunTestJob                                 │
│                                                               │
│  SIMPLIFIED: No routing logic needed!                        │
│                                                               │
│  runner = TestRunners::PromptVersionRunner.new(              │
│    test_run: test_run,                                        │
│    test: test,                                                │
│    testable: testable  # Always PromptVersion                │
│  )                                                            │
│  runner.run                                                   │
└───────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│         TestRunners::PromptVersionRunner                      │
│                                                               │
│  Delegates to ConversationTestHandlerFactory                 │
│  (no changes needed - already works)                         │
└───────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│         ConversationTestHandlerFactory                        │
│                                                               │
│  1. Reads model_config from PromptVersion                    │
│  2. Calls ApiTypes.from_config("openai", "assistants")       │
│     → Returns :openai_assistants                             │
│  3. Routes to appropriate handler:                           │
│     - :openai_responses → Openai::Responses::                │
│                            SimulatedConversationRunner        │
│     - :openai_assistants → Openai::Assistants::              │
│                             SimulatedConversationRunner       │
│     - :openai_chat_completions → Openai::ChatCompletions::   │
│                                   SimulatedConversationRunner │
└───────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  TestRunners::Openai::Assistants::SimulatedConversationRunner│
│  (renamed from Openai::ConversationRunner)                   │
│                                                               │
│  1. Extracts from model_config:                              │
│     - assistant_id = model_config[:assistant_id]  ← NEW!    │
│     - model = model_config[:model]                           │
│     - temperature, top_p, etc.                               │
│                                                               │
│  2. Extracts from dataset_row:                               │
│     - interlocutor_simulation_prompt                         │
│     - max_turns                                               │
│                                                               │
│  3. Creates thread via OpenAI Assistants API                 │
│  4. Runs multi-turn conversation                             │
│  5. Returns standardized output_data                         │
└───────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                    Test Run Result                            │
│                                                               │
│  output_data: {                                               │
│    rendered_prompt: "You are a medical assistant...",        │
│    model: "gpt-4o",                                           │
│    provider: "openai_assistants",                            │
│    messages: [...],                                           │
│    total_turns: 5,                                            │
│    metadata: {                                                │
│      assistant_id: "asst_abc123"                             │
│    }                                                          │
│  }                                                            │
└───────────────────────────────────────────────────────────────┘
```

**Key Architectural Improvements:**
1. **Single Testable Type:** Only PromptVersion exists (no Assistant model)
2. **No Runner Routing:** RunTestJob always uses PromptVersionRunner
3. **Correct model_config Structure:** assistant_id and model are separate fields
4. **Factory Routing:** ConversationTestHandlerFactory routes based on ApiTypes
5. **Standardized Naming:** All handlers follow SimulatedConversationRunner pattern

---

## 10. Implementation Details

### 10.1 VectorStoreService Implementation

```ruby
# app/services/prompt_tracker/vector_store_service.rb
module PromptTracker
  class VectorStoreService
    class VectorStoreError < StandardError; end

    class << self
      # List all vector stores for a provider
      #
      # @param provider [Symbol] the provider (:openai, etc.)
      # @return [Array<Hash>] array of vector store hashes
      def list_vector_stores(provider:)
        operations_class = operations_class_for(provider)
        operations_class.list_vector_stores
      end

      # Create a new vector store
      #
      # @param provider [Symbol] the provider
      # @param name [String] vector store name
      # @param file_ids [Array<String>] file IDs to add
      # @return [Hash] created vector store data
      def create_vector_store(provider:, name:, file_ids: [])
        operations_class = operations_class_for(provider)
        operations_class.create_vector_store(name: name, file_ids: file_ids)
      end

      # List files in a vector store
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @return [Array<Hash>] array of file hashes
      def list_vector_store_files(provider:, vector_store_id:)
        operations_class = operations_class_for(provider)
        operations_class.list_vector_store_files(vector_store_id: vector_store_id)
      end

      # Add a file to a vector store
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @param file_id [String] the file ID to add
      # @return [Hash] result
      def add_file_to_vector_store(provider:, vector_store_id:, file_id:)
        operations_class = operations_class_for(provider)
        operations_class.add_file_to_vector_store(
          vector_store_id: vector_store_id,
          file_id: file_id
        )
      end

      private

      # Get the operations class for a provider
      #
      # @param provider [Symbol] the provider
      # @return [Class] the operations class
      def operations_class_for(provider)
        case provider.to_sym
        when :openai
          Openai::VectorStoreOperations
        else
          raise VectorStoreError, "Unsupported provider: #{provider}"
        end
      end
    end
  end
end
```

### 10.2 Openai::VectorStoreOperations Implementation

```ruby
# app/services/prompt_tracker/openai/vector_store_operations.rb
module PromptTracker
  module Openai
    class VectorStoreOperations
      class << self
        # List all vector stores
        #
        # @return [Array<Hash>] array of vector store hashes
        def list_vector_stores
          client = build_client
          response = client.vector_stores.list
          response["data"] || []
        rescue => e
          Rails.logger.error "Failed to list vector stores: #{e.message}"
          []
        end

        # Create a new vector store
        #
        # @param name [String] vector store name
        # @param file_ids [Array<String>] file IDs to add
        # @return [Hash] created vector store data
        def create_vector_store(name:, file_ids: [])
          client = build_client
          params = { name: name }
          params[:file_ids] = file_ids if file_ids.any?

          client.vector_stores.create(parameters: params)
        rescue => e
          Rails.logger.error "Failed to create vector store: #{e.message}"
          { error: e.message }
        end

        # List files in a vector store
        #
        # @param vector_store_id [String] the vector store ID
        # @return [Array<Hash>] array of file hashes
        def list_vector_store_files(vector_store_id:)
          client = build_client
          response = client.vector_store_files.list(vector_store_id: vector_store_id)
          response["data"] || []
        rescue => e
          Rails.logger.error "Failed to list vector store files: #{e.message}"
          []
        end

        # Add a file to a vector store
        #
        # @param vector_store_id [String] the vector store ID
        # @param file_id [String] the file ID to add
        # @return [Hash] result
        def add_file_to_vector_store(vector_store_id:, file_id:)
          client = build_client
          client.vector_store_files.create(
            vector_store_id: vector_store_id,
            parameters: { file_id: file_id }
          )
        rescue => e
          Rails.logger.error "Failed to add file to vector store: #{e.message}"
          { error: e.message }
        end

        private

        # Build OpenAI client
        #
        # @return [OpenAI::Client] the client
        def build_client
          api_key = PromptTracker.configuration.api_keys[:openai]
          raise "OpenAI API key not configured" if api_key.blank?

          ::OpenAI::Client.new(access_token: api_key)
        end
      end
    end
  end
end
```

### 10.3 LlmClientService Routing Refactor

**Current routing logic (lines 72-94):**
```ruby
# Determine the API type using ApiTypes module
api_type = ApiTypes.from_config(provider, api)

# Route to OpenAI Responses API
if api_type == :openai_responses
  return OpenaiResponseService.call(...)
end

# Route to OpenAI Assistants API
if api_type == :openai_assistants
  return OpenaiAssistantService.call(
    assistant_id: model,  # ❌ WRONG - should use assistant_id from options
    prompt: prompt,
    timeout: options[:timeout] || 60
  )
end

# Continue to RubyLLM for other APIs...
```

**Refactored approach:**
1. Extract routing logic into private method
2. Fix assistant_id parameter (should come from options, not model)
3. Keep LlmClientService as single entry point

```ruby
# app/services/prompt_tracker/llm_client_service.rb
def self.call(provider:, api:, model:, prompt:, temperature: 0.7, max_tokens: nil, response_schema: nil, **options)
  api_type = ApiTypes.from_config(provider, api)

  # Route to specialized services for OpenAI Responses/Assistants APIs
  if api_type == :openai_responses || api_type == :openai_assistants
    return route_to_specialized_service(
      api_type: api_type,
      model: model,
      prompt: prompt,
      temperature: temperature,
      max_tokens: max_tokens,
      **options
    )
  end

  # Continue with RubyLLM for standard chat completions...
end

private

def self.route_to_specialized_service(api_type:, model:, prompt:, temperature:, max_tokens:, **options)
  case api_type
  when :openai_responses
    OpenaiResponseService.call(
      model: model,
      user_prompt: prompt,
      system_prompt: options[:system_prompt],
      tools: options[:tools] || [],
      temperature: temperature,
      max_tokens: max_tokens,
      **options.except(:system_prompt, :tools)
    )
  when :openai_assistants
    OpenaiAssistantService.call(
      assistant_id: options[:assistant_id],  # ✅ CORRECT - from options
      prompt: prompt,
      timeout: options[:timeout] || 60
    )
  end
end
```

### 10.4 Assistants::SimulatedConversationRunner Implementation

```ruby
# app/services/prompt_tracker/test_runners/openai/assistants/simulated_conversation_runner.rb
module PromptTracker
  module TestRunners
    module Openai
      module Assistants
        # Handler for OpenAI Assistants API.
        #
        # This handler executes conversational tests using the OpenAI Assistants API
        # with threads, runs, and polling. It works with PromptVersion where
        # model_config[:api] == "assistants".
        #
        # IMPORTANT: assistant_id is extracted from model_config[:assistant_id] (NOT model_config[:model])
        #
        # @example Conversational execution
        #   handler = SimulatedConversationRunner.new(model_config: config, use_real_llm: true)
        #   output_data = handler.execute(
        #     mode: :conversational,
        #     interlocutor_prompt: "You are a patient with headache.",
        #     max_turns: 5
        #   )
        #
        class SimulatedConversationRunner < TestRunners::SimulatedConversationRunner
          # Execute the test
          #
          # @param params [Hash] execution parameters
          # @return [Hash] output_data with standardized format
          def execute(params)
            start_time = Time.current

            # Extract assistant_id from model_config (NEW field!)
            assistant_id = model_config[:assistant_id]
            raise ArgumentError, "assistant_id is required in model_config[:assistant_id]" if assistant_id.blank?

            # Extract conversation parameters
            interlocutor_prompt = params[:interlocutor_prompt]
            max_turns = params[:max_turns] || 5

            raise ArgumentError, "interlocutor_prompt is required" if interlocutor_prompt.blank?

            # Run the conversation (this service handles thread creation, polling, etc.)
            conversation_result = run_assistant_conversation(
              assistant_id: assistant_id,
              interlocutor_prompt: interlocutor_prompt,
              max_turns: max_turns
            )

            response_time_ms = ((Time.current - start_time) * 1000).to_i

            # Build unified output_data structure
            {
              rendered_prompt: conversation_result[:instructions] || "",
              model: conversation_result[:model] || model_config[:model],
              provider: "openai_assistants",
              messages: conversation_result[:messages] || [],
              total_turns: conversation_result[:total_turns],
              status: conversation_result[:status] || "completed",
              thread_id: conversation_result[:thread_id],
              response_time_ms: response_time_ms,
              metadata: {
                assistant_id: assistant_id,
                max_turns: max_turns,
                interlocutor_prompt: interlocutor_prompt
              }
            }
          end

          private

          def run_assistant_conversation(assistant_id:, interlocutor_prompt:, max_turns:)
            # Implementation: creates thread, runs conversation, polls for responses
            # This is the logic currently in Openai::ConversationRunner
            # ... (implementation details)
          end
        end
      end
    end
  end
end
```

### 10.5 ConversationTestHandlerFactory Update

```ruby
# app/services/prompt_tracker/conversation_test_handler_factory.rb
# Update the executor_class_for method (lines 73-96)

def executor_class_for(model_config)
  config = model_config.with_indifferent_access
  api_type = ApiTypes.from_config(config[:provider], config[:api])

  case api_type
  when :openai_responses
    # OpenAI Response API has special stateful conversation handling
    TestRunners::Openai::Responses::SimulatedConversationRunner  # RENAMED
  when :openai_chat_completions
    # OpenAI Chat Completions API
    TestRunners::Openai::ChatCompletions::SimulatedConversationRunner  # RENAMED
  when :openai_assistants  # UPDATED: was :openai_assistants_api
    # OpenAI Assistants API with threads and runs
    TestRunners::Openai::Assistants::SimulatedConversationRunner  # NEW + RENAMED
  when :anthropic_messages
    # Anthropic uses the same completion pattern as OpenAI
    TestRunners::Anthropic::Messages::SimulatedConversationRunner  # RENAMED
  when :google_gemini
    # Google Gemini uses the same completion pattern
    TestRunners::Google::Gemini::SimulatedConversationRunner  # RENAMED
  else
    # Fallback to ChatCompletionHandler for unknown API types
    TestRunners::Openai::ChatCompletions::SimulatedConversationRunner  # RENAMED
  end
end
```

### 10.6 SyncOpenaiAssistantsToPromptVersionsService Implementation

```ruby
# app/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service.rb
module PromptTracker
  # Service to sync OpenAI Assistants to Prompts and PromptVersions.
  #
  # Fetches assistants from OpenAI API and creates:
  # - One Prompt per assistant (with slug based on assistant_id)
  # - One PromptVersion per prompt (version_number: 1)
  # - model_config[:api] = "assistants"
  # - model_config[:assistant_id] = "asst_abc123" (NEW field)
  # - model_config[:model] = "gpt-4o" (actual model name)
  #
  # This creates a 1:1:1 relationship: Assistant → Prompt → PromptVersion
  #
  class SyncOpenaiAssistantsToPromptVersionsService
    attr_reader :created_prompts, :created_versions, :errors

    def initialize
      @created_prompts = []
      @created_versions = []
      @errors = []
    end

    def call
      fetch_assistants_from_openai.each do |assistant_data|
        create_prompt_and_version_from_assistant(assistant_data)
      end

      {
        success: errors.empty?,
        created_count: created_prompts.count,
        created_prompts: created_prompts,
        created_versions: created_versions,
        errors: errors
      }
    end

    private

    def fetch_assistants_from_openai
      client = build_client
      response = client.assistants.list

      response["data"] || []
    rescue SyncError
      raise
    rescue => e
      @errors << "Failed to fetch assistants: #{e.message}"
      []
    end

    def create_prompt_and_version_from_assistant(assistant_data)
      assistant_id = assistant_data["id"]
      assistant_name = assistant_data["name"] || assistant_id

      # Create the Prompt
      prompt = Prompt.create!(
        name: assistant_name,
        slug: generate_slug(assistant_id),
        description: assistant_data["description"] || "Synced from OpenAI Assistant",
        category: "assistant"
      )

      # Create the PromptVersion
      version = prompt.prompt_versions.create!(
        system_prompt: assistant_data["instructions"] || "",
        user_prompt: "{{user_message}}",
        version_number: 1,
        status: "draft",
        model_config: build_model_config(assistant_data),
        notes: "Synced from OpenAI Assistant: #{assistant_name}"
      )

      @created_prompts << prompt
      @created_versions << version
    rescue => e
      @errors << "Failed to create prompt/version for #{assistant_name}: #{e.message}"
    end

    def generate_slug(assistant_id)
      # "asst_abc123" → "assistant_asst_abc123"
      base_slug = "assistant_#{assistant_id}"

      slug = base_slug
      counter = 1
      while Prompt.exists?(slug: slug)
        slug = "#{base_slug}_#{counter}"
        counter += 1
      end

      slug
    end

    def build_model_config(assistant_data)
      {
        provider: "openai",
        api: "assistants",
        assistant_id: assistant_data["id"],  # NEW: Store assistant_id here
        model: assistant_data["model"],      # Actual model name (e.g., "gpt-4o")
        temperature: assistant_data["temperature"] || 0.7,
        top_p: assistant_data["top_p"] || 1.0,
        tools: assistant_data["tools"] || [],
        tool_resources: assistant_data["tool_resources"] || {},
        metadata: {
          name: assistant_data["name"],
          description: assistant_data["description"],
          synced_at: Time.current.iso8601
        }
      }
    end

    def build_client
      require "openai"

      api_key = PromptTracker.configuration.openai_assistants_api_key ||
                PromptTracker.configuration.api_key_for(:openai) ||
                ENV["OPENAI_API_KEY"]
      raise SyncError, "OpenAI API key not configured" if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end
  end
end
```

### 10.7 RunTestJob Simplification

```ruby
# app/jobs/prompt_tracker/run_test_job.rb
# SIMPLIFIED: Remove routing logic entirely

module PromptTracker
  class RunTestJob < ApplicationJob
    queue_as :prompt_tracker_tests
    sidekiq_options retry: false

    # Execute the test run
    #
    # @param test_run_id [Integer] ID of the TestRun to execute
    # @param use_real_llm [Boolean] whether to use real LLM API or mock
    def perform(test_run_id, use_real_llm: false)
      Rails.logger.info "🚀 RunTestJob started for test_run #{test_run_id}"

      test_run = TestRun.find(test_run_id)
      test = test_run.test
      testable = test.testable

      # SIMPLIFIED: All testables are PromptVersion - no routing needed!
      runner = TestRunners::PromptVersionRunner.new(
        test_run: test_run,
        test: test,
        testable: testable,
        use_real_llm: use_real_llm
      )
      runner.run

      Rails.logger.info "✅ RunTestJob completed for test_run #{test_run_id}"
    end

    # REMOVED: resolve_runner_class method no longer needed
  end
end
```

### 10.8 Playground Model Config Form Update

```erb
<!-- app/views/prompt_tracker/testing/playground/_model_config_form.html.erb -->
<!-- Update to use assistant_id field (not model field) -->

<%# Assistant ID Input - shown when api: "assistants" is selected %>
<div class="mb-3" id="assistant-id-container"
     data-playground-target="assistantIdContainer"
     style="display: none;">
  <label for="assistant-id" class="form-label">Assistant ID</label>
  <input
    type="text"
    id="assistant-id"
    class="form-control"
    data-playground-target="assistantId"
    data-action="input->playground#onModelConfigChange"
    placeholder="asst_abc123"
  >
  <div class="form-text">
    Enter the OpenAI Assistant ID (e.g., asst_abc123).
    This will be stored in model_config[:assistant_id].
  </div>
  <div class="form-text text-muted">
    Tip: Use "Sync with OpenAI" on the dashboard to create PromptVersions from your assistants.
  </div>
</div>

<%# Model Field - shown for all APIs (including assistants) %>
<div class="mb-3" id="model-container"
     data-playground-target="modelContainer">
  <label for="model-name" class="form-label">Model</label>
  <input
    type="text"
    id="model-name"
    class="form-control"
    data-playground-target="modelName"
    data-action="input->playground#onModelConfigChange"
    placeholder="gpt-4o"
  >
  <div class="form-text">
    Model name (e.g., gpt-4o, gpt-4-turbo).
    For Assistants API, this can override the assistant's default model.
  </div>
</div>
```

### 10.9 Playground JavaScript Update

```javascript
// app/javascript/prompt_tracker/controllers/playground_controller.js
// Update to show/hide assistant_id field based on API selection

// Action: API change - update UI based on selected API
onApiChange() {
  if (!this.hasModelProviderTarget || !this.hasModelApiTarget) return

  const provider = this.modelProviderTarget.value
  const api = this.modelApiTarget.value
  const providerData = JSON.parse(this.modelProviderTarget.dataset.providerData || '{}')
  const data = providerData[provider]

  if (!data) return

  // Show/hide assistant_id field based on API selection
  if (api === 'assistants') {
    this.showAssistantIdField()
  } else {
    this.hideAssistantIdField()
  }

  // Update models for selected API
  const models = data.models_by_api[api] || []
  this.updateModelDropdown(models)

  // Get tools for selected API
  const tools = data.tools_by_api?.[api] || []

  // Update API description and tools
  const apiConfig = data.apis.find(a => a.key === api)
  this.updateApiSpecificUI(apiConfig, tools)
}

// Show assistant_id field
showAssistantIdField() {
  if (this.hasAssistantIdContainerTarget) {
    this.assistantIdContainerTarget.style.display = ''
  }
}

// Hide assistant_id field
hideAssistantIdField() {
  if (this.hasAssistantIdContainerTarget) {
    this.assistantIdContainerTarget.style.display = 'none'
  }
}
```

**Note:** No dynamic assistant dropdown needed - users select from synced PromptVersions in the regular PromptVersion selector.

---

## 11. Testing Strategy

### 11.1 Unit Tests

**LlmClientService (refactored routing):**
- Test routing to OpenaiResponseService for :openai_responses
- Test routing to OpenaiAssistantService for :openai_assistants
- Test routing to RubyLLM for other API types
- Test assistant_id parameter is passed correctly from options (not from model)
- Mock all executor classes

**VectorStoreService:**
- Test routing to correct provider operations class
- Test error handling for unsupported providers
- Mock provider operations classes

**Openai::VectorStoreOperations:**
- Test each method with mocked OpenAI client
- Test error handling
- Test response parsing

**Assistants::SimulatedConversationRunner:**
- Test execute method with mocked conversation logic
- Test assistant_id extraction from model_config[:assistant_id] (NOT model_config[:model])
- Test output_data structure
- Test error handling for missing parameters

**SyncOpenaiAssistantsToPromptVersionsService:**
- Test fetching assistants from OpenAI API
- Test creating PromptVersions with correct model_config structure
- Test assistant_id stored in model_config[:assistant_id]
- Test model stored in model_config[:model]
- Test error handling

**RunTestJob:**
- Test simplified logic (no routing)
- Test always uses PromptVersionRunner
- Test with different model_config[:api] values

### 11.2 Integration Tests

**Playground:**
- Test API selector shows "Assistants" option
- Test assistant_id field appears when Assistants API selected
- Test model field always visible (can override assistant's model)
- Test saving model_config with both assistant_id and model

**Conversation Tests:**
- Create PromptVersion with api: "assistants", assistant_id: "asst_123", model: "gpt-4o"
- Create conversational dataset
- Run test and verify Assistants::SimulatedConversationRunner is used
- Verify output_data structure matches expected format

**Sync with OpenAI:**
- Test syncing assistants creates PromptVersions (not Assistant records)
- Test model_config structure is correct
- Test multiple assistants sync correctly

### 11.3 System Tests

**End-to-End Flow:**
1. Sync assistants from OpenAI (creates PromptVersions)
2. Select synced PromptVersion in playground
3. Verify model_config shows assistant_id and model
4. Create conversational dataset
5. Create test with evaluators
6. Run test (uses PromptVersionRunner → Assistants::SimulatedConversationRunner)
7. Verify results display correctly

---

## 12. Risks and Mitigation

### Risk 1: Breaking Existing Assistant Data
**Impact:** High
**Probability:** High
**Mitigation:**
- No backward compatibility required (per requirements)
- Document migration path for users with existing Assistant data
- Provide script to convert Assistant records to PromptVersions (optional)

### Risk 2: model_config Structure Confusion
**Impact:** High
**Probability:** Medium
**Mitigation:**
- Clear documentation: assistant_id goes in model_config[:assistant_id], NOT model_config[:model]
- Update all code examples in plan to use correct structure
- Add validation to ensure assistant_id is present when api: "assistants"
- Helper text in UI explaining the two fields

### Risk 3: Missing Edge Cases in Assistants::SimulatedConversationRunner
**Impact:** Medium
**Probability:** Medium
**Mitigation:**
- Comprehensive unit tests
- Copy logic from existing Openai::ConversationRunner
- Test with real OpenAI API in development
- Verify thread creation, polling, and response handling

### Risk 4: Routing Logic Duplication During Migration
**Impact:** Medium
**Probability:** High
**Mitigation:**
- Create ApiExecutorFactory first (Phase 1)
- Update all services to use factory in same phase
- Remove old routing logic immediately after factory is tested
- Ensure ApiTypes.from_config is used consistently

### Risk 5: Naming Inconsistency During Refactoring
**Impact:** Low
**Probability:** Medium
**Mitigation:**
- Follow strict naming pattern: {Provider}::{ApiName}::SimulatedConversationRunner
- Update all handlers in same phase (Phase 3)
- Search codebase for old names after renaming
- Update all references in tests and documentation

### Risk 6: Vector Store Operations Break During Migration
**Impact:** High
**Probability:** Low
**Mitigation:**
- Create VectorStoreService first (non-breaking)
- Test thoroughly before removing AssistantPlaygroundService
- Keep both services temporarily during migration

### Risk 7: RunTestJob Breaks After Simplification
**Impact:** High
**Probability:** Low
**Mitigation:**
- Verify all testables are PromptVersion before removing routing
- Update tests to match new simplified logic
- Test with different model_config[:api] values
- Ensure ConversationTestHandlerFactory handles all API types

---

## 13. Success Criteria

✅ **Phase 1 Complete When:**
- VectorStoreService and Openai::VectorStoreOperations created and tested
- LlmClientService routing refactored (extracted into private method)
- assistant_id parameter fixed in LlmClientService (from options, not model)
- All tests pass
- Vector store operations work from any context

✅ **Phase 2 Complete When:**
- SyncOpenaiAssistantsToPromptVersionsService created and tested
- Service creates PromptVersions (not Assistant records)
- model_config structure correct (assistant_id in [:assistant_id], model in [:model])
- Tests pass

✅ **Phase 3 Complete When:**
- All conversation handlers renamed to SimulatedConversationRunner pattern
- TestRunners::Openai::Assistants::SimulatedConversationRunner created
- TestRunners::Openai::Responses::SimulatedConversationRunner renamed
- TestRunners::SimulatedConversationRunner base class renamed
- ConversationTestHandlerFactory updated with new names
- All tests pass

✅ **Phase 4 Complete When:**
- RunTestJob simplified (no routing logic)
- Always uses PromptVersionRunner
- Tests updated to match new behavior
- All tests pass

✅ **Phase 5 Complete When:**
- Generic playground shows Assistants API option
- Assistant ID field appears when Assistants API selected
- Model field always visible (can override assistant's model)
- Can create PromptVersion with api: "assistants", assistant_id, and model
- Can run conversation tests successfully

✅ **Phase 6 Complete When:**
- All vector store references use VectorStoreService
- No references to AssistantPlaygroundService remain
- Tests pass

✅ **Phase 7 Complete When:**
- All Assistant-specific code deleted (model, controllers, views, services, specs)
- AssistantRunner deleted
- Openai::ConversationRunner moved to Assistants::SimulatedConversationRunner
- No compilation errors
- No broken routes
- Database migration updated

✅ **Phase 8 Complete When:**
- Configuration cleaned up
- No references to openai_assistants config
- Tests pass

✅ **Phase 9 Complete When:**
- Database recreated successfully
- All migrations run
- Seeds run without errors
- Full test suite passes

✅ **Phase 10 Complete When:**
- Documentation updated
- Manual testing complete
- Example seeds created
- README reflects new architecture
- All architectural decisions documented

---

## 14. Timeline Estimate

- **Phase 1:** 2-3 hours (VectorStoreService + LlmClientService refactor)
- **Phase 2:** 2-3 hours (SyncOpenaiAssistantsToPromptVersionsService)
- **Phase 3:** 3-4 hours (Rename all conversation handlers)
- **Phase 4:** 1-2 hours (Simplify RunTestJob)
- **Phase 5:** 4-6 hours (Playground integration with assistant_id field)
- **Phase 6:** 1-2 hours (Vector store updates)
- **Phase 7:** 2-3 hours (Delete Assistant code)
- **Phase 8:** 1 hour (Configuration cleanup)
- **Phase 9:** 1 hour (Database migration)
- **Phase 10:** 2-3 hours (Documentation and testing)

**Total Estimated Time:** 19-29 hours

**Note:** Timeline includes:
- VectorStoreService creation
- LlmClientService routing refactor
- Comprehensive handler renaming
- model_config structure changes
- Additional testing requirements

---

## 15. Next Steps

1. **Review this plan** with stakeholders
2. **Verify architectural decisions:**
   - model_config[:assistant_id] for assistant ID (NOT model_config[:model])
   - model_config[:model] for actual model name
   - Sync creates PromptVersions (not dynamic dropdown)
   - LlmClientService is single entry point for all API calls (no separate factory)
   - SimulatedConversationRunner naming pattern
3. **Get approval** to proceed
4. **Create feature branch** for refactoring
5. **Start with Phase 1** (VectorStoreService + LlmClientService refactor)
6. **Commit after each phase** for easy rollback
7. **Test thoroughly** at each step
8. **Document any deviations** from the plan

---

## Appendix A: Key Architectural Decisions

### Decision 1: Assistant ID in model_config[:model]
**Rationale:** Reuses existing field instead of adding new field. Keeps model_config structure consistent across all APIs.

### Decision 2: No Backward Compatibility
**Rationale:** Per requirements, breaking changes are acceptable. Simplifies migration and reduces technical debt.

### Decision 3: VectorStoreService as Routing Service
**Rationale:** Follows existing pattern (LlmClientService). Makes it easy to add new providers in the future.

### Decision 4: Preserve ConversationRunner
**Rationale:** ConversationRunner is well-tested and works correctly. No need to rewrite it.

### Decision 5: AssistantHandler vs Extending ChatCompletionHandler
**Rationale:** Assistants API is fundamentally different (threads, runs, polling). Separate handler is clearer.

---

**End of Plan**
