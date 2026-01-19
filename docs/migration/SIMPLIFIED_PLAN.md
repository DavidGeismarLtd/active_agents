# Simplified Migration Plan: Provider/API Split + Naming Fixes

## Overview

This plan implements the correct `model_config` format WITHOUT backward compatibility, since we'll drop and recreate the database.

## Key Changes

### 1. API Naming Convention Updates
- `"response_api"` → `"responses"` (matches OpenAI's `/v1/responses` endpoint)
- `"chat_completion"` → `"chat_completions"` (matches OpenAI's `/v1/chat/completions` endpoint)
- `"assistants_api"` → `"assistants"` (matches OpenAI's `/v1/assistants` endpoint)

### 2. model_config Format
**Before (Wrong)**:
```json
{
  "provider": "openai_responses",
  "model": "gpt-4o"
}
```

**After (Correct)**:
```json
{
  "provider": "openai",
  "api": "responses",
  "model": "gpt-4o"
}
```

---

## Implementation Steps

### Step 1: Update Configuration (Initializer)

**File**: `test/dummy/config/initializers/prompt_tracker.rb`

```ruby
config.providers = {
  openai: {
    name: "OpenAI",
    apis: {
      chat_completions: {  # Changed from chat_completion
        name: "Chat Completions",
        description: "Standard chat API with messages",
        default: true
      },
      responses: {  # Changed from response_api
        name: "Responses",
        description: "Stateful conversations with built-in tools",
        capabilities: [ :web_search, :file_search, :code_interpreter, :functions ]
      },
      assistants: {  # Changed from assistants_api
        name: "Assistants",
        description: "Full assistant features with threads and runs"
      }
    }
  },
  anthropic: {
    name: "Anthropic",
    apis: {
      messages: {
        name: "Messages",
        description: "Claude messages API",
        default: true
      }
    }
  },
  google: {
    name: "Google",
    apis: {
      gemini: {
        name: "Gemini",
        description: "Google Gemini API",
        default: true
      }
    }
  }
}
```

### Step 2: Update ApiTypes Module

**File**: `app/services/prompt_tracker/api_types.rb`

Simplify to only what's needed:

```ruby
module PromptTracker
  # Defines API types for the system.
  # Maps (provider, api) pairs to unified API type constants.
  module ApiTypes
    # Mapping from config format (provider, api) to ApiType constant
    CONFIG_TO_API_TYPE = {
      %i[openai chat_completions] => :openai_chat_completions,
      %i[openai responses] => :openai_responses,
      %i[openai assistants] => :openai_assistants,
      %i[anthropic messages] => :anthropic_messages,
      %i[google gemini] => :google_gemini
    }.freeze

    # Mapping from ApiType constant to config format (provider, api)
    API_TYPE_TO_CONFIG = CONFIG_TO_API_TYPE.invert.freeze

    # Convert from config format (provider + api) to ApiType constant.
    #
    # @param provider [Symbol, String] the provider key (e.g., :openai)
    # @param api [Symbol, String] the API key (e.g., :chat_completions)
    # @return [Symbol, nil] the ApiType constant or nil if not found
    def self.from_config(provider, api)
      CONFIG_TO_API_TYPE[[ provider.to_sym, api.to_sym ]]
    end

    # Convert from ApiType constant to config format.
    #
    # @param api_type [Symbol] the ApiType constant
    # @return [Hash, nil] hash with :provider and :api keys, or nil if not found
    def self.to_config(api_type)
      result = API_TYPE_TO_CONFIG[api_type.to_sym]
      return nil unless result

      { provider: result[0], api: result[1] }
    end

    # Returns all API types
    #
    # @return [Array<Symbol>] all API type symbols
    def self.all
      CONFIG_TO_API_TYPE.values
    end

    # Check if a value is a valid API type
    #
    # @param value [Symbol, String] the value to check
    # @return [Boolean] true if the value is a valid API type
    def self.valid?(value)
      return false if value.nil?
      all.include?(value.to_sym)
    end
  end
end
```

**Remove**: All the SINGLE_RESPONSE_APIS, CONVERSATIONAL_APIS constants and related methods.

### Step 3: Update PromptVersion Model

**File**: `app/models/prompt_tracker/prompt_version.rb`

Update the `api_type` method to use the new format:

```ruby
# Returns the API type for this PromptVersion based on model_config.
#
# @return [Symbol, nil] the API type constant
# @example
#   version.api_type # => :openai_chat_completions or :openai_responses
def api_type
  return nil if model_config.blank?

  provider = model_config["provider"]&.to_sym
  api = model_config["api"]&.to_sym

  return nil unless provider && api

  ApiTypes.from_config(provider, api)
end
```

**Note**: `model_supports_structured_output?` already uses just the provider, so it doesn't need changes.

### Step 4: Update PlaygroundExecuteService

**File**: `app/services/prompt_tracker/playground_execute_service.rb`

Update `execute_api_call` to read separate fields:

```ruby
def execute_api_call
  provider = model_config[:provider] || model_config["provider"]
  api = model_config[:api] || model_config["api"]

  # Route based on API
  case api.to_s
  when "responses"
    execute_response_api
  when "assistants"
    execute_assistant_api
  else
    execute_chat_completion
  end
end
```

### Step 5: Update JavaScript Controller

**File**: `app/javascript/prompt_tracker/controllers/playground_controller.js`

Update line 319 to use new API names:

```javascript
// Show/hide conversation panel via conversation outlet
const isConversationalApi = apiConfig?.key === 'responses' || apiConfig?.key === 'assistants'
if (this.hasConversationOutlet) {
  if (isConversationalApi) {
    this.conversationOutlet.show()
  } else {
    this.conversationOutlet.hide()
  }
}
```

### Step 6: Update Seeds

**File**: `test/dummy/db/seeds/04c_prompts_with_tools.rb`

Already updated by user:

```ruby
model_config: {
  "provider" => "openai",
  "api" => "responses",  # Changed from "response_api"
  "model" => "gpt-4o",
  "temperature" => 0.7
}
```

### Step 7: Update Factories

**File**: `spec/factories/prompt_tracker/llm_responses.rb`

```ruby
# OLD
trait :response_api do
  provider { "openai_responses" }
  response_id { "resp_#{SecureRandom.hex(12)}" }
end

# NEW
trait :responses do
  provider { "openai" }
  api { "responses" }
  response_id { "resp_#{SecureRandom.hex(12)}" }
end
```

**File**: `spec/factories/prompt_tracker/prompt_versions.rb`

Add traits for different APIs:

```ruby
trait :with_chat_completions do
  model_config do
    {
      "provider" => "openai",
      "api" => "chat_completions",
      "model" => "gpt-4o",
      "temperature" => 0.7
    }
  end
end

trait :with_responses do
  model_config do
    {
      "provider" => "openai",
      "api" => "responses",
      "model" => "gpt-4o",
      "temperature" => 0.7,
      "tools" => ["web_search"]
    }
  end
end

trait :with_assistants do
  model_config do
    {
      "provider" => "openai",
      "api" => "assistants",
      "model" => "gpt-4o",
      "temperature" => 0.7
    }
  end
end
```

### Step 8: Update Test Specs

**File**: `spec/services/prompt_tracker/api_types_spec.rb`

```ruby
RSpec.describe PromptTracker::ApiTypes do
  describe ".from_config" do
    it "converts openai chat_completions" do
      expect(described_class.from_config(:openai, :chat_completions)).to eq(:openai_chat_completions)
    end

    it "converts openai responses" do
      expect(described_class.from_config(:openai, :responses)).to eq(:openai_responses)
    end

    it "converts openai assistants" do
      expect(described_class.from_config(:openai, :assistants)).to eq(:openai_assistants)
    end

    it "converts anthropic messages" do
      expect(described_class.from_config(:anthropic, :messages)).to eq(:anthropic_messages)
    end

    it "returns nil for unknown combinations" do
      expect(described_class.from_config(:unknown, :api)).to be_nil
    end
  end

  describe ".to_config" do
    it "converts api type to config format" do
      result = described_class.to_config(:openai_responses)
      expect(result).to eq({ provider: :openai, api: :responses })
    end
  end

  describe ".all" do
    it "returns all API types" do
      expect(described_class.all).to contain_exactly(
        :openai_chat_completions,
        :openai_responses,
        :openai_assistants,
        :anthropic_messages,
        :google_gemini
      )
    end
  end

  describe ".valid?" do
    it "returns true for valid API types" do
      expect(described_class.valid?(:openai_chat_completions)).to be true
      expect(described_class.valid?(:openai_responses)).to be true
    end

    it "returns false for invalid API types" do
      expect(described_class.valid?(:invalid_api)).to be false
      expect(described_class.valid?(nil)).to be false
    end
  end
end
```

---

## Global Find & Replace Tasks

### Task 1: Update All References to API Names

Use your IDE's "Find in Files" feature to replace:

1. **"response_api" → "responses"**
   - Search: `"response_api"` and `'response_api'` and `:response_api`
   - Replace with: `"responses"`, `'responses'`, `:responses`
   - Files to check:
     - `app/services/**/*.rb`
     - `app/controllers/**/*.rb`
     - `spec/**/*.rb`
     - `test/dummy/db/seeds/**/*.rb`

2. **"chat_completion" → "chat_completions"**
   - Search: `"chat_completion"` and `'chat_completion'` and `:chat_completion`
   - Replace with: `"chat_completions"`, `'chat_completions'`, `:chat_completions`
   - Same files as above

3. **"assistants_api" → "assistants"**
   - Search: `"assistants_api"` and `'assistants_api'` and `:assistants_api`
   - Replace with: `"assistants"`, `'assistants'`, `:assistants`
   - Same files as above

### Task 2: Update Constant Names in ApiTypes

After simplifying ApiTypes module, update any references to old constants:

- `ApiTypes::OPENAI_CHAT_COMPLETION` → No longer needed (use `ApiTypes.from_config` instead)
- `ApiTypes::OPENAI_RESPONSE_API` → No longer needed
- `ApiTypes::OPENAI_ASSISTANTS_API` → No longer needed
- `ApiTypes::SINGLE_RESPONSE_APIS` → Remove all usages
- `ApiTypes::CONVERSATIONAL_APIS` → Remove all usages

---

## Files That Need Updates

### Critical Files (Must Update)
1. ✅ `test/dummy/config/initializers/prompt_tracker.rb` - Configuration
2. ✅ `app/services/prompt_tracker/api_types.rb` - Simplify module
3. ✅ `app/models/prompt_tracker/prompt_version.rb` - Update api_type method
4. ✅ `app/services/prompt_tracker/playground_execute_service.rb` - Read separate fields
5. ✅ `app/javascript/prompt_tracker/controllers/playground_controller.js` - Update API names
6. ✅ `spec/factories/prompt_tracker/llm_responses.rb` - Update traits
7. ✅ `spec/factories/prompt_tracker/prompt_versions.rb` - Add new traits
8. ✅ `spec/services/prompt_tracker/api_types_spec.rb` - Update tests

### Files to Search & Replace
9. All service files in `app/services/prompt_tracker/`
10. All test files in `spec/services/`
11. All seed files in `test/dummy/db/seeds/`
12. Any documentation files in `docs/`

---

## Testing Checklist

After making all changes:

### Unit Tests
- [ ] Run: `bundle exec rspec spec/services/prompt_tracker/api_types_spec.rb`
- [ ] Run: `bundle exec rspec spec/models/prompt_tracker/prompt_version_spec.rb`
- [ ] Run: `bundle exec rspec spec/services/prompt_tracker/playground_execute_service_spec.rb`

### Integration Tests
- [ ] Drop and recreate database: `rails db:drop db:create db:migrate`
- [ ] Run seeds: `rails db:seed`
- [ ] Check that prompts are created with correct model_config format

### Browser Tests
- [ ] Start server: `rails s`
- [ ] Navigate to playground
- [ ] Select "OpenAI" provider
- [ ] Verify API dropdown shows "Chat Completions", "Responses", "Assistants"
- [ ] Select "Responses" API
- [ ] Verify tools checkboxes appear
- [ ] Save a prompt
- [ ] Check database: `PromptTracker::PromptVersion.last.model_config`
- [ ] Should see: `{"provider"=>"openai", "api"=>"responses", ...}`

### Full Test Suite
- [ ] Run: `bundle exec rspec`
- [ ] All tests should pass

---

## Success Criteria

Migration is successful when:

1. ✅ Configuration uses plural API names: `chat_completions`, `responses`, `assistants`
2. ✅ `model_config` stores separate `provider` and `api` fields
3. ✅ ApiTypes module is simplified (no SINGLE_RESPONSE_APIS, CONVERSATIONAL_APIS)
4. ✅ `api_type` method uses `ApiTypes.from_config(provider, api)`
5. ✅ PlaygroundExecuteService reads separate fields
6. ✅ All tests pass
7. ✅ Playground UI works correctly
8. ✅ Seeds create correct data format

---

## Estimated Effort

- **Step 1-8**: 2-3 hours (code changes)
- **Global Find & Replace**: 1 hour (careful search/replace)
- **Testing**: 1 hour (run tests, verify in browser)

**Total**: ~4-5 hours

---

## Notes

### Why Remove SINGLE_RESPONSE_APIS and CONVERSATIONAL_APIS?

These constants were created to categorize APIs, but they're not actually needed:

1. **Not used for routing**: We route based on the `api` field directly
2. **Not used for validation**: We validate using `ApiTypes.valid?`
3. **Not used for filtering**: Evaluators can check the api_type directly
4. **Adds complexity**: Maintaining these lists adds overhead

With separate `provider` and `api` fields, we can determine capabilities directly from the configuration.

### Why Plural API Names?

To match OpenAI's actual endpoint names:
- `/v1/chat/completions` → `chat_completions`
- `/v1/responses` → `responses`
- `/v1/assistants` → `assistants`

This makes the code more intuitive and easier to understand.
