# Quick Start: model_config Migration

## TL;DR

The playground form is already sending the correct format, but the database is storing the wrong format.

**Current (Wrong)**:
```json
{
  "provider": "openai_responses",
  "model": "gpt-4o"
}
```

**Target (Correct)**:
```json
{
  "provider": "openai",
  "api": "response_api",
  "model": "gpt-4o"
}
```

## Root Cause

The JavaScript controller (`playground_controller.js`) is **already sending** the correct format with separate `provider` and `api` fields (line 958-960).

However, somewhere in the data flow, these are being merged into a compound value `"openai_responses"`.

## Quick Fix Steps

### 1. Verify JavaScript is Sending Correct Data

Open browser console and check the request payload when saving from playground:

```javascript
// Should see:
{
  model_config: {
    provider: "openai",
    api: "response_api",  // ← This field should be present
    model: "gpt-4o"
  }
}
```

### 2. Check Controller is Receiving Correct Data

Add debug logging to `PlaygroundController#save`:

```ruby
def save
  model_config = params[:model_config] || {}
  Rails.logger.debug "Received model_config: #{model_config.inspect}"
  # ...
end
```

### 3. Run Migration in Order

```bash
# Phase 1: Make code backward compatible
# (Implement Steps 1-3 from main migration doc)

# Phase 2: Update factories and seeds
# (Implement Steps 4-6)

# Phase 3: Migrate existing data
rails prompt_tracker:migrate_model_config

# Verify
rails console
> PromptTracker::PromptVersion.last.model_config
# Should show: {"provider"=>"openai", "api"=>"response_api", ...}
```

## Files to Change (Priority Order)

1. **app/models/prompt_tracker/prompt_version.rb**
   - Add `extract_provider` and `extract_api` helpers
   - Update `api_type` method
   - Update `model_supports_structured_output?`

2. **app/services/prompt_tracker/playground_execute_service.rb**
   - Update `execute_api_call` to handle both formats

3. **app/helpers/prompt_tracker/application_helper.rb**
   - Add `format_model_config_value` helper
   - Add `format_model_config_key` helper

4. **app/views/prompt_tracker/testing/prompt_versions/show.html.erb**
   - Update Model Config card to use new helpers

5. **lib/tasks/prompt_tracker/migrate_model_config.rake**
   - Create migration task

6. **spec/factories/** and **test/dummy/db/seeds/**
   - Update to use new format

## Testing

```bash
# Run specs
bundle exec rspec spec/models/prompt_tracker/prompt_version_spec.rb
bundle exec rspec spec/services/prompt_tracker/playground_execute_service_spec.rb

# Test in browser
# 1. Go to playground
# 2. Select "OpenAI" provider
# 3. Select "Response API" 
# 4. Save
# 5. Check database: should have separate provider/api fields
```

## Expected Outcome

After migration:
- ✅ Playground form works with cascading dropdowns
- ✅ Show page displays "OpenAI - Response API" (not "openai_responses")
- ✅ Tools display as "Web Search, File Search" (not `["web_search", "file_search"]`)
- ✅ All existing functionality continues to work

## See Full Plan

For detailed implementation steps, see: `docs/migration/model_config_provider_api_split.md`

