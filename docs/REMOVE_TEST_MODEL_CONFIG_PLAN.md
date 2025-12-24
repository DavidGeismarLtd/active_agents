# Remove model_config from PromptTest - Implementation Plan

## Status: ✅ COMPLETE

## Overview
Remove `model_config` from PromptTest and use PromptVersion's `model_config` instead.

## Rationale
- Tests should validate prompts with the **intended production model**
- Single source of truth: PromptVersion.model_config
- Simpler architecture, less confusion
- Tests validate what will actually run in production

## Files to Update

### 1. Database Migration
- [ ] Create migration to remove `model_config` column from `prompt_tracker_prompt_tests`
- [ ] Remove validation in model

### 2. Model Changes
- [ ] `app/models/prompt_tracker/prompt_test.rb` - Remove `model_config` validation
- [ ] Update schema annotations

### 3. Service/Job Changes (use `version.model_config` instead of `test.model_config`)
- [ ] `app/jobs/prompt_tracker/run_test_job.rb` (line 75)
- [ ] `app/services/prompt_tracker/prompt_test_runner.rb` (line 128)

### 4. View Changes
- [ ] `app/views/prompt_tracker/testing/prompt_tests/_form.html.erb` - Remove model config section (lines 46-146)
- [ ] `app/views/prompt_tracker/testing/prompt_tests/show.html.erb` - Show version's model config instead (line 86)
- [ ] `app/views/prompt_tracker/testing/prompt_test_runs/show.html.erb` - Show version's model config (line 260)
- [ ] `app/views/prompt_tracker/prompt_test_runs/show.html.erb` - Show version's model config (line 190)

### 5. Controller Changes
- [ ] Check if any controllers reference `model_config` parameter for tests

### 6. Factory Changes
- [ ] `spec/factories/prompt_tests.rb` - Remove model_config
- [ ] Update any factory usage in specs

### 7. Spec Changes
- [ ] `spec/models/prompt_tracker/prompt_test_spec.rb` - Remove model_config validation test (line 38)
- [ ] `spec/models/prompt_tracker/prompt_test_run_spec.rb` - Remove model_config from factory (line 31)
- [ ] Update any other specs that create tests with model_config

### 8. Seed Data Changes
- [ ] `test/dummy/db/seeds.rb` - Remove model_config from test creation (line 226)

### 9. Configuration Cleanup
- [ ] Remove `config.llm_judge_model` from configuration (optional - can keep as default)
- [ ] Remove `config.prompt_generator_model` (optional - can keep)
- [ ] Remove `config.dataset_generator_model` (optional - can keep)

## Implementation Steps

1. **Create migration** to remove column
2. **Update model** - remove validation
3. **Update services/jobs** - use `prompt_version.model_config`
4. **Update views** - remove form section, show version config
5. **Update specs** - remove model_config from factories
6. **Update seeds** - remove model_config from test creation
7. **Run tests** to ensure everything works
8. **Run migration** on dummy database

## Code Changes Summary

### Before (Current)
```ruby
# In RunTestJob
model_config = test.model_config.with_indifferent_access

# In PromptTest model
validates :model_config, presence: true

# In factory
create(:prompt_test, model_config: { provider: "openai", model: "gpt-4" })
```

### After (New)
```ruby
# In RunTestJob
model_config = test.prompt_version.model_config.with_indifferent_access

# In PromptTest model
# (validation removed)

# In factory
create(:prompt_test) # No model_config needed
```

## Testing Strategy

1. Run existing test suite to identify failures
2. Update failing tests to remove model_config
3. Verify tests still run correctly using version's model_config
4. Manual testing in UI to ensure forms work

## Rollback Plan

If issues arise:
1. Revert migration
2. Restore model validation
3. Restore form fields
4. Restore service/job code
