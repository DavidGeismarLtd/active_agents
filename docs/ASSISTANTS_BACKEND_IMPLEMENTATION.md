# OpenAI Assistants API - Backend Implementation

## ✅ IMPLEMENTED - Option B

**ruby_llm does NOT support OpenAI Assistants API.** We've implemented it using the `ruby-openai` gem with a separate service.

## Implementation Summary

### Files Created/Modified

1. **`app/services/prompt_tracker/openai_assistant_service.rb`** ✅ Created
   - Dedicated service for OpenAI Assistants API
   - Handles thread creation, message sending, run execution, and response retrieval
   - Returns normalized response matching `LlmClientService` format

2. **`app/services/prompt_tracker/llm_client_service.rb`** ✅ Modified
   - Added routing logic to detect `openai_assistants` provider
   - Routes to `OpenaiAssistantService` when provider is `openai_assistants` or model starts with `asst_`
   - Maintains backward compatibility with existing chat completions

3. **`spec/services/prompt_tracker/openai_assistant_service_spec.rb`** ✅ Created
   - Complete test coverage for assistant service
   - Tests success case, error cases, timeout, and tool calls

4. **`spec/services/prompt_tracker/llm_client_service_spec.rb`** ✅ Modified
   - Added tests for routing to assistant service
   - Tests both `openai_assistants` provider and `asst_` model prefix detection

## How It Works

### Configuration (Already Done!)

Add assistants to your initializer:

```ruby
# config/initializers/prompt_tracker.rb
config.available_models = {
  openai: [
    { id: "gpt-4o", name: "GPT-4o", category: "Latest" },
    # ... other chat models
  ],

  openai_assistants: [
    { id: "asst_abc123", name: "Customer Support Assistant", category: "Support" },
    { id: "asst_def456", name: "Code Review Assistant", category: "Development" }
  ]
}

config.provider_api_key_env_vars = {
  openai: "OPENAI_API_KEY",
  openai_assistants: "OPENAI_API_KEY"  # Same API key
}
```

### Usage

The API is exactly the same as chat completions:

```ruby
# This will automatically route to OpenaiAssistantService
response = LlmClientService.call(
  provider: "openai_assistants",
  model: "asst_abc123",
  prompt: "What's the weather in Berlin?"
)

response[:text]  # => "The current weather in Berlin is..."
response[:usage] # => { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 }
response[:model] # => "asst_abc123"
```

### Detection Logic

The service detects assistants in two ways:

1. **Provider check**: `provider == "openai_assistants"`
2. **Model prefix check**: `model.start_with?("asst_")`

Either condition routes to `OpenaiAssistantService`.

## Installation Requirements

### 1. Add ruby-openai gem

```ruby
# Gemfile
gem 'ruby-openai'
```

Then run:
```bash
bundle install
```

### 2. Set API Key

The same `OPENAI_API_KEY` environment variable is used for both chat completions and assistants.

```bash
export OPENAI_API_KEY=sk-...
```

## Original Documentation (For Reference)

### 1. Add OpenAI Gem

```ruby
# Gemfile
gem 'ruby-openai'  # Official OpenAI Ruby client
```

### 2. Update LlmClientService

**File: `app/services/prompt_tracker/llm_client_service.rb`**

Add assistant detection and routing:

```ruby
# frozen_string_literal: true

module PromptTracker
  class LlmClientService
    # ... existing code ...

    # Main entry point - detect if assistant or chat completion
    def self.call(provider:, model:, prompt:, temperature: 0.7, max_tokens: nil, **options)
      # Detect OpenAI Assistants
      if provider.to_s == 'openai_assistants' || model.to_s.start_with?('asst_')
        call_openai_assistant(
          assistant_id: model,
          prompt: prompt,
          **options
        )
      else
        # Standard chat completion via ruby_llm
        new(
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: max_tokens,
          **options
        ).call
      end
    end

    # Call OpenAI Assistants API
    def self.call_openai_assistant(assistant_id:, prompt:, **options)
      client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

      # 1. Create a thread
      thread_response = client.threads.create

      thread_id = thread_response['id']

      # 2. Add user message to thread
      client.messages.create(
        thread_id: thread_id,
        parameters: {
          role: 'user',
          content: prompt
        }
      )

      # 3. Run the assistant
      run_response = client.runs.create(
        thread_id: thread_id,
        parameters: {
          assistant_id: assistant_id
        }
      )

      run_id = run_response['id']

      # 4. Wait for completion (with timeout)
      max_wait = 60 # seconds
      start_time = Time.now

      loop do
        run_status = client.runs.retrieve(
          thread_id: thread_id,
          id: run_id
        )

        status = run_status['status']

        case status
        when 'completed'
          break
        when 'failed', 'cancelled', 'expired'
          raise ApiError, "Assistant run #{status}: #{run_status['last_error']}"
        when 'requires_action'
          # Handle tool calls if needed
          raise ApiError, "Assistant requires action (tool calls not yet implemented)"
        end

        # Timeout check
        if Time.now - start_time > max_wait
          raise ApiError, "Assistant run timed out after #{max_wait} seconds"
        end

        sleep 1
      end

      # 5. Retrieve messages
      messages_response = client.messages.list(
        thread_id: thread_id,
        parameters: { order: 'desc', limit: 1 }
      )

      assistant_message = messages_response['data'].first
      content = assistant_message['content'].first['text']['value']

      # 6. Get usage from run
      final_run = client.runs.retrieve(thread_id: thread_id, id: run_id)
      usage = final_run['usage'] || {}

      # Return in standard format
      {
        text: content,
        usage: {
          prompt_tokens: usage['prompt_tokens'] || 0,
          completion_tokens: usage['completion_tokens'] || 0,
          total_tokens: usage['total_tokens'] || 0
        },
        model: assistant_id,
        raw: {
          thread_id: thread_id,
          run_id: run_id,
          assistant_message: assistant_message
        }
      }
    rescue => e
      raise ApiError, "OpenAI Assistant API error: #{e.message}"
    end

    # ... rest of existing code ...
  end
end
```

### 3. Alternative: Create Separate Service

If you prefer cleaner separation, create a dedicated service:

**File: `app/services/prompt_tracker/openai_assistant_service.rb`**

```ruby
# frozen_string_literal: true

module PromptTracker
  class OpenaiAssistantService
    class AssistantError < StandardError; end

    def self.call(assistant_id:, prompt:, timeout: 60)
      new(assistant_id: assistant_id, prompt: prompt, timeout: timeout).call
    end

    attr_reader :assistant_id, :prompt, :timeout, :client

    def initialize(assistant_id:, prompt:, timeout: 60)
      @assistant_id = assistant_id
      @prompt = prompt
      @timeout = timeout
      @client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    end

    def call
      thread_id = create_thread
      add_message(thread_id)
      run_id = run_assistant(thread_id)
      wait_for_completion(thread_id, run_id)
      retrieve_response(thread_id, run_id)
    end

    private

    def create_thread
      response = client.threads.create
      response['id']
    end

    def add_message(thread_id)
      client.messages.create(
        thread_id: thread_id,
        parameters: { role: 'user', content: prompt }
      )
    end

    def run_assistant(thread_id)
      response = client.runs.create(
        thread_id: thread_id,
        parameters: { assistant_id: assistant_id }
      )
      response['id']
    end

    def wait_for_completion(thread_id, run_id)
      start_time = Time.now

      loop do
        run = client.runs.retrieve(thread_id: thread_id, id: run_id)

        case run['status']
        when 'completed'
          return run
        when 'failed', 'cancelled', 'expired'
          raise AssistantError, "Run #{run['status']}: #{run['last_error']}"
        end

        raise AssistantError, "Timeout after #{timeout}s" if Time.now - start_time > timeout

        sleep 1
      end
    end

    def retrieve_response(thread_id, run_id)
      messages = client.messages.list(
        thread_id: thread_id,
        parameters: { order: 'desc', limit: 1 }
      )

      message = messages['data'].first
      content = message['content'].first['text']['value']

      run = client.runs.retrieve(thread_id: thread_id, id: run_id)
      usage = run['usage'] || {}

      {
        text: content,
        usage: {
          prompt_tokens: usage['prompt_tokens'] || 0,
          completion_tokens: usage['completion_tokens'] || 0,
          total_tokens: usage['total_tokens'] || 0
        },
        model: assistant_id,
        raw: { thread_id: thread_id, run_id: run_id, message: message }
      }
    end
  end
end
```

Then update `LlmClientService.call`:

```ruby
def self.call(provider:, model:, prompt:, **options)
  if provider.to_s == 'openai_assistants'
    OpenaiAssistantService.call(assistant_id: model, prompt: prompt)
  else
    new(model: model, prompt: prompt, **options).call
  end
end
```

## Summary

1. ✅ **ruby_llm does NOT support Assistants API**
2. ✅ **Use `ruby-openai` gem** for Assistants API
3. ✅ **Detect provider** (`openai_assistants`) in `LlmClientService`
4. ✅ **Route to separate method** that handles thread creation, running, and waiting
5. ✅ **Return standard format** matching ruby_llm response structure

This keeps your codebase clean and maintains a consistent interface!
