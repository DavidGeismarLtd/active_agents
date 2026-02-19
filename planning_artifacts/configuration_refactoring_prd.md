# Configuration Refactoring PRD

## Overview

Refactor PromptTracker's configuration system to be more logically coherent by consolidating related concepts and eliminating fragmented configuration sections.

## Problem Statement

The current configuration structure spreads related concepts across multiple disconnected sections:

| Current Section | Purpose |
|-----------------|---------|
| `api_keys` | Provider API keys |
| `providers` | Provider names + APIs |
| `models` | Models per provider |
| `contexts` | Context restrictions |
| `defaults` | Default selections per context |

This creates cognitive overhead:
- To understand "OpenAI", you must look at 3 different sections
- To understand "playground context", you must cross-reference `contexts` and `defaults`
- The relationship between restrictions and defaults is unclear

## Goals

1. **Consolidate provider configuration**: All provider info (key, name, APIs, models) in one place
2. **Unify context configuration**: Merge restrictions and defaults into single context definitions
3. **Remove unused complexity**: Eliminate `allowed_providers`/`allowed_models` restriction system
4. **Group feature flags**: Prepare for future feature flags with a dedicated section
5. **Improve discoverability**: Make the initializer self-documenting

## Non-Goals

- Backward compatibility with old configuration format
- Changes to `ApiCapabilities` (tool capabilities remain hardcoded in engine)
- Changes to how `builtin_tools` metadata works

---

## Proposed Configuration Structure

### New Initializer Format

```ruby
PromptTracker.configure do |config|
  # ===========================================================================
  # 1. CORE SETTINGS
  # ===========================================================================
  config.prompts_path = Rails.root.join("app", "prompts")
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # ===========================================================================
  # 2. PROVIDERS
  # ===========================================================================
  # Each provider contains: api_key, display name, available APIs, and models.
  # A provider is only enabled if api_key is present.
  config.providers = {
    openai: {
      api_key: ENV["OPENAI_API_KEY"],
      name: "OpenAI",
      apis: {
        chat_completions: { name: "Chat Completions", description: "Standard chat API", default: true },
        responses: { name: "Responses", description: "Stateful conversations with built-in tools" },
        assistants: { name: "Assistants", description: "Full assistant features with threads" }
      },
      models: [
        { id: "gpt-4o", name: "GPT-4o", capabilities: [:structured_output, :vision, :function_calling],
          supported_apis: [:chat_completions, :responses, :assistants] },
        { id: "gpt-4o-mini", name: "GPT-4o Mini", capabilities: [:structured_output, :function_calling],
          supported_apis: [:chat_completions, :responses, :assistants] },
        { id: "gpt-4-turbo", name: "GPT-4 Turbo", capabilities: [:vision, :function_calling],
          supported_apis: [:chat_completions, :responses, :assistants] }
      ]
    },
    anthropic: {
      api_key: ENV["ANTHROPIC_API_KEY"],
      name: "Anthropic",
      apis: {
        messages: { name: "Messages", description: "Claude chat API", default: true }
      },
      models: [
        { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", capabilities: [:structured_output, :function_calling] },
        { id: "claude-opus-4-1", name: "Claude Opus 4.1", capabilities: [:structured_output, :function_calling] }
      ]
    }
  }

  # ===========================================================================
  # 3. CONTEXTS
  # ===========================================================================
  # Usage scenarios with their default selections.
  # Each context specifies which provider/api/model to use by default.
  config.contexts = {
    playground: {
      description: "Prompt version testing in the playground",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    llm_judge: {
      description: "LLM-as-judge evaluation of responses",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    dataset_generation: {
      description: "Generating test dataset rows via LLM",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    prompt_generation: {
      description: "AI-assisted prompt creation and enhancement",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o-mini"
    }
  }

  # ===========================================================================
  # 4. FEATURE FLAGS
  # ===========================================================================
  config.features = {
    openai_assistant_sync: true  # Show "Sync OpenAI Assistants" button
  }

  # ===========================================================================
  # 5. TOOL UI METADATA (Optional - defaults provided by engine)
  # ===========================================================================
  # config.builtin_tools = {
  #   web_search: { name: "Web Search", description: "...", icon: "bi-globe" },
  #   ...
  # }
end
```

---

## Configuration Class Changes

### Removed Attributes

| Attribute | Reason |
|-----------|--------|
| `api_keys` | Merged into `providers[:provider_name][:api_key]` |
| `models` | Merged into `providers[:provider_name][:models]` |
| `defaults` | Merged into `contexts[:context_name][:default_*]` |
| `enable_openai_assistant_sync` | Moved to `features[:openai_assistant_sync]` |

### New/Modified Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `providers` | Hash | Nested provider configuration (api_key, name, apis, models) |
| `contexts` | Hash | Context definitions with defaults |
| `features` | Hash | Feature flags |

### Removed Methods (Breaking Changes)

```ruby
# These methods will be removed:
api_keys
api_keys=
api_key_for(provider)
configured_providers  # replaced by enabled_providers
models
models=
defaults
defaults=
default_model_for(context)      # replaced
default_provider_for(context)   # replaced
default_api_for(context)        # replaced
providers_for(context)          # removed - no more context restrictions
models_for(context, provider:)  # simplified - no more context restrictions

# All deprecated backward compatibility methods removed:
available_models / available_models=
provider_api_key_env_vars / provider_api_key_env_vars=
prompt_generator_model / prompt_generator_model=
llm_judge_model / llm_judge_model=
dataset_generator_model / dataset_generator_model=
dataset_generator_provider / dataset_generator_provider=
dataset_generator_api / dataset_generator_api=
```

### New Method Signatures

```ruby
class Configuration
  attr_accessor :prompts_path
  attr_accessor :basic_auth_username
  attr_accessor :basic_auth_password
  attr_accessor :providers
  attr_accessor :contexts
  attr_accessor :features
  attr_accessor :builtin_tools

  # Provider methods
  def provider_configured?(provider)
    # Checks if provider has api_key present
  end

  def enabled_providers
    # Returns array of provider symbols that have api_keys configured
    # e.g., [:openai, :anthropic]
  end

  def api_key_for(provider)
    # Returns the api_key for a provider
    providers.dig(provider.to_sym, :api_key)
  end

  def provider_name(provider)
    # Returns display name for provider
    providers.dig(provider.to_sym, :name) || provider.to_s.titleize
  end

  def apis_for(provider)
    # Returns array of API hashes for a provider
    # e.g., [{ key: :chat_completions, name: "Chat Completions", default: true }, ...]
  end

  def default_api_for_provider(provider)
    # Returns the default API key for a provider
  end

  def models_for_provider(provider)
    # Returns all models for a provider
    providers.dig(provider.to_sym, :models) || []
  end

  def models_for_api(provider, api)
    # Returns models compatible with a specific API
    # Filters by supported_apis if present
  end

  # Context methods
  def context_default(context, attribute)
    # Generic accessor for context defaults
    # e.g., context_default(:playground, :model) => "gpt-4o"
    contexts.dig(context.to_sym, :"default_#{attribute}")
  end

  def default_provider_for(context)
    context_default(context, :provider)
  end

  def default_api_for(context)
    context_default(context, :api)
  end

  def default_model_for(context)
    context_default(context, :model)
  end

  # Feature flag methods
  def feature_enabled?(feature)
    features[feature.to_sym] == true
  end

  # Combined provider/API methods (kept from current implementation)
  def build_provider_api_key(provider, api)
  def parse_provider_api_key(combined_key)
  def all_provider_api_options
  def tools_for_api(provider, api)
end
```

---

## Migration Guide

### Files to Update

| File | Changes Required |
|------|------------------|
| `lib/prompt_tracker/configuration.rb` | Complete rewrite of Configuration class |
| `test/dummy/config/initializers/prompt_tracker.rb` | Update to new format |
| All files calling `config.api_keys` | Use `api_key_for(provider)` or access via `providers` |
| All files calling `config.models` | Use `models_for_provider(provider)` |
| All files calling `config.defaults` | Use `context_default(context, attr)` or specific helpers |
| All files calling deprecated methods | Update to new API |
| Specs for Configuration | Rewrite specs |

### Search Patterns for Code Updates

```bash
# Find all usages of old configuration patterns:
grep -r "config\.api_keys" --include="*.rb"
grep -r "config\.models" --include="*.rb"
grep -r "config\.defaults" --include="*.rb"
grep -r "configured_providers" --include="*.rb"
grep -r "providers_for" --include="*.rb"
grep -r "models_for(" --include="*.rb"
grep -r "enable_openai_assistant_sync" --include="*.rb"
```

---

## Implementation Tasks

### Phase 1: Configuration Class Rewrite
- [ ] Rewrite `lib/prompt_tracker/configuration.rb` with new structure
- [ ] Remove all deprecated methods
- [ ] Update `initialize` method with new defaults
- [ ] Implement new helper methods

### Phase 2: Initializer Update
- [ ] Update `test/dummy/config/initializers/prompt_tracker.rb` to new format
- [ ] Verify all providers/models are correctly migrated

### Phase 3: Update Callers
- [ ] Search for and update all `config.api_keys` usages
- [ ] Search for and update all `config.models` usages
- [ ] Search for and update all `config.defaults` usages
- [ ] Search for and update all deprecated method calls
- [ ] Update feature flag checks to use `feature_enabled?`

### Phase 4: Update Specs
- [ ] Rewrite `spec/lib/prompt_tracker/configuration_spec.rb`
- [ ] Update any other specs that mock/stub configuration

### Phase 5: Documentation
- [ ] Update any README sections about configuration
- [ ] Ensure initializer is well-commented as documentation

---

## Example Usages After Refactoring

### Getting API Key for a Provider

```ruby
# Before:
PromptTracker.configuration.api_keys[:openai]

# After:
PromptTracker.configuration.api_key_for(:openai)
# or
PromptTracker.configuration.providers[:openai][:api_key]
```

### Getting Models for a Provider

```ruby
# Before:
PromptTracker.configuration.models[:openai]

# After:
PromptTracker.configuration.models_for_provider(:openai)
```

### Getting Default Model for a Context

```ruby
# Before:
PromptTracker.configuration.defaults[:playground_model]

# After:
PromptTracker.configuration.default_model_for(:playground)
# or
PromptTracker.configuration.context_default(:playground, :model)
```

### Checking Feature Flags

```ruby
# Before:
PromptTracker.configuration.enable_openai_assistant_sync

# After:
PromptTracker.configuration.feature_enabled?(:openai_assistant_sync)
```

### Getting All Enabled Providers

```ruby
# Before:
PromptTracker.configuration.configured_providers

# After:
PromptTracker.configuration.enabled_providers
```

---

## Acceptance Criteria

1. **New Configuration Format Works**
   - Initializer uses new nested `providers` structure
   - Initializer uses new `contexts` structure with defaults
   - Initializer uses `features` hash for feature flags

2. **All Helper Methods Work**
   - `enabled_providers` returns providers with API keys
   - `api_key_for(provider)` returns correct key
   - `models_for_provider(provider)` returns correct models
   - `models_for_api(provider, api)` filters by `supported_apis`
   - `default_*_for(context)` methods return correct defaults
   - `feature_enabled?(feature)` works correctly

3. **No Deprecated Code Remains**
   - All backward compatibility methods removed
   - No `config.api_keys`, `config.models`, `config.defaults` direct access
   - No `providers_for(context)` or context restriction logic

4. **All Tests Pass**
   - Configuration specs updated and passing
   - All existing functionality works with new configuration

5. **Clean Initializer**
   - Self-documenting with clear sections
   - No redundancy between sections
   - Easy to add new providers
