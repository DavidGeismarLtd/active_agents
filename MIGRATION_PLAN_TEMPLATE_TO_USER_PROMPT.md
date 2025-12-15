# Migration Plan: `template` → `user_prompt` + Add `system_prompt`

## Overview
Full migration to rename the `template` column to `user_prompt` and add a new `system_prompt` column to align with industry-standard LLM API structure.

## Goals
1. Rename `template` → `user_prompt` across entire codebase
2. Add new `system_prompt` field (optional)
3. Update all references in models, services, controllers, views, tests, and documentation
4. Maintain backward compatibility during migration
5. Zero data loss

## Migration Scope

### 1. Database Changes
**File:** `db/migrate/YYYYMMDDHHMMSS_rename_template_to_user_prompt_and_add_system_prompt.rb`
- Rename column: `template` → `user_prompt`
- Add column: `system_prompt` (text, nullable)
- Update schema annotations

### 2. Model Changes (4 files)
- `app/models/prompt_tracker/prompt_version.rb` - Primary model
  - Update validation: `validates :template` → `validates :user_prompt`
  - Update methods: `render()`, `extract_variables_schema()`, etc.
  - Update schema annotation comment
  - Update all internal references
  
- `app/models/prompt_tracker/prompt_file.rb`
  - Update YAML parsing to use `user_prompt`
  - Update `to_yaml_export` method
  
- `app/models/prompt_tracker/prompt_test.rb`
  - Check for any template references (likely `template_variables` only - keep as is)
  
- `app/models/prompt_tracker/prompt.rb`
  - Check for any template references

### 3. Service Changes (5 files)
- `app/services/prompt_tracker/template_renderer.rb` - Keep class name, update usage
- `app/services/prompt_tracker/llm_call_service.rb` - Update render_template method
- `app/services/prompt_tracker/file_sync_service.rb` - Update template comparison
- `app/services/prompt_tracker/prompt_test_runner.rb` - Update rendering
- `app/services/prompt_tracker/llm_client_service.rb` - Prepare for system_prompt support

### 4. Controller Changes (2 files)
- `app/controllers/prompt_tracker/testing/playground_controller.rb`
  - Update `extract_variables_from_template(@version.template)` → `@version.user_prompt`
  - Update save/update actions to use `user_prompt` param
  - Add `system_prompt` param handling

### 5. Job Changes (1 file)
- `app/jobs/prompt_tracker/run_test_job.rb` - Update renderer usage

### 6. View Changes (~15 files)
**Playground:**
- `app/views/prompt_tracker/testing/playground/show.html.erb`
  - Update label: "Prompt Template" → "User Prompt Template"
  - Update textarea to use `@version&.user_prompt`
  - Add new textarea for `system_prompt`

**Test Views:**
- `app/views/prompt_tracker/testing/prompt_tests/cells/_template.html.erb`
  - Update to use `version.user_prompt`
  - Consider renaming file to `_user_prompt.html.erb`
  
- `app/views/prompt_tracker/testing/prompt_versions/show.html.erb`
  - Update display of template → user_prompt
  
- `app/views/prompt_tracker/testing/prompt_versions/compare.html.erb`
  - Update comparison view

**Other Views:**
- `app/views/prompt_tracker/evaluations/show.html.erb`
- `app/views/prompt_tracker/prompt_test_runs/show.html.erb`
- `app/views/prompt_tracker/testing/prompt_test_runs/show.html.erb`

### 7. JavaScript Changes (3 files)
- `app/javascript/prompt_tracker/controllers/playground_controller.js`
  - Update target names: `templateEditor` → `userPromptEditor`
  - Add `systemPromptEditor` target
  - Update methods: `onTemplateInput` → `onUserPromptInput`
  
- `app/javascript/prompt_tracker/controllers/template_variables_controller.js`
  - Keep as is (handles variable extraction, name still valid)
  
- `app/assets/javascripts/prompt_tracker/playground.js`
  - Check for template references

### 8. Test/Spec Changes (~20 files)
**Factories:**
- `spec/factories/prompt_tracker/prompt_versions.rb` - Update `template:` → `user_prompt:`
- `spec/factories/prompt_tracker/prompt_tests.rb` - Check references

**Model Specs:**
- `spec/models/prompt_tracker/prompt_version_spec.rb` - Update all template references
- `spec/models/prompt_tracker/prompt_file_spec.rb` - Update YAML parsing tests
- `spec/models/prompt_tracker/prompt_test_spec.rb`
- `spec/models/prompt_tracker/prompt_test_run_spec.rb`
- `spec/models/prompt_tracker/ab_test_spec.rb`

**Service Specs:**
- `spec/services/prompt_tracker/template_renderer_spec.rb` - Keep class name
- `spec/services/prompt_tracker/evaluator_registry_spec.rb`
- All evaluator specs

**Controller/System Specs:**
- `spec/controllers/prompt_tracker/playground_controller_spec.rb`
- `spec/system/prompt_tracker/prompt_test_form_spec.rb`

**Fixtures:**
- `test/fixtures/prompt_tracker/prompt_versions.yml` - Update template: → user_prompt:

### 9. Documentation Changes (~15 files)
- `docs/ARCHITECTURE.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/PHASE_1_COMPLETE.md`
- `docs/FEATURE_1_PLAYGROUND.md`
- `docs/TESTING_GUIDE.md`
- All other docs mentioning template field

### 10. Example Files (3 files)
- `examples/quick_test.rb`
- `examples/multi_evaluator_setup.rb`
- `examples/test_track_call.rb`

### 11. YAML Prompt Files (~6 files)
- `app/prompts/**/*.yml` - Update `template:` → `user_prompt:` in all YAML files
- `test/dummy/app/prompts/my_prompt.yml`

## Execution Order

1. ✅ Create migration file
2. ✅ Update PromptVersion model (core)
3. ✅ Update PromptFile model (YAML handling)
4. ✅ Update all services
5. ✅ Update controllers
6. ✅ Update jobs
7. ✅ Update views (ERB)
8. ✅ Update JavaScript
9. ✅ Update all YAML prompt files
10. ✅ Update factories and fixtures
11. ✅ Update all specs/tests
12. ✅ Update documentation
13. ✅ Run migration
14. ✅ Run full test suite
15. ✅ Manual testing in UI

## Risk Mitigation
- Create backup before migration
- Run migration on development first
- Comprehensive test coverage
- Update schema.rb after migration
- Annotate models with new schema

## Files NOT to Change
- `template_variables` field in PromptTest - this is correct (variables FOR the template)
- `TemplateRenderer` class name - this is a generic renderer, name is still appropriate
- View template files themselves (*.html.erb) - these are Rails view templates, different concept
- `form_template` in EvaluatorRegistry - this refers to form partials, not prompt templates

## Estimated Impact
- **Database:** 1 migration file
- **Models:** 4 files
- **Services:** 5 files  
- **Controllers:** 2 files
- **Jobs:** 1 file
- **Views:** ~15 files
- **JavaScript:** 3 files
- **Tests/Specs:** ~25 files
- **Documentation:** ~15 files
- **YAML Files:** ~7 files
- **Total:** ~78 files to update

