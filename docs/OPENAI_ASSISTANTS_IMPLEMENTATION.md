# OpenAI Assistants API Implementation Guide

## Overview
This guide shows how to add OpenAI Assistants API support to PromptTracker using the dynamic configuration system.

## Recommended Approach: Separate Provider

Treat OpenAI Assistants as a **separate provider** from OpenAI Chat Completions. This provides:
- ✅ Clear separation between Chat Completions API and Assistants API
- ✅ No changes needed to existing views or JavaScript
- ✅ Easy to filter/show assistants only in appropriate contexts
- ✅ Clear visual distinction in the UI

## Implementation Steps

### 1. Update Configuration (Initializer)

**File: `config/initializers/prompt_tracker.rb`**

```ruby
PromptTracker.configure do |config|
  config.available_models = {
    # Standard OpenAI Chat Completion models
    openai: [
      { id: "gpt-4o", name: "GPT-4o", category: "Latest" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest" },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4" },
      { id: "gpt-4", name: "GPT-4", category: "GPT-4" },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5" }
    ],
    
    # OpenAI Assistants (separate provider)
    openai_assistants: [
      { id: "asst_abc123", name: "Customer Support Assistant", category: "Support" },
      { id: "asst_def456", name: "Code Review Assistant", category: "Development" },
      { id: "asst_ghi789", name: "Data Analysis Assistant", category: "Analytics" },
      { id: "asst_jkl012", name: "Content Writer Assistant", category: "Content" }
    ],
    
    anthropic: [
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5" },
      # ...
    ]
  }

  config.provider_api_key_env_vars = {
    openai: "OPENAI_API_KEY",
    openai_assistants: "OPENAI_API_KEY",  # Same API key as openai
    anthropic: "ANTHROPIC_API_KEY"
  }
end
```

### 2. No View Changes Needed! ✅

Both forms already work dynamically:
- `app/views/prompt_tracker/testing/playground/_model_config_form.html.erb`
- `app/views/prompt_tracker/evaluator_configs/forms/_llm_judge.html.erb`

They will automatically:
1. Show "Openai Assistants" in the provider dropdown (if API key is configured)
2. Show the assistant list when that provider is selected
3. Group assistants by category (Support, Development, Analytics, Content)

### 3. Backend Detection

**File: `app/services/prompt_tracker/llm_caller_service.rb` (or similar)**

```ruby
class LlmCallerService
  def call(provider:, model:, messages:, **options)
    # Detect if this is an assistant
    if provider.to_s == 'openai_assistants'
      call_openai_assistant(model, messages, **options)
    else
      # Standard chat completion
      call_chat_completion(provider, model, messages, **options)
    end
  end

  private

  def call_openai_assistant(assistant_id, messages, **options)
    # Use OpenAI Assistants API
    # 1. Create a thread
    # 2. Add messages to thread
    # 3. Run the assistant
    # 4. Wait for completion
    # 5. Retrieve messages
    
    client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    
    # Create thread
    thread = client.threads.create
    
    # Add user message
    client.messages.create(
      thread_id: thread['id'],
      role: 'user',
      content: messages.last[:content]
    )
    
    # Run assistant
    run = client.runs.create(
      thread_id: thread['id'],
      assistant_id: assistant_id
    )
    
    # Wait for completion
    while run['status'] == 'in_progress' || run['status'] == 'queued'
      sleep 1
      run = client.runs.retrieve(thread_id: thread['id'], id: run['id'])
    end
    
    # Get response
    messages = client.messages.list(thread_id: thread['id'])
    assistant_message = messages['data'].first
    
    {
      content: assistant_message['content'].first['text']['value'],
      model: assistant_id,
      usage: {
        prompt_tokens: run['usage']['prompt_tokens'],
        completion_tokens: run['usage']['completion_tokens'],
        total_tokens: run['usage']['total_tokens']
      }
    }
  end

  def call_chat_completion(provider, model, messages, **options)
    # Existing chat completion logic using ruby_llm gem
    RubyLLM.generate(
      provider: provider,
      model: model,
      messages: messages,
      **options
    )
  end
end
```

### 4. Alternative: Use Metadata Approach

If you prefer to keep assistants under the `openai` provider:

```ruby
config.available_models = {
  openai: [
    # Chat models
    { id: "gpt-4o", name: "GPT-4o", category: "Chat - Latest", type: "chat" },
    { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Chat - Latest", type: "chat" },
    
    # Assistants
    { id: "asst_abc123", name: "Customer Support", category: "Assistants", type: "assistant" },
    { id: "asst_def456", name: "Code Review", category: "Assistants", type: "assistant" }
  ]
}
```

Then detect by model ID prefix:

```ruby
def call(provider:, model:, messages:, **options)
  if provider.to_s == 'openai' && model.start_with?('asst_')
    call_openai_assistant(model, messages, **options)
  else
    call_chat_completion(provider, model, messages, **options)
  end
end
```

## UI Behavior

### Provider Dropdown
```
┌─────────────────────────┐
│ Openai                  │
│ Openai Assistants       │  ← New option appears
│ Anthropic               │
└─────────────────────────┘
```

### Model Dropdown (when "Openai Assistants" selected)
```
┌─────────────────────────────────────┐
│ Support                             │
│   Customer Support Assistant        │
│ Development                         │
│   Code Review Assistant             │
│ Analytics                           │
│   Data Analysis Assistant           │
│ Content                             │
│   Content Writer Assistant          │
└─────────────────────────────────────┘
```

## Finding Your Assistant IDs

```bash
# Using OpenAI CLI
openai api assistants.list

# Or via API
curl https://api.openai.com/v1/assistants \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"
```

## Dynamic Assistant Loading (Advanced)

For automatic assistant discovery:

```ruby
# lib/prompt_tracker/assistants_loader.rb
module PromptTracker
  class AssistantsLoader
    def self.load_openai_assistants
      return [] unless ENV['OPENAI_API_KEY'].present?
      
      client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      response = client.assistants.list
      
      response['data'].map do |assistant|
        {
          id: assistant['id'],
          name: assistant['name'] || assistant['id'],
          category: assistant['metadata']['category'] || 'Assistants'
        }
      end
    rescue => e
      Rails.logger.error("Failed to load OpenAI assistants: #{e.message}")
      []
    end
  end
end

# In initializer
config.available_models = {
  openai: [...],
  openai_assistants: PromptTracker::AssistantsLoader.load_openai_assistants
}
```

## Summary

**Recommended: Separate Provider Approach**
- Add `openai_assistants` as a new provider key
- List your assistant IDs with friendly names
- No view changes needed - everything works automatically!
- Backend detects `openai_assistants` provider and uses Assistants API

**Result:**
- Users can select "Openai Assistants" from provider dropdown
- Model dropdown shows your configured assistants
- Backend automatically routes to correct API
- Clean, maintainable, and extensible

