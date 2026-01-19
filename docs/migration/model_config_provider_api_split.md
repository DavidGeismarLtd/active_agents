# Migration Plan: Split Provider from API in model_config

## Problem Statement

Currently, `model_config` stores provider and API as a single compound value:

```json
{
  "provider": "openai_responses",
  "model": "gpt-4o",
  "temperature": 0.7
}
```

This should be split into separate `provider` and `api` fields:

```json
{
  "provider": "openai",
  "api": "response_api",
  "model": "gpt-4o",
  "temperature": 0.7
}
```

## Root Cause

The compound value `"openai_responses"` was created as a workaround to distinguish between:
- OpenAI Chat Completions API (`/v1/chat/completions`)
- OpenAI Response API (`/v1/responses`)

This approach has several issues:
1. **UI Confusion**: The playground form expects separate `provider` and `api` fields
2. **Display Issues**: Show pages display "openai_responses" instead of "OpenAI - Response API"
3. **Inconsistent Data Model**: Configuration defines providers with nested APIs, but storage uses compound keys
4. **Scalability**: Adding new APIs requires new compound provider names

## Impact Analysis

### Files That CREATE the Compound Value

1. **JavaScript Controller** (✅ Already correct)
   - `app/javascript/prompt_tracker/controllers/playground_controller.js`
   - Line 958-960: Already sends separate `provider` and `api` fields

2. **View Template** (✅ Already correct)
   - `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb`
   - Lines 15-16: Already reads separate `provider` and `api` from model_config

### Files That CONSUME the Compound Value

1. **PromptVersion Model**
   - `app/models/prompt_tracker/prompt_version.rb`
   - Line 452-468: `api_type` method uses compound provider value
   - Line 420-433: `model_supports_structured_output?` uses compound provider value

2. **PlaygroundExecuteService**
   - `app/services/prompt_tracker/playground_execute_service.rb`
   - Line 83-92: Routes based on compound provider value

3. **ApiTypes Module**
   - `app/services/prompt_tracker/api_types.rb`
   - Lines 59-66: Has CONFIG_TO_API_TYPE mapping but not used by PromptVersion

4. **Test Executors**
   - `app/services/prompt_tracker/test_runners/api_executors/openai/response_api_executor.rb`
   - Previously had override for provider (removed by user)

5. **Factories & Seeds**
   - `spec/factories/prompt_tracker/llm_responses.rb`
   - `test/dummy/db/seeds/04c_prompts_with_tools.rb`
   - Use compound `"openai_responses"` value

6. **Documentation**
   - `docs/prd/01-openai-response-api-service.md`
   - `docs/prd/03-playground-response-api-support.md`
   - Reference compound provider format

## Migration Strategy

### Phase 1: Update Data Consumers (Read Both Formats)

Make all code that reads `model_config` support BOTH formats:
- Old: `{ "provider": "openai_responses" }`
- New: `{ "provider": "openai", "api": "response_api" }`

### Phase 2: Update Data Producers (Write New Format)

Ensure all code that creates/updates `model_config` uses the new format.

### Phase 3: Data Migration (Convert Existing Records)

Run a migration to convert all existing `model_config` records.

### Phase 4: Remove Old Format Support

Remove backward compatibility code after confirming all data is migrated.

---

## Detailed Implementation Plan

### Step 1: Add Helper Methods to PromptVersion Model

**File**: `app/models/prompt_tracker/prompt_version.rb`

Add private helper methods to extract provider and API from model_config:

```ruby
private

# Extract provider from model_config (supports both old and new formats)
# Old format: { "provider" => "openai_responses" }
# New format: { "provider" => "openai", "api" => "response_api" }
def extract_provider
  return nil if model_config.blank?

  provider = model_config["provider"]&.to_s
  return nil if provider.blank?

  # If API is explicitly set, use provider as-is (new format)
  return provider if model_config["api"].present?

  # Otherwise, extract from compound value (old format)
  case provider
  when "openai_responses"
    "openai"
  when "openai_assistants"
    "openai"
  else
    provider
  end
end

# Extract API from model_config (supports both old and new formats)
def extract_api
  return nil if model_config.blank?

  # New format: explicit API field
  return model_config["api"]&.to_sym if model_config["api"].present?

  # Old format: infer from compound provider value
  provider = model_config["provider"]&.to_s
  case provider
  when "openai_responses"
    :response_api
  when "openai_assistants"
    :assistants_api
  when "openai"
    :chat_completion
  when "anthropic"
    :messages
  when "google"
    :gemini
  else
    nil
  end
end
```

### Step 2: Update api_type Method

**File**: `app/models/prompt_tracker/prompt_version.rb`

Replace the `api_type` method to use the new helper:

```ruby
def api_type
  return ApiTypes::OPENAI_CHAT_COMPLETION if model_config.blank?

  provider = extract_provider&.to_sym
  api = extract_api

  # Use ApiTypes.from_config to convert (provider, api) → api_type
  api_type = ApiTypes.from_config(provider, api) if provider && api

  # Fallback to old behavior if conversion fails
  api_type || ApiTypes::OPENAI_CHAT_COMPLETION
end
```

### Step 3: Update model_supports_structured_output? Method

**File**: `app/models/prompt_tracker/prompt_version.rb`

```ruby
def model_supports_structured_output?
  return false if model_config.blank?

  provider = extract_provider
  model = model_config["model"]&.to_s

  case provider
  when "openai"
    model&.start_with?("gpt-4o") || model&.start_with?("gpt-4-turbo")
  when "anthropic"
    model&.include?("claude-3")
  else
    false
  end
end
```

### Step 4: Update PlaygroundExecuteService

**File**: `app/services/prompt_tracker/playground_execute_service.rb`

```ruby
def execute_api_call
  provider = model_config[:provider] || model_config["provider"] || "openai"
  api = model_config[:api] || model_config["api"]

  # Support old compound format
  if api.blank?
    case provider.to_s
    when "openai_responses"
      provider = "openai"
      api = "response_api"
    when "openai_assistants"
      provider = "openai"
      api = "assistants_api"
    end
  end

  # Route based on API
  case api.to_s
  when "response_api"
    execute_response_api
  when "assistants_api"
    execute_assistant_api
  else
    execute_chat_completion
  end
end
```

### Step 5: Update Factories

**File**: `spec/factories/prompt_tracker/llm_responses.rb`

```ruby
# OLD
trait :response_api do
  provider { "openai_responses" }
  response_id { "resp_#{SecureRandom.hex(12)}" }
end

# NEW
trait :response_api do
  provider { "openai" }
  api { "response_api" }
  response_id { "resp_#{SecureRandom.hex(12)}" }
end
```

**File**: `spec/factories/prompt_tracker/prompt_versions.rb`

Add factory traits for different API types:

```ruby
trait :with_chat_completion do
  model_config do
    {
      "provider" => "openai",
      "api" => "chat_completion",
      "model" => "gpt-4o",
      "temperature" => 0.7
    }
  end
end

trait :with_response_api do
  model_config do
    {
      "provider" => "openai",
      "api" => "response_api",
      "model" => "gpt-4o",
      "temperature" => 0.7,
      "tools" => ["web_search"]
    }
  end
end
```

### Step 6: Update Seeds

**File**: `test/dummy/db/seeds/04c_prompts_with_tools.rb`

```ruby
# OLD
model_config: {
  "provider" => "openai_responses",
  "model" => "gpt-4o",
  "temperature" => 0.7
}

# NEW
model_config: {
  "provider" => "openai",
  "api" => "response_api",
  "model" => "gpt-4o",
  "temperature" => 0.7
}
```

### Step 7: Create Data Migration Rake Task

**File**: `lib/tasks/prompt_tracker/migrate_model_config.rake`

```ruby
namespace :prompt_tracker do
  desc "Migrate model_config from compound provider to separate provider/api fields"
  task migrate_model_config: :environment do
    puts "Starting model_config migration..."

    # Mapping of compound provider values to (provider, api) pairs
    PROVIDER_MAPPING = {
      "openai_responses" => { provider: "openai", api: "response_api" },
      "openai_assistants" => { provider: "openai", api: "assistants_api" }
    }.freeze

    updated_count = 0
    skipped_count = 0

    PromptTracker::PromptVersion.find_each do |version|
      next if version.model_config.blank?

      provider = version.model_config["provider"]

      # Skip if already in new format (has explicit API field)
      if version.model_config["api"].present?
        skipped_count += 1
        next
      end

      # Skip if provider doesn't need migration
      mapping = PROVIDER_MAPPING[provider]
      unless mapping
        skipped_count += 1
        next
      end

      # Update to new format
      new_config = version.model_config.dup
      new_config["provider"] = mapping[:provider]
      new_config["api"] = mapping[:api]

      version.update_column(:model_config, new_config)
      updated_count += 1

      puts "  Updated PromptVersion ##{version.id}: #{provider} → #{mapping[:provider]}/#{mapping[:api]}"
    end

    puts "\nMigration complete!"
    puts "  Updated: #{updated_count} records"
    puts "  Skipped: #{skipped_count} records"
  end
end
```

### Step 8: Add Helper Methods to ApplicationHelper

**File**: `app/helpers/prompt_tracker/application_helper.rb`

Add methods to format model_config for display:

```ruby
# Format model config value for display
def format_model_config_value(key, value, model_config = {})
  case key.to_s
  when 'provider'
    # Extract provider from compound or use as-is
    provider = extract_provider_from_config(model_config)
    provider_name(provider.to_sym) if provider

  when 'api'
    # Get API display name
    provider = extract_provider_from_config(model_config)
    api_key = value.to_sym
    api_config = apis_for(provider.to_sym).find { |a| a[:key] == api_key }
    api_config&.dig(:name) || value.to_s.titleize

  when 'tools'
    format_tools_value(value, model_config)

  when 'temperature', 'top_p', 'frequency_penalty', 'presence_penalty'
    value.to_f.round(2)

  when 'max_tokens'
    "#{value.to_i} tokens"

  else
    value
  end
end

# Format model config key for display
def format_model_config_key(key)
  case key.to_s
  when 'api'
    'API'
  when 'max_tokens'
    'Max Tokens'
  when 'top_p'
    'Top P'
  else
    key.to_s.titleize
  end
end

private

# Extract provider from model_config (handles both old and new formats)
def extract_provider_from_config(config)
  return nil if config.blank?

  provider = config['provider'] || config[:provider]
  return nil if provider.blank?

  # If API is explicitly set, use provider as-is (new format)
  return provider if config['api'].present? || config[:api].present?

  # Otherwise, extract from compound value (old format)
  case provider.to_s
  when 'openai_responses', 'openai_assistants'
    'openai'
  else
    provider
  end
end

# Format tools array as user-friendly names
def format_tools_value(tools, model_config)
  return tools unless tools.is_a?(Array)

  provider = extract_provider_from_config(model_config)
  api_key = model_config['api'] || model_config[:api]

  # Infer API from old compound format if needed
  if api_key.blank?
    compound_provider = model_config['provider'] || model_config[:provider]
    api_key = case compound_provider.to_s
              when 'openai_responses' then 'response_api'
              when 'openai_assistants' then 'assistants_api'
              else 'chat_completion'
              end
  end

  available_tools = PromptTracker.configuration.tools_for_api(
    provider.to_sym,
    api_key.to_sym
  )

  tools.map do |tool_id|
    tool = available_tools.find { |t| t[:id] == tool_id }
    tool ? tool[:name] : tool_id.to_s.titleize
  end.join(', ')
end
```

### Step 9: Update Show Page View

**File**: `app/views/prompt_tracker/testing/prompt_versions/show.html.erb`

Update the Model Config card to use the new helper:

```erb
<div class="card-body">
  <% if @version.model_config.present? %>
    <% # Display provider and API separately with visual hierarchy %>
    <% if @version.model_config['provider'].present? %>
      <div class="mb-3 pb-3 border-bottom">
        <small class="text-muted d-block">
          <%= format_model_config_key('provider') %>
        </small>
        <strong>
          <%= format_model_config_value('provider', @version.model_config['provider'], @version.model_config) %>
        </strong>

        <% api_value = @version.model_config['api'] %>
        <% if api_value.present? %>
          <div class="mt-2 ms-3">
            <small class="text-muted d-block">
              <%= format_model_config_key('api') %>
            </small>
            <strong>
              <%= format_model_config_value('api', api_value, @version.model_config) %>
            </strong>
          </div>
        <% end %>
      </div>
    <% end %>

    <% # Display other config values %>
    <% @version.model_config.except('provider', 'api').each do |key, value| %>
      <div class="mb-2">
        <small class="text-muted d-block">
          <%= format_model_config_key(key) %>
        </small>
        <strong>
          <%= format_model_config_value(key, value, @version.model_config) %>
        </strong>
      </div>
    <% end %>
  <% else %>
    <p class="text-muted mb-0">No model configuration set</p>
  <% end %>
</div>
```

---

## Execution Order

Execute the steps in this exact order to ensure backward compatibility during migration:

### Phase 1: Make Readers Backward Compatible (Steps 1-3, 8)
1. ✅ Add `extract_provider` and `extract_api` helper methods to PromptVersion
2. ✅ Update `api_type` method to use helpers
3. ✅ Update `model_supports_structured_output?` method
4. ✅ Add display helpers to ApplicationHelper
5. ✅ Update show page view to use new helpers
6. ✅ Run tests to ensure backward compatibility

**At this point, the app can read BOTH old and new formats**

### Phase 2: Update Writers to New Format (Steps 4-6)
1. ✅ Update PlaygroundExecuteService to handle both formats
2. ✅ Update factories to use new format
3. ✅ Update seeds to use new format
4. ✅ Verify playground form already sends new format (it does!)
5. ✅ Run tests to ensure new format works

**At this point, new records use new format, old records still work**

### Phase 3: Migrate Existing Data (Step 7)
1. ✅ Create migration rake task
2. ✅ Test on development database
3. ✅ Run on production: `rails prompt_tracker:migrate_model_config`
4. ✅ Verify all records migrated successfully

**At this point, ALL records use new format**

### Phase 4: Cleanup (Optional - Future)
1. Remove backward compatibility code from `extract_provider` and `extract_api`
2. Remove compound provider handling from PlaygroundExecuteService
3. Update documentation to remove references to old format

---

## Testing Checklist

### Before Migration
- [ ] Existing prompt versions with `"provider": "openai_responses"` display correctly
- [ ] Playground form works with existing versions
- [ ] Test runs work with existing versions
- [ ] Evaluators work with existing versions

### After Phase 1 (Backward Compatible Readers)
- [ ] All existing tests pass
- [ ] Show page displays "OpenAI - Response API" instead of "openai_responses"
- [ ] Tools display as "Web Search, File Search" instead of array
- [ ] api_type returns correct value for both old and new formats

### After Phase 2 (New Format Writers)
- [ ] New prompt versions created from playground use new format
- [ ] Factories create records with new format
- [ ] Seeds create records with new format
- [ ] All tests pass with new format

### After Phase 3 (Data Migration)
- [ ] All PromptVersion records have separate `provider` and `api` fields
- [ ] No records have compound provider values
- [ ] All existing functionality still works
- [ ] Show pages display correctly for all versions

---

## Rollback Plan

If issues are discovered after migration:

### Immediate Rollback (Before Phase 3)
Simply revert the code changes. Old data still works.

### Post-Migration Rollback (After Phase 3)
Run reverse migration:

```ruby
# Reverse migration task
namespace :prompt_tracker do
  desc "Rollback model_config to compound provider format"
  task rollback_model_config: :environment do
    REVERSE_MAPPING = {
      ["openai", "response_api"] => "openai_responses",
      ["openai", "assistants_api"] => "openai_assistants"
    }.freeze

    PromptTracker::PromptVersion.find_each do |version|
      next if version.model_config.blank?

      provider = version.model_config["provider"]
      api = version.model_config["api"]

      compound_key = [provider, api]
      compound_value = REVERSE_MAPPING[compound_key]

      if compound_value
        new_config = version.model_config.dup
        new_config["provider"] = compound_value
        new_config.delete("api")
        version.update_column(:model_config, new_config)
      end
    end
  end
end
```

---

## Files to Update Summary

### Models
- ✅ `app/models/prompt_tracker/prompt_version.rb` - Add helpers, update api_type

### Services
- ✅ `app/services/prompt_tracker/playground_execute_service.rb` - Handle both formats

### Helpers
- ✅ `app/helpers/prompt_tracker/application_helper.rb` - Add display formatters

### Views
- ✅ `app/views/prompt_tracker/testing/prompt_versions/show.html.erb` - Use new helpers
- ⚠️ `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb` - Already correct!

### Tests
- ✅ `spec/factories/prompt_tracker/llm_responses.rb` - Update traits
- ✅ `spec/factories/prompt_tracker/prompt_versions.rb` - Add new traits
- ⚠️ Update any specs that assert on model_config structure

### Seeds
- ✅ `test/dummy/db/seeds/04c_prompts_with_tools.rb` - Update to new format

### Tasks
- ✅ `lib/tasks/prompt_tracker/migrate_model_config.rake` - Create migration task

### Documentation
- ⚠️ `docs/prd/01-openai-response-api-service.md` - Update examples
- ⚠️ `docs/prd/03-playground-response-api-support.md` - Update examples

---

## Benefits After Migration

1. **Consistent Data Model**: Storage matches configuration structure
2. **Better UX**: Show pages display "OpenAI - Response API" instead of "openai_responses"
3. **Scalability**: Easy to add new APIs without creating compound keys
4. **Cleaner Code**: No more special cases for compound provider values
5. **Type Safety**: Separate fields are easier to validate and query
6. **Better Analytics**: Can query by provider or API independently

---

## Estimated Effort

- **Phase 1**: 2-3 hours (code changes + testing)
- **Phase 2**: 1-2 hours (factories, seeds, testing)
- **Phase 3**: 30 minutes (migration task + execution)
- **Phase 4**: 1 hour (cleanup, optional)

**Total**: ~5-7 hours

---

## Questions & Answers

**Q: Why not just update the database directly?**
A: We need backward compatibility during the transition. The helper methods ensure old data still works while new data uses the new format.

**Q: What if a PromptVersion has responses?**
A: The migration only updates the `model_config` column, which doesn't affect immutability. Responses reference the version, not the config structure.

**Q: Will this break existing API integrations?**
A: No. The `model_config` is internal storage. External APIs (if any) should use the configuration helpers which will work with both formats.

**Q: Can we skip Phase 1 and go straight to migration?**
A: No. Without Phase 1, old records would break immediately after migration. Phase 1 ensures the app can read both formats.

---

## Success Criteria

Migration is successful when:

1. ✅ All PromptVersion records have `{ "provider": "openai", "api": "response_api" }` format
2. ✅ Show pages display formatted provider/API names
3. ✅ Playground form works correctly with cascading dropdowns
4. ✅ All tests pass
5. ✅ No compound provider values exist in database
6. ✅ Tools display as formatted names, not arrays
