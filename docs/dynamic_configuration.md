# Dynamic Configuration for Multi-Tenant Applications

PromptTracker supports dynamic, context-aware configuration through the `configuration_provider` option. This is essential for multi-tenant applications where API keys and settings differ per organization, user, or request context.

## The Problem

In a typical static configuration, API keys are set once at application boot:

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  config.providers = {
    openai: { api_key: ENV["OPENAI_API_KEY"] }  # Same key for all requests
  }
end
```

This doesn't work for multi-tenant apps where each organization has its own API keys.

## The Solution: Configuration Provider

A `configuration_provider` is a callable (Proc/Lambda) that PromptTracker calls at runtime to get context-specific configuration:

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # Static settings that don't change per-request
  config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]

  # Dynamic configuration provider - called at runtime for each request
  config.configuration_provider = -> {
    # Access your request-scoped context (e.g., Rails Current attributes)
    org = Current.organization
    
    {
      providers: {
        openai: { api_key: org.openai_api_key },
        anthropic: { api_key: org.anthropic_api_key },
        google: { api_key: org.google_api_key }
      },
      contexts: {
        playground: {
          default_provider: org.default_llm_provider&.to_sym || :openai,
          default_model: org.default_model || "gpt-4o"
        }
      },
      features: {
        openai_assistant_sync: org.openai_assistant_sync_enabled?
      }
    }
  }
end
```

## How It Works

1. When PromptTracker needs configuration (e.g., to get an API key), it checks if `configuration_provider` is set
2. If set, it calls the provider and uses the returned values, falling back to static config for missing keys
3. If not set, it uses the static `config.providers`, `config.contexts`, etc.

### Configuration Keys

The `configuration_provider` should return a Hash with these optional keys:

| Key | Type | Description |
|-----|------|-------------|
| `providers` | Hash | Provider configs with API keys (overrides `config.providers`) |
| `contexts` | Hash | Context defaults (overrides `config.contexts`) |
| `features` | Hash | Feature flags (overrides `config.features`) |

## Setting Up Request-Scoped Context

PromptTracker doesn't dictate how you set up your request context. Common patterns:

### Using Rails CurrentAttributes

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :organization
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :set_current_organization
  
  private
  
  def set_current_organization
    Current.organization = current_user&.organization
  end
end
```

### Using Thread-Local Storage

```ruby
# In middleware or controller
Thread.current[:current_organization] = organization

# In configuration_provider
config.configuration_provider = -> {
  org = Thread.current[:current_organization]
  return {} unless org  # Fall back to static config
  
  { providers: { openai: { api_key: org.openai_api_key } } }
}
```

## Complete Example

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # 1. STATIC SETTINGS (applied to all requests)
  config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]
  
  # 2. DYNAMIC CONFIGURATION PROVIDER
  config.configuration_provider = -> {
    org = Current.organization
    
    # Return empty hash to use static fallbacks when no org context
    return {} unless org
    
    {
      providers: {
        openai: { 
          api_key: org.openai_api_key,
          # You can also override provider names, APIs, etc.
          name: "#{org.name}'s OpenAI"
        },
        anthropic: { api_key: org.anthropic_api_key }
      },
      contexts: {
        playground: {
          default_provider: org.playground_provider&.to_sym,
          default_api: org.playground_api&.to_sym,
          default_model: org.playground_model
        },
        llm_judge: {
          default_provider: :openai,
          default_model: org.llm_judge_model || "gpt-4o"
        }
      },
      features: {
        openai_assistant_sync: org.feature_enabled?(:assistant_sync)
      }
    }
  }
  
  # 3. STATIC FALLBACKS (used when configuration_provider returns nil/empty)
  config.providers = {
    openai: { api_key: ENV["OPENAI_API_KEY"] },
    anthropic: { api_key: ENV["ANTHROPIC_API_KEY"] }
  }
  
  config.contexts = {
    playground: { default_provider: :openai, default_model: "gpt-4o" }
  }
end
```

## API Reference

### Configuration Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `dynamic_configuration?` | Boolean | `true` if `configuration_provider` is set |
| `effective_providers` | Hash | Dynamic providers if available, else static |
| `effective_contexts` | Hash | Dynamic contexts if available, else static |
| `effective_features` | Hash | Dynamic features if available, else static |
| `ruby_llm_config` | Hash | RubyLLM-compatible config from effective providers |

### Internal Behavior

All configuration accessor methods (`api_key_for`, `enabled_providers`, `provider_name`, etc.) automatically use the effective configuration, so existing code works without changes.

