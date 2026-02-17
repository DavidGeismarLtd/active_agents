# PRD: Anthropic Messages API Implementation

## Status: 🔲 NOT STARTED

## Overview

Implement Anthropic (Claude) as a new LLM provider in PromptTracker, following the established patterns from the OpenAI implementation.

## Goals

1. Support Anthropic Claude models in the playground
2. Enable LLM Judge evaluations with Claude models
3. Support function calling (tool use) with Claude
4. Maintain consistent architecture with OpenAI implementation

## Background Research

### API Summary

| Aspect | Anthropic | OpenAI (Responses API) |
|--------|-----------|------------------------|
| API Endpoint | `POST /v1/messages` | `POST /v1/responses` |
| APIs Available | 1 (Messages only) | 3 (Chat, Responses, Assistants) |
| max_tokens | **REQUIRED** | Optional (has default) |
| System Prompt | Separate `system` param | In messages or `instructions` |
| Tool Format | `{name, description, input_schema}` | `{type: "function", function: {...}}` |
| Tool Calls | In `content` array as blocks | In `output` array |
| Stop Reason | `stop_reason: "end_turn"` | `stop_reason: "end_turn"` |
| Usage Tokens | `input_tokens`, `output_tokens` | `prompt_tokens`, `completion_tokens` |
| Built-in Tools | `web_search` only | `web_search`, `file_search`, `code_interpreter` |

### ruby_llm Support

✅ **Confirmed**: ruby_llm fully supports Anthropic with:
- Chat, Embeddings, Media, Models, Streaming, Tools
- Configuration: `anthropic_api_key`

### Decision: Direct ruby_llm vs Dedicated Service

**Recommendation**: Create a dedicated `AnthropicMessagesService` that **uses ruby_llm under the hood**:
- ✅ Uses ruby_llm for actual API calls (simplicity, maintained library)
- ✅ Service wraps ruby_llm to provide consistent PromptTracker interface
- ✅ Centralized request building
- ✅ Consistent tool formatting
- ✅ Unified response normalization to `NormalizedLlmResponse`
- ✅ Better testability

```ruby
# AnthropicMessagesService uses ruby_llm internally
def call
  # ruby_llm handles the HTTP call
  response = RubyLLM.chat(model: model, messages: messages, ...)
  # We normalize the response to our format
  LlmResponseNormalizers::Anthropic::Messages.normalize(response)
end
```

---

## Architecture

### File Structure

```
app/services/prompt_tracker/
├── anthropic_messages_service.rb              # Main service orchestrator (uses ruby_llm)
├── anthropic/
│   └── messages/
│       ├── request_builder.rb                 # Build params for ruby_llm call
│       ├── tool_formatter.rb                  # DEDICATED CLASS: Format tools for Anthropic
│       └── function_call_handler.rb           # Handle function call loops (Phase 2)
├── llm_response_normalizers/
│   └── anthropic/
│       └── messages.rb                        # Normalize ruby_llm response to NormalizedLlmResponse
├── test_runners/
│   └── anthropic/
│       └── messages/
│           └── simulated_conversation_runner.rb  # Multi-turn conversation runner
└── remote_entity/
    └── anthropic/
        └── messages/
            └── field_normalizer.rb            # Bidirectional field mapping (if needed)
```

### Spec Files

```
spec/services/prompt_tracker/
├── anthropic_messages_service_spec.rb
├── anthropic/
│   └── messages/
│       ├── request_builder_spec.rb
│       ├── tool_formatter_spec.rb
│       └── function_call_handler_spec.rb
├── llm_response_normalizers/
│   └── anthropic/
│       └── messages_spec.rb
└── test_runners/
    └── anthropic/
        └── messages/
            └── simulated_conversation_runner_spec.rb
```

---

## Phase 1: Core Implementation

### 1.1 AnthropicMessagesService

Main orchestrator service, similar to `OpenaiResponseService`.

```ruby
module PromptTracker
  class AnthropicMessagesService
    def self.call(model:, messages:, system: nil, tools: [], max_tokens: 4096, temperature: 0.7, **options)
      new(model:, messages:, system:, tools:, max_tokens:, temperature:, **options).call
    end

    def call
      response = client.messages.create(parameters: build_parameters)
      normalize_response(response)
    end

    private

    def build_parameters
      request_builder.build
    end

    def normalize_response(response)
      LlmResponseNormalizers::Anthropic::Messages.normalize(response)
    end
  end
end
```

### 1.2 Request Builder

Builds the API request parameters.

```ruby
module PromptTracker
  module Anthropic
    module Messages
      class RequestBuilder
        def build
          params = {
            model: model,
            messages: messages,
            max_tokens: max_tokens  # REQUIRED for Anthropic
          }
          params[:system] = system if system.present?
          params[:temperature] = temperature if temperature
          params[:tools] = tool_formatter.format if tools.any?
          params
        end
      end
    end
  end
end
```

### 1.3 Tool Formatter

Formats tools for Anthropic's API format.

**Anthropic Tool Format:**
```json
{
  "name": "get_weather",
  "description": "Get weather for a location",
  "input_schema": {
    "type": "object",
    "properties": {
      "location": { "type": "string" }
    },
    "required": ["location"]
  }
}
```

**PromptTracker Internal Format:**
```ruby
{
  name: "get_weather",
  description: "Get weather for a location",
  parameters: { type: "object", properties: {...} }
}
```

Transformation needed: `parameters` → `input_schema`

### 1.4 Response Normalizer

Normalizes Anthropic response to `NormalizedLlmResponse`.

**Anthropic Response:**
```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    { "type": "text", "text": "Hello!" },
    { "type": "tool_use", "id": "toolu_01", "name": "get_weather", "input": {...} }
  ],
  "model": "claude-3-5-sonnet-20241022",
  "stop_reason": "end_turn",
  "usage": { "input_tokens": 12, "output_tokens": 8 }
}
```

**Normalized Output:**
```ruby
NormalizedLlmResponse.new(
  text: "Hello!",
  usage: { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 },
  model: "claude-3-5-sonnet-20241022",
  tool_calls: [{ id: "toolu_01", name: "get_weather", arguments: {...} }],
  file_search_results: [],
  web_search_results: [],
  code_interpreter_results: [],
  api_metadata: { message_id: "msg_01XFDUDYJgAACzvnptvVoYEL", stop_reason: "end_turn" }
)
```

---

## Phase 2: Function Calling Loop (Tool Use)

### 2.1 Function Call Handler

Handle multi-turn conversations with tool use.

**Anthropic Tool Use Flow:**
1. Send request with tools
2. Claude responds with `stop_reason: "tool_use"` and `tool_use` blocks in content
3. Execute tools
4. Send new request with tool results as user message
5. Claude provides final response

**Tool Result Format:**
```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "toolu_01",
      "content": "72°F and sunny"
    }
  ]
}
```

### 2.2 Key Differences from OpenAI

| Aspect | OpenAI Responses API | Anthropic Messages |
|--------|---------------------|-------------------|
| Continuation | `previous_response_id` | Full message history |
| Tool Results | `function_call_output` items | `tool_result` in user message |
| Stateful | Yes (server-side) | No (client manages history) |

---

## Phase 3: Integration Points

### 3.1 Test Runner Integration

The test runner needs to detect Anthropic provider and use the correct service:

```ruby
# In TestRunners::Base or similar
def call_llm_api(prompt_version, input)
  case prompt_version.provider
  when "openai"
    OpenaiResponseService.call(...)
  when "anthropic"
    AnthropicMessagesService.call(...)
  end
end
```

### 3.2 Playground Integration

Update the playground controller to support Anthropic:

```ruby
# PlaygroundController
def run
  case params[:provider]
  when "anthropic"
    response = AnthropicMessagesService.call(
      model: params[:model],
      messages: [{ role: "user", content: params[:input] }],
      system: params[:system_prompt],
      max_tokens: params[:max_tokens] || 4096
    )
  end
end
```

### 3.3 LLM Judge Support

Enable Claude as an LLM judge for evaluations:
- Already configured in `contexts[:llm_judge]` with `providers: [:openai, :anthropic]`
- Need to update judge evaluator to use correct service based on model

---

## API Format Reference

### Request Parameters

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| model | string | ✅ | - | e.g., `claude-3-5-sonnet-20241022` |
| messages | array | ✅ | - | Array of message objects |
| max_tokens | integer | ✅ | - | **No default - must specify** |
| system | string/array | ❌ | - | System prompt (separate from messages) |
| temperature | number | ❌ | 1 | Range: 0-1 |
| top_p | number | ❌ | - | Nucleus sampling |
| top_k | integer | ❌ | -1 | Top-k sampling (-1 = disabled) |
| stop_sequences | array | ❌ | - | Custom stop sequences |
| stream | boolean | ❌ | false | Enable streaming |
| tools | array | ❌ | - | Tool definitions |
| tool_choice | object | ❌ | auto | `{type: "auto/any/tool"}` |

### Response Fields

| Field | Type | Notes |
|-------|------|-------|
| id | string | Message ID (e.g., `msg_01XFDUDYJgAACzvnptvVoYEL`) |
| type | string | Always `"message"` |
| role | string | Always `"assistant"` |
| content | array | Array of content blocks |
| model | string | Model used |
| stop_reason | string | `end_turn`, `max_tokens`, `stop_sequence`, `tool_use` |
| usage | object | `{input_tokens, output_tokens}` |

### Content Block Types

| Type | Fields | Description |
|------|--------|-------------|
| text | `text` | Text response |
| tool_use | `id`, `name`, `input` | Tool call request |
| thinking | `thinking`, `signature` | Extended thinking (if enabled) |

---

## Configuration

### Already Configured

The dummy app initializer already has Anthropic configured:

```ruby
# API Keys
config.api_keys = {
  openai: ENV["OPENAI_API_KEY"],
  anthropic: ENV["ANTHROPIC_API_KEY"]  # ✅ Already present
}

# Providers
config.providers = {
  anthropic: {
    name: "Anthropic",
    apis: {
      messages: {
        name: "Messages",
        description: "Claude chat API",
        default: true
      }
    }
  }
}

# Models
config.models = {
  anthropic: [
    { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", ... },
    { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", ... },
    ...
  ]
}
```

### Model Capabilities to Add

Update model capabilities to include `:function_calling`:

```ruby
{ id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5",
  capabilities: [ :chat, :structured_output, :vision, :function_calling ] }
```

---

## Implementation Plan

### Phase 1: Core Service (Priority: High)
- [ ] Create `AnthropicMessagesService`
- [ ] Create `Anthropic::Messages::RequestBuilder`
- [ ] Create `Anthropic::Messages::ToolFormatter`
- [ ] Create `LlmResponseNormalizers::Anthropic::Messages`
- [ ] Write specs for all classes

### Phase 2: Function Calling & Conversation Runner (Priority: Medium)
- [ ] Create `Anthropic::Messages::FunctionCallHandler`
- [ ] Handle multi-turn tool use conversations
- [ ] Create `TestRunners::Anthropic::Messages::SimulatedConversationRunner`
  - Key difference from OpenAI: **stateless** (must manage full message history)
  - No `previous_response_id` - send entire conversation each turn
- [ ] Write specs for function call loops
- [ ] Write specs for SimulatedConversationRunner

### Phase 3: Integration (Priority: Medium)
- [ ] Update playground to support Anthropic (add `execute_anthropic_messages` method)
- [ ] Update test runner to detect and use Anthropic service
- [ ] Update LLM judge to support Claude models
- [ ] Add `:function_calling` capability to Claude models

### Phase 4: Testing & Polish (Priority: High)
- [ ] Integration tests with real API (optional, gated)
- [ ] Update documentation
- [ ] Test in playground UI

---

## Success Criteria

1. ✅ Can call Anthropic Messages API via `AnthropicMessagesService`
2. ✅ Responses normalized to `NormalizedLlmResponse`
3. ✅ Function calling works with tool_use → tool_result flow
4. ✅ Playground supports Anthropic provider selection
5. ✅ LLM Judge can use Claude models
6. ✅ All specs pass
7. ✅ Consistent architecture with OpenAI implementation

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ruby_llm Anthropic bugs | Medium | Can fall back to direct HTTP calls if needed |
| Rate limiting differences | Low | Handle rate limit errors appropriately |
| Streaming complexity | Medium | Phase 1 focuses on non-streaming; add streaming later |
| Tool format incompatibility | Low | ToolFormatter handles translation |

---

## Out of Scope (Future Phases)

- Streaming responses (SSE)
- Extended thinking blocks
- Image/document input
- Prompt caching
- Web search built-in tool
- Anthropic Files API integration
