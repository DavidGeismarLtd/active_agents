# Migration Execution Checklist

Use this checklist to track progress during the migration.

## Pre-Migration

- [ ] Read `model_config_provider_api_split.md` (full plan)
- [ ] Read `QUICK_START.md` (quick overview)
- [ ] Review the three Mermaid diagrams for visual understanding
- [ ] Create a backup of the database
- [ ] Create a new git branch: `git checkout -b fix/model-config-provider-api-split`

---

## Phase 1: Backward Compatible Readers

### Step 1: Add Helper Methods to PromptVersion
- [ ] Open `app/models/prompt_tracker/prompt_version.rb`
- [ ] Add `extract_provider` private method (lines ~480)
- [ ] Add `extract_api` private method (lines ~500)
- [ ] Run: `bundle exec rspec spec/models/prompt_tracker/prompt_version_spec.rb`

### Step 2: Update api_type Method
- [ ] Update `api_type` method to use `extract_provider` and `extract_api`
- [ ] Use `ApiTypes.from_config(provider, api)` for conversion
- [ ] Test with old format: `{ "provider" => "openai_responses" }`
- [ ] Test with new format: `{ "provider" => "openai", "api" => "response_api" }`
- [ ] Run: `bundle exec rspec spec/models/prompt_tracker/prompt_version_spec.rb`

### Step 3: Update model_supports_structured_output?
- [ ] Update method to use `extract_provider` instead of direct access
- [ ] Run: `bundle exec rspec spec/models/prompt_tracker/prompt_version_spec.rb`

### Step 4: Add Display Helpers
- [ ] Open `app/helpers/prompt_tracker/application_helper.rb`
- [ ] Add `format_model_config_value` method
- [ ] Add `format_model_config_key` method
- [ ] Add `extract_provider_from_config` private method
- [ ] Add `format_tools_value` private method
- [ ] Run: `bundle exec rspec spec/helpers/prompt_tracker/application_helper_spec.rb`

### Step 5: Update Show Page View
- [ ] Open `app/views/prompt_tracker/testing/prompt_versions/show.html.erb`
- [ ] Find the Model Config card section
- [ ] Replace raw value display with `format_model_config_value` helper
- [ ] Add visual hierarchy for provider/API display
- [ ] Test in browser with existing version

### Step 6: Test Backward Compatibility
- [ ] Run full test suite: `bundle exec rspec`
- [ ] Start Rails server: `rails s`
- [ ] Navigate to an existing prompt version show page
- [ ] Verify "OpenAI - Response API" displays instead of "openai_responses"
- [ ] Verify tools display as "Web Search" instead of `["web_search"]`
- [ ] Verify playground form still works

**Checkpoint**: At this point, the app can read BOTH old and new formats.

---

## Phase 2: New Format Writers

### Step 7: Update PlaygroundExecuteService
- [ ] Open `app/services/prompt_tracker/playground_execute_service.rb`
- [ ] Update `execute_api_call` method to handle both formats
- [ ] Add backward compatibility for compound provider values
- [ ] Run: `bundle exec rspec spec/services/prompt_tracker/playground_execute_service_spec.rb`

### Step 8: Update Factories
- [ ] Open `spec/factories/prompt_tracker/llm_responses.rb`
- [ ] Update `:response_api` trait to use new format
- [ ] Open `spec/factories/prompt_tracker/prompt_versions.rb`
- [ ] Add `:with_chat_completion` trait
- [ ] Add `:with_response_api` trait
- [ ] Run: `bundle exec rspec`

### Step 9: Update Seeds
- [ ] Open `test/dummy/db/seeds/04c_prompts_with_tools.rb`
- [ ] Find all `model_config` hashes
- [ ] Replace `"provider" => "openai_responses"` with separate fields
- [ ] Run: `rails db:seed` (in test/dummy if needed)

### Step 10: Verify Playground Form
- [ ] Open browser console
- [ ] Navigate to playground
- [ ] Select "OpenAI" provider
- [ ] Select "Response API"
- [ ] Check Network tab when saving
- [ ] Verify request payload has separate `provider` and `api` fields
- [ ] Check database after save
- [ ] Verify new record has correct format

**Checkpoint**: At this point, new records use new format, old records still work.

---

## Phase 3: Data Migration

### Step 11: Create Migration Task
- [ ] Create `lib/tasks/prompt_tracker/migrate_model_config.rake`
- [ ] Add migration logic with PROVIDER_MAPPING
- [ ] Add logging for each updated record
- [ ] Add summary output (updated count, skipped count)

### Step 12: Test Migration on Development
- [ ] Create test data with old format:
  ```ruby
  PromptTracker::PromptVersion.last.update_column(:model_config, 
    { "provider" => "openai_responses", "model" => "gpt-4o" }
  )
  ```
- [ ] Run: `rails prompt_tracker:migrate_model_config`
- [ ] Verify output shows updated records
- [ ] Check database: `PromptTracker::PromptVersion.last.model_config`
- [ ] Should see: `{"provider"=>"openai", "api"=>"response_api", ...}`

### Step 13: Run Migration on Production
- [ ] Backup production database
- [ ] Deploy Phase 1 & 2 code changes
- [ ] Run: `rails prompt_tracker:migrate_model_config RAILS_ENV=production`
- [ ] Monitor output for errors
- [ ] Verify migration completed successfully

### Step 14: Verify Migration
- [ ] Check production database
- [ ] Query: `SELECT DISTINCT model_config->>'provider' FROM prompt_tracker_prompt_versions;`
- [ ] Should NOT see "openai_responses" or "openai_assistants"
- [ ] Should see "openai", "anthropic", etc.
- [ ] Test playground functionality
- [ ] Test show pages
- [ ] Test test runs

**Checkpoint**: At this point, ALL records use new format.

---

## Phase 4: Cleanup (Optional - Future)

### Step 15: Remove Backward Compatibility
- [ ] Remove compound provider handling from `extract_provider`
- [ ] Remove compound provider handling from `extract_api`
- [ ] Remove compound provider handling from `PlaygroundExecuteService`
- [ ] Run full test suite
- [ ] Update documentation

### Step 16: Update Documentation
- [ ] Update `docs/prd/01-openai-response-api-service.md`
- [ ] Update `docs/prd/03-playground-response-api-support.md`
- [ ] Remove references to compound provider format
- [ ] Add note about migration completion date

---

## Post-Migration Verification

- [ ] All tests pass: `bundle exec rspec`
- [ ] Playground form works correctly
- [ ] Show pages display formatted values
- [ ] Test runs execute successfully
- [ ] Evaluators work correctly
- [ ] No compound provider values in database
- [ ] Git commit all changes
- [ ] Create pull request
- [ ] Get code review
- [ ] Merge to master

---

## Rollback (If Needed)

If issues are discovered:

- [ ] Stop accepting new data (maintenance mode)
- [ ] Run rollback task: `rails prompt_tracker:rollback_model_config`
- [ ] Revert code changes: `git revert <commit>`
- [ ] Deploy reverted code
- [ ] Verify old format works again
- [ ] Investigate issues
- [ ] Fix and retry migration

---

## Success Metrics

After migration is complete:

- ✅ Zero compound provider values in database
- ✅ All PromptVersions have separate `provider` and `api` fields
- ✅ Show pages display "OpenAI - Response API" (not "openai_responses")
- ✅ Tools display as "Web Search, File Search" (not arrays)
- ✅ Playground cascading dropdowns work correctly
- ✅ All tests pass
- ✅ No production errors related to model_config

