# Configuration Object Redesign

## Overview

This document details the complete redesign of the PromptTracker configuration object to support context-aware model selection across different features of the application.

## Goals

1. **End Users** should be able to:
   - Select provider and model when creating prompt versions (Playground)
   - Select model when creating an OpenAI Assistant
   - Select provider/model when creating an LLM-as-a-Judge evaluator

2. **Developers/Configurators** should be able to:
   - Define available providers/models for prompt version creation
   - Define available models for OpenAI Assistant creation
   - Define available providers/models for LLM Judge evaluators
   - Define which model to use for dataset row generation
   - Define which model to use for AI-powered prompt generation
   - Configure all API keys in one place

3. **Application Logic** must:
   - Only show options that are both configured AND have valid API keys
   - Support context-specific model restrictions
   - Support capability-based filtering (e.g., only models supporting structured output)

---

## New Configuration Structure

### Complete Configuration Example

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # ===========================================================================
  # Path Configuration
  # ===========================================================================
  config.prompts_path = Rails.root.join("app", "prompts")

  # ===========================================================================
  # Authentication
  # ===========================================================================
  config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]

  # ===========================================================================
  # API Keys (REQUIRED)
  # ===========================================================================
  # Direct API key configuration. A provider is only available if its key is set.
  config.api_keys = {
    openai: ENV["OPENAI_API_KEY"],
    anthropic: ENV["ANTHROPIC_API_KEY"],
    google: ENV["GOOGLE_API_KEY"]
  }

  # ===========================================================================
  # Master Model Registry (REQUIRED)
  # ===========================================================================
  # All available models in the system. Each model can have capabilities.
  # Capabilities are used for filtering in specific contexts.
  #
  # Supported capabilities:
  #   - :chat - Standard chat completion
  #   - :structured_output - Supports JSON schema / structured outputs
  #   - :vision - Supports image inputs
  #   - :function_calling - Supports function/tool calling
  #
  config.models = {
    openai: [
      { id: "gpt-4o", name: "GPT-4o", category: "Latest",
        capabilities: [:chat, :structured_output, :vision, :function_calling] },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest",
        capabilities: [:chat, :structured_output, :vision, :function_calling] },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4",
        capabilities: [:chat, :vision, :function_calling] },
      { id: "gpt-4", name: "GPT-4", category: "GPT-4",
        capabilities: [:chat, :function_calling] },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5",
        capabilities: [:chat, :function_calling] }
    ],
    anthropic: [
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5",
        capabilities: [:chat, :structured_output, :vision] },
      { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", category: "Claude 3.5",
        capabilities: [:chat, :structured_output] },
      { id: "claude-3-opus-20240229", name: "Claude 3 Opus", category: "Claude 3",
        capabilities: [:chat, :vision] }
    ],
    google: [
      { id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash", category: "Gemini 2.0",
        capabilities: [:chat, :structured_output] },
      { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", category: "Gemini 1.5",
        capabilities: [:chat, :structured_output, :vision] }
    ]
  }

  # ===========================================================================
  # OpenAI Assistants Configuration (OPTIONAL)
  # ===========================================================================
  # Separate configuration for OpenAI Assistants API.
  # This can use a different API key than the chat completions.
  #
  config.openai_assistants = {
    api_key: ENV["OPENAI_API_KEY"],  # Can be different org/project key
    available_models: [
      { id: "gpt-4o", name: "GPT-4o" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini" },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo" },
      { id: "gpt-4", name: "GPT-4" },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo" }
    ]
  }

  # ===========================================================================
  # Context-Specific Model Restrictions (OPTIONAL)
  # ===========================================================================
  # Restrict which models appear in specific UI contexts.
  # If a context is not defined, all configured models are available.
  #
  # Options:
  #   - providers: Array of provider symbols to include (nil = all)
  #   - models: Array of model IDs to include (nil = all from providers)
  #   - require_capability: Only include models with this capability
  #
  config.contexts = {
    # Playground: prompt version testing
    playground: {
      providers: nil,  # All configured providers
      models: nil,     # All models from those providers
      require_capability: nil
    },

    # LLM Judge: evaluating responses
    llm_judge: {
      providers: [:openai, :anthropic],
      models: nil,
      require_capability: :structured_output  # Must support structured output
    },

    # Dataset Generation: generating test data rows
    dataset_generation: {
      providers: [:openai],
      models: ["gpt-4o", "gpt-4o-mini"],
      require_capability: :structured_output
    },

    # Prompt Generation: AI-assisted prompt creation
    prompt_generation: {
      providers: [:openai],
      models: ["gpt-4o-mini"],
      require_capability: nil
    }
  }

  # ===========================================================================
  # Default Models (OPTIONAL)
  # ===========================================================================
  # Default model selections for each context.
  # Used when no model is explicitly selected.
  #
  config.defaults = {
    playground_provider: :openai,
    playground_model: "gpt-4o",
    llm_judge_model: "gpt-4o",
    dataset_generator_model: "gpt-4o",
    prompt_generator_model: "gpt-4o-mini"
  }
end
```

---

## Configuration Class API

The new `Configuration` class provides these query methods:

### Core Query Methods

```ruby
# Check if a provider has a valid API key configured
config.provider_configured?(provider)
# => true/false

# Get all configured providers (those with API keys)
config.configured_providers
# => [:openai, :anthropic]

# Get available providers for a specific context
config.providers_for(context)
# => [:openai, :anthropic]  # Filtered by context restrictions AND API key presence

# Get available models for a context
config.models_for(context)
# => { openai: [{id: "gpt-4o", ...}], anthropic: [{id: "claude-3-5-sonnet", ...}] }

# Get available models for a context and specific provider
config.models_for(context, provider: :openai)
# => [{id: "gpt-4o", name: "GPT-4o", ...}, ...]

# Get the default model for a context
config.default_model_for(context)
# => "gpt-4o"

# Get the default provider for a context (where applicable)
config.default_provider_for(context)
# => :openai
```

### OpenAI Assistants Methods

```ruby
# Check if OpenAI Assistants is configured
config.openai_assistants_configured?
# => true/false

# Get available models for assistants
config.openai_assistants_models
# => [{id: "gpt-4o", name: "GPT-4o"}, ...]
```

---

## Files to Update

### 1. Configuration Core

| File | Action | Description |
|------|--------|-------------|
| `lib/prompt_tracker/configuration.rb` | **REWRITE** | Complete rewrite with new attributes and query methods |
| `lib/generators/prompt_tracker/install/templates/prompt_tracker.rb` | **REWRITE** | New initializer template for fresh installations |
| `test/dummy/config/initializers/prompt_tracker.rb` | **REWRITE** | Update test app configuration |

### 2. Helpers

| File | Action | Description |
|------|--------|-------------|
| `app/helpers/prompt_tracker/application_helper.rb` | **UPDATE** | Remove old `provider_api_key_present?` and `available_providers`, add new context-aware helpers |

### 3. Controllers

| File | Action | Description |
|------|--------|-------------|
| `app/controllers/prompt_tracker/testing/playground_controller.rb` | **UPDATE** | Use new `providers_for(:playground)` |
| `app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb` | **UPDATE** | Use `config.openai_assistants_models` instead of hardcoded list |

### 4. Views

| File | Action | Description |
|------|--------|-------------|
| `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb` | **UPDATE** | Use new helper methods |
| `app/views/prompt_tracker/testing/openai/assistant_playground/show.html.erb` | **UPDATE** | Use configuration for model dropdown |
| `app/views/prompt_tracker/evaluator_configs/forms/_llm_judge.html.erb` | **UPDATE** | Use `models_for(:llm_judge)` |

### 5. Services

| File | Action | Description |
|------|--------|-------------|
| `app/services/prompt_tracker/prompt_generator_service.rb` | **UPDATE** | Use `config.default_model_for(:prompt_generation)` |
| `app/services/prompt_tracker/dataset_row_generator_service.rb` | **UPDATE** | Use `config.default_model_for(:dataset_generation)` |
| `app/services/prompt_tracker/evaluators/llm_judge_evaluator.rb` | **UPDATE** | Use `config.default_model_for(:llm_judge)` |
| `app/services/prompt_tracker/evaluators/conversation_judge_evaluator.rb` | **UPDATE** | Use `config.default_model_for(:llm_judge)` |
| `app/services/prompt_tracker/llm_client_service.rb` | **UPDATE** | Use `config.api_keys` for validation |

### 6. Jobs

| File | Action | Description |
|------|--------|-------------|
| `app/jobs/prompt_tracker/generate_dataset_rows_job.rb` | **REVIEW** | May need to pass model from configuration |

---

## Detailed File Changes

### `lib/prompt_tracker/configuration.rb`

**Remove:**
- `attr_accessor :available_models`
- `attr_accessor :provider_api_key_env_vars`
- `attr_accessor :prompt_generator_model`
- `attr_accessor :dataset_generator_model`
- `attr_accessor :llm_judge_model`
- `attr_accessor :openai_api_key`
- `attr_accessor :anthropic_api_key`
- `attr_accessor :google_api_key`
- `attr_accessor :openai_assistants_api_key`

**Add:**
- `attr_accessor :api_keys` - Hash of provider => API key
- `attr_accessor :models` - Hash of provider => array of model definitions
- `attr_accessor :openai_assistants` - Hash with `api_key` and `available_models`
- `attr_accessor :contexts` - Hash of context => restrictions
- `attr_accessor :defaults` - Hash of default settings

**Add Methods:**
- `provider_configured?(provider)` - Check if provider has API key
- `configured_providers` - List all providers with API keys
- `providers_for(context)` - Get providers for a context
- `models_for(context, provider: nil)` - Get models for a context
- `default_model_for(context)` - Get default model for context
- `default_provider_for(context)` - Get default provider for context
- `openai_assistants_configured?` - Check if assistants API is configured
- `openai_assistants_models` - Get models for assistants

### `app/helpers/prompt_tracker/application_helper.rb`

**Remove:**
- `provider_api_key_present?(provider)` - Replaced by `config.provider_configured?`
- `available_providers` - Replaced by context-aware `providers_for`

**Add:**
- `providers_for(context)` - Delegate to configuration
- `models_for(context, provider: nil)` - Delegate to configuration
- `default_model_for(context)` - Delegate to configuration
- `default_provider_for(context)` - Delegate to configuration

### `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb`

**Before:**
```erb
<% all_available_models = PromptTracker.configuration.available_models %>
<% available_providers_list = @available_providers %>
```

**After:**
```erb
<% available_providers_list = providers_for(:playground) %>
<% all_available_models = models_for(:playground) %>
<% default_provider = default_provider_for(:playground) %>
<% default_model = default_model_for(:playground) %>
```

### `app/views/prompt_tracker/evaluator_configs/forms/_llm_judge.html.erb`

**Before:**
```erb
<% all_models = PromptTracker.configuration.available_models %>
<% if provider_api_key_present?(provider_key.to_s) %>
```

**After:**
```erb
<% all_models = models_for(:llm_judge) %>
<!-- No need to check API key - models_for already filters -->
```

### `app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb`

**Before:**
```ruby
@available_models = [
  { id: "gpt-4o", name: "GPT-4o" },
  { id: "gpt-4-turbo", name: "GPT-4 Turbo" },
  # ... hardcoded
]
```

**After:**
```ruby
@available_models = PromptTracker.configuration.openai_assistants_models
```

### `app/services/prompt_tracker/prompt_generator_service.rb`

**Before:**
```ruby
DEFAULT_MODEL = ENV.fetch("PROMPT_GENERATOR_MODEL", "gpt-4o-mini")
```

**After:**
```ruby
def self.default_model
  PromptTracker.configuration.default_model_for(:prompt_generation) || "gpt-4o-mini"
end
```

### `app/services/prompt_tracker/dataset_row_generator_service.rb`

**Before:**
```ruby
DEFAULT_MODEL = "gpt-4o"
```

**After:**
```ruby
def self.default_model
  PromptTracker.configuration.default_model_for(:dataset_generation) || "gpt-4o"
end
```

### `app/services/prompt_tracker/evaluators/llm_judge_evaluator.rb`

**Before:**
```ruby
DEFAULT_CONFIG = {
  judge_model: "gpt-4o",
  # ...
}.freeze
```

**After:**
```ruby
def self.default_config
  {
    judge_model: PromptTracker.configuration.default_model_for(:llm_judge) || "gpt-4o",
    custom_instructions: "Evaluate the quality and appropriateness of the response"
  }.freeze
end
```

---

## Testing Strategy

### 1. Unit Tests for Configuration Class

**File:** `spec/lib/prompt_tracker/configuration_spec.rb`

```ruby
RSpec.describe PromptTracker::Configuration do
  let(:config) { described_class.new }

  before do
    config.api_keys = {
      openai: "sk-test-openai",
      anthropic: "sk-test-anthropic",
      google: nil  # Not configured
    }

    config.models = {
      openai: [
        { id: "gpt-4o", name: "GPT-4o", category: "Latest", capabilities: [:chat, :structured_output] },
        { id: "gpt-4", name: "GPT-4", category: "GPT-4", capabilities: [:chat] }
      ],
      anthropic: [
        { id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", capabilities: [:chat, :structured_output] }
      ],
      google: [
        { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", capabilities: [:chat] }
      ]
    }

    config.contexts = {
      playground: { providers: nil, models: nil, require_capability: nil },
      llm_judge: { providers: [:openai], models: nil, require_capability: :structured_output }
    }

    config.defaults = {
      playground_provider: :openai,
      playground_model: "gpt-4o",
      llm_judge_model: "gpt-4o"
    }
  end

  describe "#provider_configured?" do
    it "returns true for providers with API keys" do
      expect(config.provider_configured?(:openai)).to be true
      expect(config.provider_configured?(:anthropic)).to be true
    end

    it "returns false for providers without API keys" do
      expect(config.provider_configured?(:google)).to be false
    end

    it "returns false for unknown providers" do
      expect(config.provider_configured?(:unknown)).to be false
    end
  end

  describe "#configured_providers" do
    it "returns only providers with API keys" do
      expect(config.configured_providers).to contain_exactly(:openai, :anthropic)
    end
  end

  describe "#providers_for" do
    context "when context has no restrictions" do
      it "returns all configured providers" do
        expect(config.providers_for(:playground)).to contain_exactly(:openai, :anthropic)
      end
    end

    context "when context has provider restrictions" do
      it "returns only allowed providers that are also configured" do
        expect(config.providers_for(:llm_judge)).to contain_exactly(:openai)
      end
    end
  end

  describe "#models_for" do
    context "without provider filter" do
      it "returns models from all available providers for context" do
        result = config.models_for(:playground)
        expect(result.keys).to contain_exactly(:openai, :anthropic)
        expect(result[:openai].map { |m| m[:id] }).to include("gpt-4o", "gpt-4")
      end
    end

    context "with provider filter" do
      it "returns only models from that provider" do
        result = config.models_for(:playground, provider: :openai)
        expect(result).to be_an(Array)
        expect(result.map { |m| m[:id] }).to include("gpt-4o", "gpt-4")
      end
    end

    context "when context requires a capability" do
      it "filters models by capability" do
        result = config.models_for(:llm_judge)
        # Only gpt-4o has structured_output, not gpt-4
        expect(result[:openai].map { |m| m[:id] }).to include("gpt-4o")
        expect(result[:openai].map { |m| m[:id] }).not_to include("gpt-4")
      end
    end
  end

  describe "#default_model_for" do
    it "returns the default model for the context" do
      expect(config.default_model_for(:playground)).to eq("gpt-4o")
      expect(config.default_model_for(:llm_judge)).to eq("gpt-4o")
    end

    it "returns nil for unknown context" do
      expect(config.default_model_for(:unknown)).to be_nil
    end
  end

  describe "#openai_assistants_configured?" do
    context "when openai_assistants is configured with API key" do
      before do
        config.openai_assistants = {
          api_key: "sk-test",
          available_models: [{ id: "gpt-4o", name: "GPT-4o" }]
        }
      end

      it "returns true" do
        expect(config.openai_assistants_configured?).to be true
      end
    end

    context "when openai_assistants has no API key" do
      before do
        config.openai_assistants = { api_key: nil, available_models: [] }
      end

      it "returns false" do
        expect(config.openai_assistants_configured?).to be false
      end
    end
  end

  describe "#openai_assistants_models" do
    before do
      config.openai_assistants = {
        api_key: "sk-test",
        available_models: [
          { id: "gpt-4o", name: "GPT-4o" },
          { id: "gpt-4-turbo", name: "GPT-4 Turbo" }
        ]
      }
    end

    it "returns the configured models" do
      expect(config.openai_assistants_models.length).to eq(2)
      expect(config.openai_assistants_models.first[:id]).to eq("gpt-4o")
    end
  end
end
```

### 2. Helper Tests

**File:** `spec/helpers/prompt_tracker/application_helper_spec.rb`

Update existing tests to use new methods:

```ruby
describe "#providers_for" do
  before do
    PromptTracker.configuration.api_keys = {
      openai: "sk-test",
      anthropic: "sk-ant-test",
      google: nil
    }
    PromptTracker.configuration.models = {
      openai: [{ id: "gpt-4o", name: "GPT-4o", capabilities: [:chat] }],
      anthropic: [{ id: "claude", name: "Claude", capabilities: [:chat] }],
      google: [{ id: "gemini", name: "Gemini", capabilities: [:chat] }]
    }
    PromptTracker.configuration.contexts = {
      playground: { providers: nil, models: nil, require_capability: nil }
    }
  end

  it "returns providers for playground context" do
    expect(helper.providers_for(:playground)).to contain_exactly(:openai, :anthropic)
  end
end

describe "#models_for" do
  # Similar tests for models_for helper
end
```

### 3. Integration Tests for Views

**File:** `spec/views/prompt_tracker/testing/playground/_model_config_form.html.erb_spec.rb`

```ruby
RSpec.describe "prompt_tracker/testing/playground/_model_config_form", type: :view do
  before do
    PromptTracker.configuration.api_keys = { openai: "sk-test" }
    PromptTracker.configuration.models = {
      openai: [
        { id: "gpt-4o", name: "GPT-4o", category: "Latest", capabilities: [:chat] },
        { id: "gpt-4", name: "GPT-4", category: "GPT-4", capabilities: [:chat] }
      ]
    }
    PromptTracker.configuration.contexts = {
      playground: { providers: nil, models: nil, require_capability: nil }
    }
    PromptTracker.configuration.defaults = {
      playground_provider: :openai,
      playground_model: "gpt-4o"
    }
  end

  it "renders provider dropdown with configured providers" do
    render partial: "prompt_tracker/testing/playground/model_config_form"

    expect(rendered).to have_select("model-provider", with_options: ["Openai"])
    expect(rendered).not_to have_select("model-provider", with_options: ["Anthropic"])
  end

  it "renders model dropdown with configured models" do
    render partial: "prompt_tracker/testing/playground/model_config_form"

    expect(rendered).to have_select("model-name", with_options: ["GPT-4o", "GPT-4"])
  end
end
```

### 4. Service Tests

**File:** `spec/services/prompt_tracker/prompt_generator_service_spec.rb`

```ruby
describe ".default_model" do
  context "when configured in defaults" do
    before do
      PromptTracker.configuration.defaults = { prompt_generator_model: "gpt-4o-mini" }
    end

    it "returns the configured model" do
      expect(described_class.default_model).to eq("gpt-4o-mini")
    end
  end

  context "when not configured" do
    before do
      PromptTracker.configuration.defaults = {}
    end

    it "returns the fallback model" do
      expect(described_class.default_model).to eq("gpt-4o-mini")
    end
  end
end
```

### 5. Controller Tests

**File:** `spec/controllers/prompt_tracker/testing/openai/assistant_playground_controller_spec.rb`

```ruby
describe "GET #show" do
  before do
    PromptTracker.configuration.openai_assistants = {
      api_key: "sk-test",
      available_models: [
        { id: "gpt-4o", name: "GPT-4o" },
        { id: "gpt-4-turbo", name: "GPT-4 Turbo" }
      ]
    }
  end

  it "sets @available_models from configuration" do
    get :show, params: { assistant_id: assistant.id }

    expect(assigns(:available_models).length).to eq(2)
    expect(assigns(:available_models).first[:id]).to eq("gpt-4o")
  end
end
```

---

## Test Execution Plan

### Phase 1: Configuration Core Tests
```bash
# Run configuration spec only
bundle exec rspec spec/lib/prompt_tracker/configuration_spec.rb
```

### Phase 2: Helper Tests
```bash
# Run helper specs
bundle exec rspec spec/helpers/prompt_tracker/application_helper_spec.rb
```

### Phase 3: View Tests
```bash
# Run view specs
bundle exec rspec spec/views/prompt_tracker/
```

### Phase 4: Service Tests
```bash
# Run service specs related to configuration
bundle exec rspec spec/services/prompt_tracker/prompt_generator_service_spec.rb
bundle exec rspec spec/services/prompt_tracker/dataset_row_generator_service_spec.rb
bundle exec rspec spec/services/prompt_tracker/evaluators/
```

### Phase 5: Controller Tests
```bash
# Run controller specs
bundle exec rspec spec/controllers/prompt_tracker/
```

### Phase 6: Full Test Suite
```bash
# Run all tests to ensure no regressions
bundle exec rspec
```

---

## Implementation Order

1. **Configuration Class** - Rewrite `lib/prompt_tracker/configuration.rb`
2. **Configuration Spec** - Create/update `spec/lib/prompt_tracker/configuration_spec.rb`
3. **Verify Configuration Tests Pass**
4. **Helper Updates** - Update `app/helpers/prompt_tracker/application_helper.rb`
5. **Helper Spec Updates** - Update helper specs
6. **Verify Helper Tests Pass**
7. **View Updates** - Update all view files
8. **Service Updates** - Update all service files
9. **Controller Updates** - Update all controller files
10. **Initializer Templates** - Update template files
11. **Run Full Test Suite**
12. **Manual Testing** - Test in browser

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PromptTracker Configuration                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐   ┌─────────────────────────────────────────────────┐ │
│  │    api_keys     │   │                    models                       │ │
│  ├─────────────────┤   ├─────────────────────────────────────────────────┤ │
│  │ openai: "sk-x"  │   │ openai:                                         │ │
│  │ anthropic:"sk-y"│   │   - { id: gpt-4o, capabilities: [:chat, :so] } │ │
│  │ google: nil     │   │   - { id: gpt-4, capabilities: [:chat] }       │ │
│  └─────────────────┘   │ anthropic:                                      │ │
│                        │   - { id: claude-3-5-sonnet, ... }              │ │
│                        │ google:                                         │ │
│                        │   - { id: gemini-1.5-pro, ... }                 │ │
│                        └─────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────────────────────────┐   ┌─────────────────────────────────┐ │
│  │         openai_assistants       │   │           defaults              │ │
│  ├─────────────────────────────────┤   ├─────────────────────────────────┤ │
│  │ api_key: "sk-asst"              │   │ playground_provider: :openai    │ │
│  │ available_models:               │   │ playground_model: "gpt-4o"      │ │
│  │   - { id: gpt-4o }              │   │ llm_judge_model: "gpt-4o"       │ │
│  │   - { id: gpt-4-turbo }         │   │ dataset_generator_model: ...    │ │
│  └─────────────────────────────────┘   └─────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                            contexts                                    │ │
│  ├───────────────────────────────────────────────────────────────────────┤ │
│  │                                                                       │ │
│  │  playground:           llm_judge:              dataset_generation:    │ │
│  │  ┌─────────────────┐   ┌─────────────────────┐ ┌────────────────────┐ │ │
│  │  │ providers: nil  │   │ providers: [:openai,│ │ providers: [:openai]│ │ │
│  │  │ models: nil     │   │            :anthro] │ │ models: [gpt-4o,   │ │ │
│  │  │ require: nil    │   │ require: :struct_out│ │         gpt-4o-mini]│ │ │
│  │  └─────────────────┘   └─────────────────────┘ │ require: :struct_out│ │ │
│  │                                                └────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    ▼
                         ┌─────────────────────┐
                         │   Query Methods     │
                         ├─────────────────────┤
                         │ providers_for(:ctx) │
                         │ models_for(:ctx)    │
                         │ default_model_for() │
                         └─────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │  Playground  │ │  LLM Judge   │ │  Assistant   │
            │     View     │ │    Form      │ │  Playground  │
            └──────────────┘ └──────────────┘ └──────────────┘
```

---

## Key Design Decisions

### 1. Direct API Keys vs ENV Variable Mapping

**Before:** `provider_api_key_env_vars = { openai: "OPENAI_API_KEY" }` → check `ENV["OPENAI_API_KEY"]`

**After:** `api_keys = { openai: ENV["OPENAI_API_KEY"] }` → direct value storage

**Rationale:** Simpler, more direct. The configuration reads ENV vars at load time.

### 2. Capabilities on Models

Each model can have capabilities like `:chat`, `:structured_output`, `:vision`.

**Rationale:** Different contexts need different capabilities. LLM Judge needs structured output. Dataset generation needs structured output. This allows automatic filtering.

### 3. Context-Based Configuration

Instead of one global list of models, each UI context can have restrictions.

**Rationale:**
- Playground might allow all models
- LLM Judge should only show models that support structured output
- Dataset generation might be restricted to specific fast/cheap models

### 4. Separate OpenAI Assistants Config

Assistants API is fundamentally different from chat completions:
- Different API endpoints
- Different model availability (assistants don't support all models)
- May use different API key (different org/project)

**Rationale:** Keep it separate for clarity and flexibility.

### 5. Defaults Consolidation

All default values in one `defaults` hash:
- `playground_provider`
- `playground_model`
- `llm_judge_model`
- `dataset_generator_model`
- `prompt_generator_model`

**Rationale:** Easy to find and configure. Clear naming convention.

---

## File Summary

| Category | Files to Change | Count |
|----------|-----------------|-------|
| Configuration Core | `lib/prompt_tracker/configuration.rb`, templates | 3 |
| Helpers | `application_helper.rb` | 1 |
| Controllers | `playground_controller.rb`, `assistant_playground_controller.rb` | 2 |
| Views | `_model_config_form.html.erb`, `_llm_judge.html.erb`, `assistant_playground/show.html.erb` | 3 |
| Services | `prompt_generator_service.rb`, `dataset_row_generator_service.rb`, `llm_judge_evaluator.rb`, `conversation_judge_evaluator.rb` | 4 |
| **Total** | | **13 files** |

---

## Next Steps

1. Review and approve this plan
2. Start implementation following the Implementation Order
3. Run tests after each phase
4. Manual browser testing after completion
