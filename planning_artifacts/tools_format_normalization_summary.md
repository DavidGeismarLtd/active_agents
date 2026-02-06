# Tools Format Normalization - Implementation Summary

## ✅ Issues Addressed

### Issue 1: Fixed Failing System Specs - Route Helper ✅

**Problem:** All 13 system specs in `spec/system/prompt_tracker/playground_tools_spec.rb` were failing with:
```
NoMethodError: undefined method `testing_prompt_prompt_version_playground_path'
```

**Solution:** Updated all route helper calls to include the `prompt_tracker.` prefix:
- ❌ Before: `testing_prompt_prompt_version_playground_path(prompt, version)`
- ✅ After: `prompt_tracker.testing_prompt_prompt_version_playground_path(prompt, version)`

**Files Modified:**
- `spec/system/prompt_tracker/playground_tools_spec.rb` - Fixed 10 occurrences of the route helper

---

### Issue 2: Enforce Correct Tools Format When Syncing OpenAI Assistants ✅

**Problem:** When `SyncOpenaiAssistantsToPromptVersionsService` imports assistants from OpenAI API, the `tools` field was stored in OpenAI's hash format instead of our internal string array format.

**OpenAI Format (from API):**
```ruby
[
  { "type" => "file_search", "file_search" => { "ranking_options" => { "ranker" => "auto" } } },
  { "type" => "code_interpreter" }
]
```

**Our Internal Format (normalized):**
```ruby
["file_search", "code_interpreter"]
```

**Why Normalize?**
1. **Consistency** - Matches our seed data format and internal conventions
2. **Simplicity** - String arrays are easier to work with than nested hashes
3. **Separation of Concerns** - Tool-specific configuration belongs in `tool_resources`, not in the `tools` array
4. **View Compatibility** - The view layer (`ModelConfigHelper`) already expects this format

---

## 🏗️ Solution Architecture

### 1. Created ModelConfigNormalizer Class

**File:** `app/services/prompt_tracker/openai/assistants/model_config_normalizer.rb`

**Responsibilities:**
- Takes raw OpenAI assistant data as input
- Normalizes `tools` array from hash format to string array
- Preserves `tool_resources` as-is (contains tool-specific configuration)
- Handles mixed formats (hash + string) gracefully
- Filters out nil/invalid tool entries
- Provides default values for temperature and top_p

**Key Method:**
```ruby
def normalize_tools
  raw_tools = assistant_data["tools"] || []
  
  raw_tools.map do |tool|
    # Extract type from hash or use string directly
    tool.is_a?(Hash) ? tool["type"] : tool.to_s
  end.compact
end
```

### 2. Updated SyncOpenaiAssistantsToPromptVersionsService

**File:** `app/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service.rb`

**Changes:**
- Replaced inline `build_model_config` logic with call to `ModelConfigNormalizer.normalize`
- Simplified the service by delegating normalization responsibility

**Before:**
```ruby
def build_model_config(assistant_data)
  {
    provider: "openai",
    api: "assistants",
    tools: assistant_data["tools"] || [],  # ← Stored raw hash format
    # ...
  }
end
```

**After:**
```ruby
def build_model_config(assistant_data)
  Openai::Assistants::ModelConfigNormalizer.normalize(assistant_data)
end
```

### 3. Comprehensive Test Coverage

**New Spec:** `spec/services/prompt_tracker/openai/assistants/model_config_normalizer_spec.rb`

**Test Cases (10 contexts):**
1. ✅ Normalizes tools from OpenAI hash format to string array
2. ✅ Preserves tool_resources as-is
3. ✅ Sets correct provider and api
4. ✅ Includes assistant_id and model configuration
5. ✅ Includes metadata with sync timestamp
6. ✅ Handles legacy string format (no-op)
7. ✅ Handles mixed tool formats (hash + string)
8. ✅ Returns empty array when no tools
9. ✅ Filters out nil and invalid tool entries
10. ✅ Uses default values for temperature and top_p

**Updated Spec:** `spec/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service_spec.rb`

**Changes:**
- Updated expectation on line 175 to expect normalized string array
- Added new context "with complex tools including file_search" to verify normalization of file_search tools with ranking options

---

## 📊 Canonical Tools Format Across APIs

### Decision: Use String Array Format

**Format:** `["file_search", "code_interpreter", "functions"]`

**Applies to:**
- ✅ OpenAI Chat Completions API
- ✅ OpenAI Responses API
- ✅ OpenAI Assistants API
- ✅ Anthropic Messages API

**Tool-Specific Configuration:**
- Stored separately in `tool_config` (for Responses API) or `tool_resources` (for Assistants API)
- Example:
  ```ruby
  {
    "tools" => ["file_search"],
    "tool_resources" => {
      "file_search" => {
        "vector_store_ids" => ["vs_123", "vs_456"]
      }
    }
  }
  ```

---

## 🧪 What to Test

### 1. Run the Normalizer Specs
```bash
bundle exec rspec spec/services/prompt_tracker/openai/assistants/model_config_normalizer_spec.rb
```

**Expected:** 10 examples, 0 failures

### 2. Run the Sync Service Specs
```bash
bundle exec rspec spec/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service_spec.rb
```

**Expected:** All specs pass with normalized tools format

### 3. Run the System Specs (Tools Selection)
```bash
bundle exec rspec spec/system/prompt_tracker/playground_tools_spec.rb
```

**Expected:** 13 examples, 0 failures (route helper issue fixed)

### 4. Manual Testing - Sync OpenAI Assistants

1. **Navigate to Testing Dashboard:**
   - Go to `/prompt_tracker/testing`
   - Click "Sync OpenAI Assistants" button

2. **Verify Synced Assistant:**
   - Open a synced assistant in the playground
   - Check that tools are pre-selected correctly
   - Inspect `model_config` in Rails console:
     ```ruby
     version = PromptTracker::PromptVersion.last
     version.model_config["tools"]
     # Should be: ["file_search", "code_interpreter"] (string array)
     # NOT: [{"type"=>"file_search", ...}] (hash array)
     ```

3. **Test Tool Toggling:**
   - Toggle tools on/off in the playground
   - Verify checkboxes and active states work correctly
   - Verify tool configuration panels show/hide correctly

---

## 📁 Files Created/Modified

### Created:
1. ✅ `app/services/prompt_tracker/openai/assistants/model_config_normalizer.rb` - Normalizer class
2. ✅ `spec/services/prompt_tracker/openai/assistants/model_config_normalizer_spec.rb` - Normalizer specs
3. ✅ `spec/system/prompt_tracker/playground_tools_spec.rb` - System specs for tools selection (Task 2)
4. ✅ `planning_artifacts/tools_format_normalization_summary.md` - This document

### Modified:
1. ✅ `app/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service.rb` - Use normalizer
2. ✅ `spec/services/prompt_tracker/sync_openai_assistants_to_prompt_versions_service_spec.rb` - Updated expectations
3. ✅ `app/views/prompt_tracker/testing/playground/_tools_panel.html.erb` - Fixed tool format conversion (Task 1)

---

## 🎯 Next Steps (Task 3 - Pending)

**Task 3: Refactor Tools Panel View - Extract Styles and Ruby Logic**

This task is still pending. It involves:
1. Extract CSS styles from `_tools_panel.html.erb` to dedicated stylesheet
2. Extract Ruby logic (lines 11-26) into a helper method
3. Keep the view thin with minimal logic

This will be addressed in a separate PR/commit.

