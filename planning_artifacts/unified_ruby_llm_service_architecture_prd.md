# PRD: Unified RubyLLM Service Architecture

## Status: 🔲 NOT STARTED

## Overview

Restructure PromptTracker's LLM service architecture to leverage RubyLLM's native tool handling capabilities. This creates a unified service for all RubyLLM-compatible providers (OpenAI, Anthropic, Google, DeepSeek, etc.) while maintaining dedicated services for APIs requiring direct SDK access.

## Goals

1. **Unified Tool Handling**: Use RubyLLM's native `with_tool()` API for automatic tool execution
2. **Provider Agnostic**: Single service handles all RubyLLM-compatible providers
3. **Simplified Architecture**: Remove redundant `FunctionCallHandler` classes where possible
4. **Clear Separation**: Dedicated services only for APIs that require direct SDK access
5. **Dynamic Tool Classes**: Convert JSON tool configs to `RubyLLM::Tool` subclasses at runtime

## Background

### Current Architecture Problems

| Issue | Description |
|-------|-------------|
| Duplicate code | Separate `FunctionCallHandler` for OpenAI and Anthropic doing the same thing |
| Manual tool loop | We manually handle: API call → check tool_use → execute → send result → repeat |
| Tool registration | Using `with_params` to pass tools bypasses RubyLLM's tool system |
| Provider-specific | `AnthropicMessagesService`, `LlmClientService` have similar logic |

### RubyLLM Native Tool Support

RubyLLM handles the **entire tool execution loop** automatically:

```ruby
class Weather < RubyLLM::Tool
  description "Gets weather for a location"
  param :city, desc: "City name"

  def execute(city:)
    # Return result - RubyLLM sends back to model automatically
    { temperature: 72, conditions: "Sunny" }
  end
end

chat = RubyLLM.chat(model: 'claude-sonnet-4-5')
      .with_tool(Weather)
      .on_tool_call { |tc| puts "Calling: #{tc.name}" }
      .on_tool_result { |r| puts "Result: #{r}" }

# Single call handles: message → tool_use → execute → result → final response
response = chat.ask("What's the weather in Berlin?")
```

### API Compatibility Matrix

| Provider/API | RubyLLM Compatible | Native Tool Support | Recommended Service |
|--------------|-------------------|---------------------|---------------------|
| OpenAI Chat Completions | ✅ Yes | ✅ Yes | `RubyLlmService` |
| Anthropic Messages | ✅ Yes | ✅ Yes | `RubyLlmService` |
| Google Gemini | ✅ Yes | ✅ Yes | `RubyLlmService` |
| DeepSeek | ✅ Yes | ✅ Yes | `RubyLlmService` |
| OpenRouter | ✅ Yes | ✅ Yes | `RubyLlmService` |
| Ollama (local) | ✅ Yes | ⚠️ Model-dependent | `RubyLlmService` |
| OpenAI Responses API | ❌ No | N/A | `OpenaiResponseService` |
| OpenAI Assistants API | ❌ No | N/A | `OpenaiAssistantService` |

---

## Proposed Architecture

### Service Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          LlmClientService                                │
│                     (Routing & Entry Point)                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────┐  ┌──────────────────┐  ┌────────────────────┐  │
│  │   RubyLlmService    │  │ OpenaiResponse   │  │  OpenaiAssistant   │  │
│  │   (NEW - Unified)   │  │    Service       │  │     Service        │  │
│  ├─────────────────────┤  ├──────────────────┤  ├────────────────────┤  │
│  │ • OpenAI Chat       │  │ • Direct HTTP    │  │ • Direct HTTP      │  │
│  │ • Anthropic         │  │ • Built-in tools │  │ • Thread-based     │  │
│  │ • Google Gemini     │  │ • web_search     │  │ • File search      │  │
│  │ • DeepSeek          │  │ • file_search    │  │ • Code interpreter │  │
│  │ • OpenRouter        │  │ • code_interp    │  │                    │  │
│  │ • Ollama            │  │ • functions      │  │                    │  │
│  └──────────┬──────────┘  └──────────────────┘  └────────────────────┘  │
│             │                                                            │
│  ┌──────────▼──────────┐                                                 │
│  │ DynamicToolBuilder  │                                                 │
│  │ (Converts JSON to   │                                                 │
│  │  RubyLLM::Tool)     │                                                 │
│  └─────────────────────┘                                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### File Structure

```
app/services/prompt_tracker/
├── llm_client_service.rb                    # MODIFY: Route to appropriate service
├── ruby_llm_service.rb                      # NEW: Unified RubyLLM service
├── ruby_llm/
│   ├── dynamic_tool_builder.rb              # NEW: JSON → RubyLLM::Tool converter
│   └── tool_execution_callbacks.rb          # NEW: Logging/monitoring callbacks
├── openai_response_service.rb               # KEEP: Direct SDK for Responses API
├── openai_assistant_service.rb              # KEEP: Direct SDK for Assistants API
├── openai/
│   └── responses/
│       ├── function_call_handler.rb         # KEEP: Manual tool loop for Responses API
│       ├── function_executor.rb             # KEEP: Mock execution for Responses API
│       └── function_input_builder.rb        # KEEP: Input building for Responses API
├── llm_response_normalizers/
│   ├── ruby_llm.rb                          # KEEP: Unified normalizer for RubyLLM
│   ├── openai/
│   │   ├── responses.rb                     # KEEP: For Responses API
│   │   └── assistants.rb                    # KEEP: For Assistants API
│   └── anthropic/
│       └── messages.rb                      # REMOVE: No longer needed
├── anthropic_messages_service.rb            # REMOVE: Replaced by RubyLlmService
└── anthropic/
    └── messages/                            # REMOVE: Entire directory
        ├── request_builder.rb
        ├── tool_formatter.rb
        ├── function_call_handler.rb
        └── function_input_builder.rb
```

---

## Phase 1: Core RubyLlmService

### 1.1 DynamicToolBuilder

Converts PromptTracker's JSON tool configs into `RubyLLM::Tool` subclasses at runtime.

```ruby
# app/services/prompt_tracker/ruby_llm/dynamic_tool_builder.rb
module PromptTracker
  module RubyLlm
    class DynamicToolBuilder
      # @param tool_config [Hash] PromptTracker tool configuration
      #   { "functions" => [{ "name" => "...", "description" => "...", "parameters" => {...} }] }
      # @param mock_function_outputs [Hash, nil] Optional mock outputs for testing
      #   { "function_name" => { "result" => "..." } }
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def self.build(tool_config:, mock_function_outputs: nil)
        new(tool_config: tool_config, mock_function_outputs: mock_function_outputs).build
      end

      def initialize(tool_config:, mock_function_outputs: nil)
        @tool_config = tool_config
        @mock_function_outputs = mock_function_outputs
      end

      def build
        functions = @tool_config["functions"] || []
        functions.map { |func_def| build_tool_class(func_def) }
      end

      private

      def build_tool_class(func_def)
        mock_outputs = @mock_function_outputs
        func_name = func_def["name"]
        func_description = func_def["description"]
        func_parameters = func_def["parameters"]

        Class.new(::RubyLLM::Tool) do
          description func_description

          # Use manual JSON Schema approach (v1.9+)
          params func_parameters if func_parameters.present?

          # Override tool name
          define_method(:name) { func_name }
          define_singleton_method(:tool_name) { func_name }

          # Execute returns mock data
          define_method(:execute) do |**args|
            custom_mock = mock_outputs&.dig(func_name)
            if custom_mock
              custom_mock.is_a?(Hash) ? custom_mock : { result: custom_mock }
            else
              {
                status: "success",
                function: func_name,
                result: "Mock response for #{func_name}",
                received_arguments: args
              }
            end
          end
        end
      end
    end
  end
end
```

### 1.2 RubyLlmService

Unified service for all RubyLLM-compatible providers.

```ruby
# app/services/prompt_tracker/ruby_llm_service.rb
module PromptTracker
  class RubyLlmService
    # Make a single-turn LLM call
    #
    # @param model [String] Model ID (e.g., "gpt-4o", "claude-sonnet-4-5", "gemini-2.0-flash")
    # @param prompt [String] User message
    # @param system [String, nil] System prompt
    # @param tools [Array<Symbol>] Tools to enable (e.g., [:functions])
    # @param tool_config [Hash] Tool configuration (e.g., { "functions" => [...] })
    # @param mock_function_outputs [Hash, nil] Mock outputs for testing
    # @param temperature [Float] Temperature (0.0-2.0)
    # @param max_tokens [Integer, nil] Maximum output tokens
    # @return [NormalizedLlmResponse]
    def self.call(model:, prompt:, system: nil, tools: [], tool_config: {},
                  mock_function_outputs: nil, temperature: 0.7, max_tokens: nil, **options)
      new(
        model: model,
        prompt: prompt,
        system: system,
        tools: tools,
        tool_config: tool_config,
        mock_function_outputs: mock_function_outputs,
        temperature: temperature,
        max_tokens: max_tokens,
        **options
      ).call
    end

    def initialize(model:, prompt:, system: nil, tools: [], tool_config: {},
                   mock_function_outputs: nil, temperature: 0.7, max_tokens: nil, **options)
      @model = model
      @prompt = prompt
      @system = system
      @tools = tools
      @tool_config = tool_config
      @mock_function_outputs = mock_function_outputs
      @temperature = temperature
      @max_tokens = max_tokens
      @options = options
      @tool_call_log = []
    end

    def call
      log_request
      chat = build_chat
      response = chat.ask(@prompt)
      log_response(response)

      LlmResponseNormalizers::RubyLlm.normalize(response)
    end

    private

    def build_chat
      chat = ::RubyLLM.chat(model: @model)
      chat = chat.with_instructions(@system) if @system.present?
      chat = chat.with_temperature(@temperature) if @temperature
      chat = apply_params(chat)
      chat = apply_tools(chat)
      chat = apply_callbacks(chat)
      chat
    end

    def apply_params(chat)
      return chat unless @max_tokens || @options.any?

      chat.with_params do |p|
        p[:max_tokens] = @max_tokens if @max_tokens
        @options.each { |k, v| p[k] = v }
      end
    end

    def apply_tools(chat)
      return chat unless @tools.include?(:functions) && @tool_config["functions"].present?

      # Build dynamic RubyLLM::Tool classes from JSON config
      tool_classes = RubyLlm::DynamicToolBuilder.build(
        tool_config: @tool_config,
        mock_function_outputs: @mock_function_outputs
      )

      # Register each tool with the chat
      tool_classes.each do |tool_class|
        chat = chat.with_tool(tool_class.new)
      end

      chat
    end

    def apply_callbacks(chat)
      chat
        .on_tool_call { |tc| log_tool_call(tc) }
        .on_tool_result { |result| log_tool_result(result) }
    end

    def log_request
      Rails.logger.info "[RubyLlmService] Request: model=#{@model}, " \
                        "system=#{@system.present?}, tools=#{@tools.inspect}, " \
                        "functions=#{@tool_config['functions']&.length || 0}, " \
                        "max_tokens=#{@max_tokens}"
    end

    def log_response(response)
      tool_calls_count = response.respond_to?(:tool_calls) && response.tool_calls.present? ? response.tool_calls.length : 0
      Rails.logger.info "[RubyLlmService] Response: model=#{response.model_id}, " \
                        "input_tokens=#{response.input_tokens}, output_tokens=#{response.output_tokens}, " \
                        "tool_calls=#{tool_calls_count}"
    end

    def log_tool_call(tool_call)
      Rails.logger.info "[RubyLlmService] Tool call: #{tool_call.name} with #{tool_call.arguments}"
      @tool_call_log << { type: :call, name: tool_call.name, arguments: tool_call.arguments }
    end

    def log_tool_result(result)
      Rails.logger.info "[RubyLlmService] Tool result: #{result.inspect.truncate(200)}"
      @tool_call_log << { type: :result, result: result }
    end
  end
end
```

---

## Phase 2: Multi-Turn Conversations

### 2.1 Unified SimulatedConversationRunner

Replace provider-specific runners with a unified RubyLLM-based runner.

**Key insight**: We don't need a separate `ConversationManager` class because:
1. `RubyLLM::Chat` already maintains conversation history internally
2. The existing provider-specific runners manage history directly within the runner
3. Keeping the same pattern (runner manages everything) is simpler and consistent

The runner creates a `RubyLLM::Chat` instance at the start and uses `chat.ask(message)`
for each turn. RubyLLM handles the conversation history automatically.

```ruby
# app/services/prompt_tracker/test_runners/ruby_llm/simulated_conversation_runner.rb
module PromptTracker
  module TestRunners
    module RubyLlm
      class SimulatedConversationRunner < TestRunners::SimulatedConversationRunner
        # Execute the test
        #
        # @param params [Hash] execution parameters
        # @return [Hash] output_data with standardized format
        def execute(params)
          @messages = []
          @all_tool_calls = []
          @mock_function_outputs = params[:mock_function_outputs]
          start_time = Time.current

          messages = execute_conversation(params)

          response_time_ms = ((Time.current - start_time) * 1000).to_i

          build_output_data(
            messages: messages,
            params: params,
            response_time_ms: response_time_ms,
            tokens: token_aggregator.aggregate_from_messages(messages),
            tools_used: tools.map(&:to_s)
          )
        end

        private

        # Execute a conversation (single-turn or multi-turn)
        #
        # RubyLLM::Chat maintains conversation history internally,
        # so we just call chat.ask() for each turn.
        #
        # @param params [Hash] execution parameters
        # @return [Array<Hash>] array of messages
        def execute_conversation(params)
          messages = []
          max_turns = params[:max_turns] || 1

          # Build RubyLLM chat instance once (with tools, system prompt, etc.)
          chat = build_ruby_llm_chat(params)

          (1..max_turns).each do |turn|
            # Generate user message
            user_message = if turn == 1
              params[:first_user_message]
            else
              interlocutor_simulator.generate_next_message(
                interlocutor_prompt: params[:interlocutor_prompt],
                conversation_history: messages,
                turn: turn
              )
            end

            break if user_message.nil?

            messages << { "role" => "user", "content" => user_message, "turn" => turn }

            # Call LLM - RubyLLM handles tool execution automatically
            response = call_llm(chat: chat, message: user_message, turn: turn)

            # Track tool calls
            if response.tool_calls.present?
              @all_tool_calls.concat(response.tool_calls)
            end

            # Build message with standardized structure
            messages << {
              "role" => "assistant",
              "content" => response.text,
              "turn" => turn,
              "usage" => response.usage,
              "tool_calls" => response.tool_calls || [],
              "api_metadata" => response.api_metadata || {}
            }
          end

          messages
        end

        # Build a RubyLLM::Chat instance with all configurations
        #
        # @param params [Hash] execution parameters
        # @return [RubyLLM::Chat] configured chat instance
        def build_ruby_llm_chat(params)
          chat = RubyLLM.chat(model: model)
          chat = chat.with_instructions(params[:system_prompt]) if params[:system_prompt].present?
          chat = chat.with_temperature(temperature) if temperature
          chat = apply_tools_to_chat(chat)
          chat
        end

        # Apply tools to chat using DynamicToolBuilder
        #
        # @param chat [RubyLLM::Chat] chat instance
        # @return [RubyLLM::Chat] chat with tools applied
        def apply_tools_to_chat(chat)
          return chat unless tools.include?(:functions) && tool_config["functions"].present?

          tool_classes = RubyLlm::DynamicToolBuilder.build(
            tool_config: tool_config,
            mock_function_outputs: @mock_function_outputs
          )

          tool_classes.each { |tc| chat = chat.with_tool(tc.new) }
          chat
        end

        # Call the LLM
        #
        # @param chat [RubyLLM::Chat] chat instance
        # @param message [String] user message
        # @param turn [Integer] current turn number
        # @return [NormalizedLlmResponse] normalized response
        def call_llm(chat:, message:, turn:)
          if use_real_llm
            response = chat.ask(message)
            LlmResponseNormalizers::RubyLlm.normalize(response)
          else
            mock_llm_response(turn: turn)
          end
        end

        # Get the interlocutor simulator instance
        def interlocutor_simulator
          @interlocutor_simulator ||= Helpers::InterlocutorSimulator.new(use_real_llm: use_real_llm)
        end

        # Get the token aggregator instance
        def token_aggregator
          @token_aggregator ||= Helpers::TokenAggregator.new
        end
      end
    end
  end
end
```

---

## Phase 3: LlmClientService Routing

### 3.1 Updated LlmClientService

The entry point routes requests to appropriate services based on API type.

```ruby
# app/services/prompt_tracker/llm_client_service.rb (Updated)
module PromptTracker
  class LlmClientService
    # Route requests to appropriate service
    #
    # @param provider [String] Provider name (openai, anthropic, google, etc.)
    # @param api [String, nil] API type (chat_completions, responses, assistants, messages)
    # @param model [String] Model ID
    # @param prompt [String] User message
    # @param options [Hash] Additional options
    # @return [NormalizedLlmResponse]
    def self.call(provider:, api:, model:, prompt:, temperature: 0.7, max_tokens: nil, **options)
      api_type = ApiTypes.from_config(provider, api)

      case api_type
      when :openai_responses
        # Direct SDK - has built-in tools (web_search, file_search, code_interpreter)
        OpenaiResponseService.call(
          model: model,
          input: prompt,
          instructions: options[:system_prompt],
          tools: options[:tools] || [],
          tool_config: options[:tool_config] || {},
          temperature: temperature,
          max_tokens: max_tokens,
          **options.except(:system_prompt, :tools, :tool_config)
        )
      when :openai_assistants
        # Direct SDK - thread-based with persistent state
        OpenaiAssistantService.call(
          assistant_id: options[:assistant_id],
          user_message: prompt,
          timeout: options[:timeout] || 60
        )
      else
        # All other providers go through unified RubyLlmService
        # This includes: openai_chat_completions, anthropic_messages,
        # google_gemini, deepseek, openrouter, ollama, etc.
        RubyLlmService.call(
          model: model,
          prompt: prompt,
          system: options[:system_prompt],
          tools: options[:tools] || [],
          tool_config: options[:tool_config] || {},
          mock_function_outputs: options[:mock_function_outputs],
          temperature: temperature,
          max_tokens: max_tokens,
          **options.except(:system_prompt, :tools, :tool_config, :mock_function_outputs)
        )
      end
    end
  end
end
```

### 3.2 Updated ApiTypes

```ruby
# app/services/prompt_tracker/api_types.rb (Updated)
module PromptTracker
  module ApiTypes
    # Determine API type from provider and api config
    #
    # @param provider [String] Provider name
    # @param api [String, nil] API type
    # @return [Symbol] API type constant
    def self.from_config(provider, api)
      case [provider&.to_s&.downcase, api&.to_s&.downcase]
      when ["openai", "responses"]
        :openai_responses
      when ["openai", "assistants"]
        :openai_assistants
      else
        # All others use RubyLLM: openai/chat_completions, anthropic/*, google/*, etc.
        :ruby_llm
      end
    end

    # Check if API type requires direct SDK (not RubyLLM)
    def self.requires_direct_sdk?(api_type)
      %i[openai_responses openai_assistants].include?(api_type)
    end
  end
end
```

---

## Phase 4: Test Runner Factory Update

### 4.1 Updated ConversationTestHandlerFactory

```ruby
# app/services/prompt_tracker/conversation_test_handler_factory.rb (Updated)
module PromptTracker
  class ConversationTestHandlerFactory
    def self.build(model_config:, use_real_llm:, mock_function_outputs: nil)
      api_type = determine_api_type(model_config)

      case api_type
      when :openai_responses
        TestRunners::Openai::Responses::SimulatedConversationRunner.new(
          model_config: model_config,
          use_real_llm: use_real_llm,
          mock_function_outputs: mock_function_outputs
        )
      when :openai_assistants
        TestRunners::Openai::Assistants::SimulatedConversationRunner.new(
          model_config: model_config,
          use_real_llm: use_real_llm
        )
      else
        # Unified runner for all RubyLLM-compatible providers
        TestRunners::RubyLlm::SimulatedConversationRunner.new(
          model_config: model_config,
          use_real_llm: use_real_llm,
          mock_function_outputs: mock_function_outputs
        )
      end
    end

    private

    def self.determine_api_type(model_config)
      provider = model_config[:provider] || "openai"
      api = model_config[:api]
      ApiTypes.from_config(provider, api)
    end
  end
end
```

---

## Migration Plan

### Step 1: Create New Files (No Breaking Changes)

| File | Description |
|------|-------------|
| `app/services/prompt_tracker/ruby_llm_service.rb` | New unified service |
| `app/services/prompt_tracker/ruby_llm/dynamic_tool_builder.rb` | JSON → Tool converter |
| `app/services/prompt_tracker/test_runners/ruby_llm/simulated_conversation_runner.rb` | Unified test runner |
| `spec/services/prompt_tracker/ruby_llm_service_spec.rb` | Tests |
| `spec/services/prompt_tracker/ruby_llm/dynamic_tool_builder_spec.rb` | Tests |

### Step 2: Update Routing (Backward Compatible)

1. Update `ApiTypes.from_config` to return `:ruby_llm` for non-specialized APIs
2. Update `LlmClientService.call` to route to `RubyLlmService`
3. Update `ConversationTestHandlerFactory` to use unified runner
4. **Keep old services working** during transition

### Step 3: Validate & Test

1. Run all existing tests - should still pass
2. Test with real LLM calls for each provider:
   - OpenAI Chat Completions with tools
   - Anthropic Claude with tools
   - Google Gemini with tools
3. Verify tool execution works automatically

### Step 4: Remove Deprecated Code

| File to Remove | Replaced By |
|----------------|-------------|
| `anthropic_messages_service.rb` | `RubyLlmService` |
| `anthropic/messages/request_builder.rb` | `RubyLlmService` (inline) |
| `anthropic/messages/tool_formatter.rb` | `DynamicToolBuilder` |
| `anthropic/messages/function_call_handler.rb` | RubyLLM auto-handles |
| `anthropic/messages/function_input_builder.rb` | RubyLLM auto-handles |
| `llm_response_normalizers/anthropic/messages.rb` | `llm_response_normalizers/ruby_llm.rb` |
| `test_runners/anthropic/messages/*` | `test_runners/ruby_llm/*` |
| `test_runners/openai/chat_completions/*` | `test_runners/ruby_llm/*` |

---

## Testing Strategy

### Unit Tests

```ruby
# spec/services/prompt_tracker/ruby_llm/dynamic_tool_builder_spec.rb
RSpec.describe PromptTracker::RubyLlm::DynamicToolBuilder do
  describe ".build" do
    let(:tool_config) do
      {
        "functions" => [
          {
            "name" => "get_weather",
            "description" => "Get weather for a city",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string", "description" => "City name" }
              },
              "required" => ["city"]
            }
          }
        ]
      }
    end

    it "creates RubyLLM::Tool subclasses" do
      tools = described_class.build(tool_config: tool_config)

      expect(tools.length).to eq(1)
      expect(tools.first.superclass).to eq(RubyLLM::Tool)
    end

    it "sets tool name correctly" do
      tools = described_class.build(tool_config: tool_config)
      tool_instance = tools.first.new

      expect(tool_instance.name).to eq("get_weather")
    end

    it "returns mock data on execute" do
      tools = described_class.build(tool_config: tool_config)
      tool_instance = tools.first.new

      result = tool_instance.execute(city: "Berlin")
      expect(result[:status]).to eq("success")
      expect(result[:function]).to eq("get_weather")
    end

    context "with custom mock outputs" do
      let(:mock_outputs) { { "get_weather" => { "temp" => 72 } } }

      it "returns custom mock on execute" do
        tools = described_class.build(
          tool_config: tool_config,
          mock_function_outputs: mock_outputs
        )
        tool_instance = tools.first.new

        result = tool_instance.execute(city: "Berlin")
        expect(result).to eq({ "temp" => 72 })
      end
    end
  end
end
```

### Integration Tests

```ruby
# spec/services/prompt_tracker/ruby_llm_service_spec.rb
RSpec.describe PromptTracker::RubyLlmService do
  describe ".call" do
    context "with OpenAI model" do
      it "makes a successful call" do
        VCR.use_cassette("ruby_llm_service/openai_basic") do
          response = described_class.call(
            model: "gpt-4o-mini",
            prompt: "Say hello",
            temperature: 0.7
          )

          expect(response).to be_a(PromptTracker::NormalizedLlmResponse)
          expect(response.text).to be_present
        end
      end
    end

    context "with Anthropic model" do
      it "makes a successful call" do
        VCR.use_cassette("ruby_llm_service/anthropic_basic") do
          response = described_class.call(
            model: "claude-3-5-sonnet-20241022",
            prompt: "Say hello",
            max_tokens: 100
          )

          expect(response).to be_a(PromptTracker::NormalizedLlmResponse)
          expect(response.text).to be_present
        end
      end
    end

    context "with tools" do
      let(:tool_config) do
        {
          "functions" => [{
            "name" => "get_weather",
            "description" => "Get weather",
            "parameters" => { "type" => "object", "properties" => {} }
          }]
        }
      end

      it "executes tools automatically" do
        VCR.use_cassette("ruby_llm_service/with_tools") do
          response = described_class.call(
            model: "gpt-4o-mini",
            prompt: "What's the weather in Berlin?",
            tools: [:functions],
            tool_config: tool_config
          )

          expect(response.text).to be_present
          # Tool was called and result integrated into response
        end
      end
    end
  end
end
```

---

## Benefits

### 1. Simplified Architecture

| Before | After |
|--------|-------|
| `AnthropicMessagesService` + helpers | `RubyLlmService` (unified) |
| `LlmClientService` (partial RubyLLM) | `RubyLlmService` (full RubyLLM) |
| Manual `FunctionCallHandler` per provider | RubyLLM auto-handles |
| Provider-specific `ToolFormatter` classes | `DynamicToolBuilder` (unified) |
| ~10+ files for tool handling | ~3 files |

### 2. Automatic Tool Execution

```ruby
# Before: Manual loop in FunctionCallHandler
while response[:tool_calls].present? && iteration_count < MAX_ITERATIONS
  iteration_count += 1
  tool_calls = response[:tool_calls]
  all_tool_calls.concat(tool_calls)
  history << build_assistant_tool_use_message(response)
  tool_result_message = @input_builder.build_tool_result_message(tool_calls)
  history << tool_result_message
  response = call_api_with_history(history, system_prompt)
  all_responses << response
end

# After: RubyLLM handles it automatically
response = chat.ask("What's the weather?")  # Done!
```

### 3. Provider Agnostic

Same code works for:
- ✅ OpenAI (gpt-4o, gpt-4, gpt-3.5-turbo)
- ✅ Anthropic (claude-3-5-sonnet, claude-3-opus)
- ✅ Google (gemini-2.0-flash, gemini-1.5-pro)
- ✅ DeepSeek
- ✅ OpenRouter
- ✅ Ollama (local models)
- ✅ AWS Bedrock
- ✅ Any future RubyLLM-supported provider

### 4. Built-in Monitoring

```ruby
chat
  .on_tool_call { |tc| log_tool_call(tc) }
  .on_tool_result { |r| log_tool_result(r) }
  .on_new_message { puts "Assistant is responding..." }
  .on_end_message { |m| puts "Response complete!" }
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| RubyLLM gem issues/bugs | We already depend on it; can contribute fixes |
| Tool execution format differences | Test thoroughly with each provider |
| Mock system integration | Pass mock_function_outputs to `DynamicToolBuilder` |
| Breaking existing tests | Incremental migration with backward compatibility |
| OpenAI Responses API not supported | Keep `OpenaiResponseService` with manual handling |

---

## Open Questions

1. **Structured Output with Tools**: Does RubyLLM support both `with_schema` and `with_tool` simultaneously?
   - Need to verify this works for judge evaluators that use both

2. **Tool Call Metadata**: Does RubyLLM expose full tool call details (IDs, timing) for our test output?
   - May need to capture via callbacks

3. **Max Iterations Safety**: RubyLLM handles tool loops automatically - does it have a max iteration limit?
   - Check RubyLLM source code or add callback-based limiting

4. **Streaming with Tools**: How does RubyLLM handle streaming responses that include tool calls?
   - May be relevant for future UI streaming features

---

## Implementation Order

```
Phase 1: DynamicToolBuilder + RubyLlmService (2-3 days)
    │
    ├── Create DynamicToolBuilder
    ├── Create RubyLlmService
    ├── Write comprehensive tests
    └── Manual testing with real APIs

Phase 2: Unified Test Runner (2-3 days)
    │
    ├── Create unified SimulatedConversationRunner
    ├── (RubyLLM::Chat handles conversation state internally)
    ├── Update tests
    └── Test multi-turn conversations

Phase 3: Routing Updates (1-2 days)
    │
    ├── Update LlmClientService routing
    ├── Update ConversationTestHandlerFactory
    ├── Run full test suite
    └── Fix any regressions

Phase 4: Cleanup (1-2 days)
    │
    ├── Remove deprecated Anthropic services
    ├── Remove deprecated test runners
    ├── Update documentation
    └── Final testing

Total: ~7-10 days
```

---

## Summary

This architecture change leverages RubyLLM's native tool handling to create a **unified, provider-agnostic LLM service**. Key benefits:

1. **One service** for all RubyLLM-compatible providers (OpenAI, Anthropic, Google, etc.)
2. **Automatic tool execution** - no more manual `FunctionCallHandler` loops
3. **Dynamic tool classes** - convert JSON configs to `RubyLLM::Tool` at runtime
4. **Simplified codebase** - remove ~10 provider-specific files
5. **Future-proof** - new providers work automatically

The only exceptions are **OpenAI Responses API** and **Assistants API**, which require direct SDK access for their unique features (built-in web_search, file_search, code_interpreter, threads).

---

## Appendix: File Changes Summary

### New Files (5)
- `app/services/prompt_tracker/ruby_llm_service.rb`
- `app/services/prompt_tracker/ruby_llm/dynamic_tool_builder.rb`
- `app/services/prompt_tracker/test_runners/ruby_llm/simulated_conversation_runner.rb`
- `spec/services/prompt_tracker/ruby_llm_service_spec.rb`
- `spec/services/prompt_tracker/ruby_llm/dynamic_tool_builder_spec.rb`

### Modified Files (3)
- `app/services/prompt_tracker/llm_client_service.rb`
- `app/services/prompt_tracker/api_types.rb`
- `app/services/prompt_tracker/conversation_test_handler_factory.rb`

### Removed Files (10+)
- `app/services/prompt_tracker/anthropic_messages_service.rb`
- `app/services/prompt_tracker/anthropic/messages/request_builder.rb`
- `app/services/prompt_tracker/anthropic/messages/tool_formatter.rb`
- `app/services/prompt_tracker/anthropic/messages/function_call_handler.rb`
- `app/services/prompt_tracker/anthropic/messages/function_input_builder.rb`
- `app/services/prompt_tracker/llm_response_normalizers/anthropic/messages.rb`
- `app/services/prompt_tracker/test_runners/anthropic/messages/simulated_conversation_runner.rb`
- `app/services/prompt_tracker/test_runners/openai/chat_completions/simulated_conversation_runner.rb`
- And corresponding spec files

### Kept As-Is (Direct SDK)
- `app/services/prompt_tracker/openai_response_service.rb`
- `app/services/prompt_tracker/openai_assistant_service.rb`
- `app/services/prompt_tracker/openai/responses/*` (all function handling)
