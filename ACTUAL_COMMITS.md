# Actual Commits to Be Created

Based on the **actual git status**, here are the commits that will be created:

## Already Committed
✅ **Commit 1** (ed10145): Add vector store limit validation for OpenAI Responses API

## To Be Created (6 commits)

### Commit 2: Create VectorStoreService infrastructure
**New files:**
- `app/services/prompt_tracker/vector_store_service.rb`
- `app/services/prompt_tracker/openai/` (directory with vector_store_operations.rb)
- `spec/services/prompt_tracker/vector_store_service_spec.rb`
- `spec/services/prompt_tracker/openai/vector_store_operations_spec.rb`

**Purpose:** Provider-agnostic service for vector store operations

---

### Commit 3: Create sync service for Assistants
**New files:**
- `app/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service.rb`
- `spec/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service_spec.rb`

**Purpose:** Import OpenAI Assistants as PromptVersions instead of Assistant records

---

### Commit 4: Update dashboard to remove Assistant option
**Modified files:**
- `app/views/prompt_tracker/testing/dashboard/_create_testable_modal.html.erb`
- `app/views/prompt_tracker/testing/dashboard/index.html.erb`
- `app/controllers/prompt_tracker/testing/dashboard_controller.rb`

**Deleted files:**
- `app/views/prompt_tracker/testing/dashboard/_assistant_list.html.erb`

**Purpose:** Remove separate "Create Assistant" UI option

---

### Commit 5: Extract Response API tools partials
**Modified files:**
- `app/views/prompt_tracker/testing/playground/_response_api_tools.html.erb`

**New files:**
- `app/views/prompt_tracker/testing/playground/response_api_tools/_functions_configuration_panel.html.erb`
- `app/views/prompt_tracker/testing/playground/response_api_tools/_create_vector_store_modal.html.erb`
- `app/views/prompt_tracker/testing/playground/response_api_tools/_vector_store_files_modal.html.erb`

**Purpose:** Refactor monolithic view into focused partials

---

### Commit 6: Update vector store controller
**Modified files:**
- `app/controllers/prompt_tracker/api/vector_stores_controller.rb`

**Purpose:** Use VectorStoreService instead of AssistantPlaygroundService

---

## How to Execute

```bash
chmod +x create_commits.sh
./create_commits.sh
git log --oneline -7
```

## Result
You will have **7 total commits** (1 existing + 6 new) that are clean, focused, and ready to push.

