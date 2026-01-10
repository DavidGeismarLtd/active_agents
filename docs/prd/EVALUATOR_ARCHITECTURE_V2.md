# PRD: Evaluator Architecture V2 - API-Agnostic Evaluators

## Executive Summary

This document describes a complete refactoring of the evaluator system to make evaluators **API-agnostic** and **testable-agnostic**. Evaluators will be organized into two categories based on their **input shape**: `SingleResponse` vs `Conversational`. A normalization layer will transform API-specific responses into a standard format before passing to evaluators.

## Goals

1. **Decouple evaluators from APIs**: Evaluators should not know or care whether data came from Chat Completion API, Assistants API, or Response API
2. **Decouple evaluators from testables**: Evaluators should not know if the test is for PromptVersion or Assistant
3. **Two clear categories**: `SingleResponse` (single object) and `Conversational` (array of messages)
4. **API compatibility filtering**: `compatible_with_apis` controls which evaluators are shown in the UI based on what data the API provides
5. **Data normalization layer**: Transform API-specific responses into a standard format before evaluation

---

## Current State (Problems)

```
evaluators/
├── base_evaluator.rb
├── base_prompt_version_evaluator.rb      # Text-based, tied to PromptVersion
├── base_chat_completion_evaluator.rb     # Alias for above
├── base_conversational_evaluator.rb      # Conversation-based
├── base_assistants_api_evaluator.rb      # Requires run_steps (Assistants-specific)
├── base_openai_assistant_evaluator.rb    # Deprecated alias
├── length_evaluator.rb                   # Inherits from BaseChatCompletionEvaluator
├── keyword_evaluator.rb                  # Inherits from BasePromptVersionEvaluator
├── function_call_evaluator.rb            # Inherits from BaseConversationalEvaluator
├── file_search_evaluator.rb              # Inherits from BaseAssistantsApiEvaluator
└── ...
```

**Problems:**
- 6 base classes with confusing inheritance
- `compatible_with` returns testable classes (PromptVersion, Assistant) - wrong abstraction
- `FileSearchEvaluator` directly accesses `run_steps` - locked to Assistants API
- Evaluators receive raw API responses instead of normalized data

---

## Target State

### Folder Structure

```
evaluators/
├── base_evaluator.rb                     # Abstract base
├── single_response/
│   ├── base_single_response_evaluator.rb # For single response evaluation
│   ├── length_evaluator.rb
│   ├── keyword_evaluator.rb
│   ├── format_evaluator.rb
│   ├── exact_match_evaluator.rb
│   ├── pattern_match_evaluator.rb
│   └── llm_judge_evaluator.rb
├── conversational/
│   ├── base_conversational_evaluator.rb  # For multi-turn evaluation
│   ├── conversation_judge_evaluator.rb
│   ├── function_call_evaluator.rb
│   └── file_search_evaluator.rb
└── normalizers/                          # NEW: Data normalization
    ├── base_normalizer.rb
    ├── chat_completion_normalizer.rb
    ├── response_api_normalizer.rb
    └── assistants_api_normalizer.rb
```

---

## API Types

We define specific API types that evaluators can declare compatibility with:

```ruby
# API type constants
module PromptTracker
  module ApiTypes
    OPENAI_CHAT_COMPLETION = :openai_chat_completion
    OPENAI_RESPONSE_API = :openai_response_api
    OPENAI_ASSISTANTS_API = :openai_assistants_api
    ANTHROPIC_MESSAGES = :anthropic_messages

    ALL = [
      OPENAI_CHAT_COMPLETION,
      OPENAI_RESPONSE_API,
      OPENAI_ASSISTANTS_API,
      ANTHROPIC_MESSAGES
    ].freeze
  end
end
```

---

## Determining API Type

### In Testable Concern

```ruby
# app/models/concerns/prompt_tracker/testable.rb
module PromptTracker
  module Testable
    extend ActiveSupport::Concern

    # Returns the API type for this testable
    #
    # @return [Symbol] the API type
    # @example
    #   prompt_version.api_type # => :openai_chat_completion or :openai_response_api
    #   assistant.api_type      # => :openai_assistants_api
    def api_type
      raise NotImplementedError, "#{self.class.name} must implement #api_type"
    end
  end
end
```

### In PromptVersion

```ruby
# app/models/prompt_tracker/prompt_version.rb
class PromptVersion < ApplicationRecord
  def api_type
    return nil if model_config.blank?

    provider = model_config["provider"]&.to_s

    case provider
    when "openai"
      ApiTypes::OPENAI_CHAT_COMPLETION
    when "openai_responses"
      ApiTypes::OPENAI_RESPONSE_API
    when "anthropic"
      ApiTypes::ANTHROPIC_MESSAGES
    else
      # Unknown provider - assume chat completion style
      ApiTypes::OPENAI_CHAT_COMPLETION
    end
  end
end
```

### In Openai::Assistant

```ruby
# app/models/prompt_tracker/openai/assistant.rb
class Assistant < ApplicationRecord
  def api_type
    ApiTypes::OPENAI_ASSISTANTS_API
  end
end
```

---

## Part 2: Evaluator Base Classes

### BaseEvaluator (Abstract)

```ruby
# app/services/prompt_tracker/evaluators/base_evaluator.rb
module PromptTracker
  module Evaluators
    class BaseEvaluator
      attr_reader :config

      # Returns which APIs this evaluator is compatible with
      # Subclasses MUST override this
      #
      # @return [Array<Symbol>] array of API type symbols
      def self.compatible_with_apis
        raise NotImplementedError, "Subclasses must implement .compatible_with_apis"
      end

      # Check if evaluator is compatible with a specific API type
      #
      # @param api_type [Symbol] the API type to check
      # @return [Boolean] true if compatible
      def self.compatible_with_api?(api_type)
        compatible_with_apis.include?(api_type) || compatible_with_apis.include?(:all)
      end

      # Returns the evaluator category
      # @return [Symbol] :single_response or :conversational
      def self.category
        raise NotImplementedError, "Subclasses must implement .category"
      end

      def initialize(config = {})
        @config = config
      end

      def evaluate
        raise NotImplementedError, "Subclasses must implement #evaluate"
      end

      def evaluate_score
        raise NotImplementedError, "Subclasses must implement #evaluate_score"
      end
    end
  end
end
```

### BaseSingleResponseEvaluator

```ruby
# app/services/prompt_tracker/evaluators/single_response/base_single_response_evaluator.rb
module PromptTracker
  module Evaluators
    module SingleResponse
      class BaseSingleResponseEvaluator < BaseEvaluator
        attr_reader :response

        def self.category
          :single_response
        end

        # Initialize with a normalized response object
        #
        # @param response [Hash] normalized response with:
        #   - :text [String] the response text content
        #   - :tool_calls [Array<Hash>] optional tool/function calls
        #   - :metadata [Hash] optional additional metadata
        # @param config [Hash] evaluator configuration
        def initialize(response, config = {})
          @response = normalize_response(response)
          super(config)
        end

        # Convenience accessor for response text
        def response_text
          response[:text] || ""
        end

        # Convenience accessor for tool calls
        def tool_calls
          response[:tool_calls] || []
        end

        private

        # Normalize input to standard response format
        # Accepts either a String or Hash
        def normalize_response(input)
          case input
          when String
            { text: input, tool_calls: [], metadata: {} }
          when Hash
            {
              text: input[:text] || input["text"] || "",
              tool_calls: input[:tool_calls] || input["tool_calls"] || [],
              metadata: input[:metadata] || input["metadata"] || {}
            }
          else
            { text: input.to_s, tool_calls: [], metadata: {} }
          end
        end
      end
    end
  end
end
```

### BaseConversationalEvaluator

```ruby
# app/services/prompt_tracker/evaluators/conversational/base_conversational_evaluator.rb
module PromptTracker
  module Evaluators
    module Conversational
      class BaseConversationalEvaluator < BaseEvaluator
        attr_reader :conversation

        def self.category
          :conversational
        end

        # Initialize with normalized conversation data
        #
        # @param conversation [Hash] normalized conversation with:
        #   - :messages [Array<Hash>] array of message objects
        #   - :tool_usage [Array<Hash>] aggregated tool usage across conversation
        #   - :file_search_results [Array<Hash>] file search results (if applicable)
        # @param config [Hash] evaluator configuration
        def initialize(conversation, config = {})
          @conversation = normalize_conversation(conversation)
          super(config)
        end

        # Get all messages
        def messages
          conversation[:messages] || []
        end

        # Get assistant messages only
        def assistant_messages
          messages.select { |m| m[:role] == "assistant" }
        end

        # Get user messages only
        def user_messages
          messages.select { |m| m[:role] == "user" }
        end

        # Get aggregated tool usage across the conversation
        def tool_usage
          conversation[:tool_usage] || []
        end

        # Get file search results (normalized from any API)
        def file_search_results
          conversation[:file_search_results] || []
        end

        private

        def normalize_conversation(input)
          return { messages: [], tool_usage: [], file_search_results: [] } if input.nil?

          {
            messages: normalize_messages(input[:messages] || input["messages"] || []),
            tool_usage: input[:tool_usage] || input["tool_usage"] || [],
            file_search_results: input[:file_search_results] || input["file_search_results"] || []
          }
        end

        def normalize_messages(msgs)
          msgs.map do |msg|
            {
              role: msg[:role] || msg["role"],
              content: msg[:content] || msg["content"],
              tool_calls: msg[:tool_calls] || msg["tool_calls"] || [],
              turn: msg[:turn] || msg["turn"]
            }
          end
        end
      end
    end
  end
end
```


---

## Part 3: Concrete Evaluators

### Example: LengthEvaluator (SingleResponse)

```ruby
# app/services/prompt_tracker/evaluators/single_response/length_evaluator.rb
module PromptTracker
  module Evaluators
    module SingleResponse
      class LengthEvaluator < BaseSingleResponseEvaluator
        # Works with ALL APIs - just needs text
        def self.compatible_with_apis
          [:all]
        end

        def self.metadata
          {
            name: "Length Validator",
            description: "Validates response length against min/max ranges",
            icon: "rulers",
            default_config: { min_length: 10, max_length: 2000 }
          }
        end

        def evaluate_score
          length = response_text.length
          return 100 if length >= config[:min_length] && length <= config[:max_length]
          0
        end
      end
    end
  end
end
```

### Example: FunctionCallEvaluator (Conversational)

```ruby
# app/services/prompt_tracker/evaluators/conversational/function_call_evaluator.rb
module PromptTracker
  module Evaluators
    module Conversational
      class FunctionCallEvaluator < BaseConversationalEvaluator
        # Works with APIs that support function/tool calling
        def self.compatible_with_apis
          [
            ApiTypes::OPENAI_CHAT_COMPLETION,  # With function calling
            ApiTypes::OPENAI_RESPONSE_API,
            ApiTypes::OPENAI_ASSISTANTS_API
          ]
        end

        def self.metadata
          {
            name: "Function Call Validator",
            description: "Validates that expected functions were called",
            icon: "terminal",
            default_config: { expected_functions: [], require_all: true }
          }
        end

        def evaluate_score
          return 100 if expected_functions.empty?

          # Use normalized tool_usage from conversation
          called_functions = tool_usage.map { |t| t[:function_name] }.uniq
          matched = expected_functions & called_functions

          if config[:require_all]
            (matched.length.to_f / expected_functions.length * 100).round
          else
            matched.any? ? 100 : 0
          end
        end

        private

        def expected_functions
          Array(config[:expected_functions]).map(&:to_s)
        end
      end
    end
  end
end
```

### Example: FileSearchEvaluator (Conversational, API-Limited)

```ruby
# app/services/prompt_tracker/evaluators/conversational/file_search_evaluator.rb
module PromptTracker
  module Evaluators
    module Conversational
      class FileSearchEvaluator < BaseConversationalEvaluator
        # Only Assistants API has file_search capability
        def self.compatible_with_apis
          [ApiTypes::OPENAI_ASSISTANTS_API]
        end

        def self.metadata
          {
            name: "File Search Validator",
            description: "Validates that expected files were searched",
            icon: "file-earmark-search",
            default_config: { expected_files: [], require_all: true }
          }
        end

        def evaluate_score
          return 0 if expected_files.empty?

          # Use normalized file_search_results from conversation
          searched_files = file_search_results.flat_map { |r| r[:files] }.uniq
          matched = expected_files.select { |exp| searched_files.any? { |s| file_matches?(s, exp) } }

          (matched.length.to_f / expected_files.length * 100).round
        end

        private

        def expected_files
          Array(config[:expected_files]).map(&:to_s)
        end

        def file_matches?(searched, expected)
          searched.downcase.include?(expected.downcase)
        end
      end
    end
  end
end
```

---

## Part 4: Data Normalization Layer

The normalization layer transforms API-specific responses into a standard format.

### Standard Formats

#### SingleResponse Format

```ruby
{
  text: "The actual response content",
  tool_calls: [
    {
      id: "call_abc123",
      type: "function",
      function_name: "get_weather",
      arguments: { "location" => "San Francisco" }
    }
  ],
  metadata: {
    model: "gpt-4o",
    finish_reason: "stop"
  }
}
```

#### Conversation Format

```ruby
{
  messages: [
    {
      role: "user",
      content: "What's the weather?",
      tool_calls: [],
      turn: 1
    },
    {
      role: "assistant",
      content: "Let me check that for you.",
      tool_calls: [
        { id: "call_abc", type: "function", function_name: "get_weather", arguments: {...} }
      ],
      turn: 1
    }
  ],
  tool_usage: [
    { function_name: "get_weather", call_id: "call_abc", arguments: {...}, result: {...} }
  ],
  file_search_results: [
    { query: "policies", files: ["policy.pdf", "guidelines.txt"], scores: [0.95, 0.87] }
  ]
}
```


### Normalizer Classes

```ruby
# app/services/prompt_tracker/evaluators/normalizers/base_normalizer.rb
module PromptTracker
  module Evaluators
    module Normalizers
      class BaseNormalizer
        # Normalize a single response for SingleResponse evaluators
        def normalize_single_response(raw_response)
          raise NotImplementedError
        end

        # Normalize a conversation for Conversational evaluators
        def normalize_conversation(raw_data)
          raise NotImplementedError
        end
      end
    end
  end
end
```

```ruby
# app/services/prompt_tracker/evaluators/normalizers/assistants_api_normalizer.rb
module PromptTracker
  module Evaluators
    module Normalizers
      class AssistantsApiNormalizer < BaseNormalizer
        # Normalize conversation data from Assistants API
        #
        # @param raw_data [Hash] raw data containing:
        #   - messages: Array of messages from the thread
        #   - run_steps: Array of run steps (Assistants-specific)
        # @return [Hash] normalized conversation format
        def normalize_conversation(raw_data)
          messages = raw_data[:messages] || raw_data["messages"] || []
          run_steps = raw_data[:run_steps] || raw_data["run_steps"] || []

          {
            messages: normalize_messages(messages),
            tool_usage: extract_tool_usage(messages, run_steps),
            file_search_results: extract_file_search_results(run_steps)
          }
        end

        private

        def normalize_messages(messages)
          messages.map do |msg|
            {
              role: msg["role"] || msg[:role],
              content: msg["content"] || msg[:content],
              tool_calls: extract_tool_calls(msg),
              turn: msg["turn"] || msg[:turn]
            }
          end
        end

        def extract_tool_calls(message)
          tool_calls = message["tool_calls"] || message[:tool_calls] || []
          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type],
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_tool_usage(messages, run_steps)
          # Combine tool calls from messages and detailed info from run_steps
          tool_calls = messages.flat_map { |m| extract_tool_calls(m) }

          tool_calls.map do |tc|
            {
              function_name: tc[:function_name],
              call_id: tc[:id],
              arguments: tc[:arguments],
              result: find_tool_result(run_steps, tc[:id])
            }
          end
        end

        def extract_file_search_results(run_steps)
          run_steps.flat_map do |step|
            step_data = step.deep_symbolize_keys
            file_search_results = step_data[:file_search_results] || []

            file_search_results.map do |fs|
              results = fs[:results] || []
              {
                query: fs[:query],
                files: results.map { |r| r[:file_name] || r["file_name"] },
                scores: results.map { |r| r[:score] || r["score"] }
              }
            end
          end
        end

        def find_tool_result(run_steps, call_id)
          # Find the tool output for this call in run_steps
          run_steps.each do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []

            tool_calls.each do |tc|
              if (tc["id"] || tc[:id]) == call_id
                return tc["output"] || tc[:output]
              end
            end
          end
          nil
        end

        def parse_arguments(args)
          return {} if args.nil?
          return args if args.is_a?(Hash)
          JSON.parse(args) rescue {}
        end
      end
    end
  end
end
```

```ruby
# app/services/prompt_tracker/evaluators/normalizers/chat_completion_normalizer.rb
module PromptTracker
  module Evaluators
    module Normalizers
      class ChatCompletionNormalizer < BaseNormalizer
        # Normalize a single response from Chat Completion API
        #
        # @param raw_response [Hash, String] the raw response
        # @return [Hash] normalized single response format
        def normalize_single_response(raw_response)
          case raw_response
          when String
            { text: raw_response, tool_calls: [], metadata: {} }
          when Hash
            {
              text: extract_text(raw_response),
              tool_calls: extract_tool_calls(raw_response),
              metadata: extract_metadata(raw_response)
            }
          end
        end

        private

        def extract_text(response)
          response[:text] || response["text"] ||
            response.dig(:choices, 0, :message, :content) ||
            response.dig("choices", 0, "message", "content") ||
            ""
        end

        def extract_tool_calls(response)
          tool_calls = response[:tool_calls] || response["tool_calls"] ||
            response.dig(:choices, 0, :message, :tool_calls) ||
            response.dig("choices", 0, "message", "tool_calls") || []

          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type] || "function",
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_metadata(response)
          {
            model: response[:model] || response["model"],
            finish_reason: response.dig(:choices, 0, :finish_reason) ||
                          response.dig("choices", 0, "finish_reason")
          }
        end

        def parse_arguments(args)
          return {} if args.nil?
          return args if args.is_a?(Hash)
          JSON.parse(args) rescue {}
        end
      end
    end
  end
end
```


---

## Part 5: Updated EvaluatorRegistry

```ruby
# app/services/prompt_tracker/evaluator_registry.rb
module PromptTracker
  class EvaluatorRegistry
    class << self
      # Returns evaluators for a specific test
      # Filters by:
      # 1. Test mode (single_turn -> single_response evaluators, conversational -> conversational evaluators)
      # 2. API compatibility (based on testable's api_type)
      #
      # @param test [Test] the test to filter for
      # @return [Hash] hash of evaluator_key => metadata
      def for_test(test)
        category = test.single_turn? ? :single_response : :conversational
        api_type = test.testable.api_type

        all.select do |_key, meta|
          evaluator_class = meta[:evaluator_class]
          evaluator_class.category == category &&
            evaluator_class.compatible_with_api?(api_type)
        end
      end

      # Returns evaluators by category
      #
      # @param category [Symbol] :single_response or :conversational
      # @return [Hash] hash of evaluator_key => metadata
      def by_category(category)
        all.select { |_key, meta| meta[:evaluator_class].category == category }
      end

      # Returns single_response evaluators
      def single_response_evaluators
        by_category(:single_response)
      end

      # Returns conversational evaluators
      def conversational_evaluators
        by_category(:conversational)
      end

      # Auto-discover evaluators from both folders
      def auto_discover_evaluators
        # Discover from single_response folder
        discover_from_folder("single_response")

        # Discover from conversational folder
        discover_from_folder("conversational")
      end

      private

      def discover_from_folder(folder_name)
        path = File.join(File.dirname(__FILE__), "evaluators", folder_name, "*.rb")

        Dir.glob(path).each do |file|
          next if file.include?("base_")  # Skip base classes

          filename = File.basename(file, ".rb")
          class_name = filename.camelize
          module_name = folder_name.camelize

          begin
            evaluator_class = "PromptTracker::Evaluators::#{module_name}::#{class_name}".constantize
            register_evaluator_by_convention(evaluator_class)
          rescue NameError => e
            Rails.logger.warn "Failed to load evaluator #{class_name}: #{e.message}"
          end
        end
      end
    end
  end
end
```

---

## Part 6: Test Form UI Changes

### Updated Test Form with Dynamic Evaluator Filtering

The test form should filter evaluators based on:
1. **Test mode** (single_turn vs conversational)
2. **API type** from the testable

```erb
<%# app/views/prompt_tracker/testing/tests/_form.html.erb %>

<%# Evaluator section with dynamic filtering %>
<div data-controller="test-evaluator-filter"
     data-test-evaluator-filter-api-type-value="<%= @testable.api_type %>">

  <%# Test mode selection %>
  <div class="mb-4">
    <label class="form-label">Test Mode</label>
    <div class="btn-group" role="group">
      <%= form.radio_button :test_mode, :single_turn,
            class: "btn-check",
            data: { action: "test-evaluator-filter#modeChanged" } %>
      <%= form.label :test_mode_single_turn, "Single Turn", class: "btn btn-outline-primary" %>

      <%= form.radio_button :test_mode, :conversational,
            class: "btn-check",
            data: { action: "test-evaluator-filter#modeChanged" } %>
      <%= form.label :test_mode_conversational, "Conversational", class: "btn btn-outline-primary" %>
    </div>
  </div>

  <%# Evaluator selection (filtered dynamically) %>
  <div data-test-evaluator-filter-target="evaluatorList">
    <%# Single Response Evaluators %>
    <div data-category="single_response">
      <h5>Single Response Evaluators</h5>
      <% EvaluatorRegistry.single_response_evaluators.each do |key, meta| %>
        <div class="evaluator-option"
             data-apis="<%= meta[:evaluator_class].compatible_with_apis.join(',') %>">
          <%= check_box_tag "evaluators[]", key %>
          <%= label_tag key, meta[:name] %>
        </div>
      <% end %>
    </div>

    <%# Conversational Evaluators %>
    <div data-category="conversational">
      <h5>Conversational Evaluators</h5>
      <% EvaluatorRegistry.conversational_evaluators.each do |key, meta| %>
        <div class="evaluator-option"
             data-apis="<%= meta[:evaluator_class].compatible_with_apis.join(',') %>">
          <%= check_box_tag "evaluators[]", key %>
          <%= label_tag key, meta[:name] %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### Stimulus Controller

```javascript
// app/javascript/controllers/test_evaluator_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["evaluatorList"]
  static values = { apiType: String }

  connect() {
    this.filterEvaluators()
  }

  modeChanged(event) {
    this.filterEvaluators()
  }

  filterEvaluators() {
    const mode = this.element.querySelector('input[name*="test_mode"]:checked')?.value
    const category = mode === 'single_turn' ? 'single_response' : 'conversational'
    const apiType = this.apiTypeValue

    // Show/hide category sections
    this.evaluatorListTarget.querySelectorAll('[data-category]').forEach(section => {
      section.style.display = section.dataset.category === category ? 'block' : 'none'
    })

    // Filter by API compatibility within visible section
    this.evaluatorListTarget.querySelectorAll('.evaluator-option').forEach(option => {
      const apis = option.dataset.apis.split(',')
      const isCompatible = apis.includes('all') || apis.includes(apiType)
      option.style.display = isCompatible ? 'block' : 'none'
    })
  }
}
```


---

## Part 7: Test Execution Flow

### Updated TestRunner

```ruby
# app/services/prompt_tracker/testing/test_runner.rb
module PromptTracker
  module Testing
    class TestRunner
      def initialize(test)
        @test = test
        @normalizer = normalizer_for_api(@test.testable.api_type)
      end

      def run
        # 1. Execute the test against the testable
        raw_response = execute_testable

        # 2. Normalize the response based on API type
        normalized_data = normalize_response(raw_response)

        # 3. Run evaluators with normalized data
        run_evaluators(normalized_data)
      end

      private

      def normalizer_for_api(api_type)
        case api_type
        when ApiTypes::OPENAI_CHAT_COMPLETION
          Evaluators::Normalizers::ChatCompletionNormalizer.new
        when ApiTypes::OPENAI_RESPONSE_API
          Evaluators::Normalizers::ResponseApiNormalizer.new
        when ApiTypes::OPENAI_ASSISTANTS_API
          Evaluators::Normalizers::AssistantsApiNormalizer.new
        when ApiTypes::ANTHROPIC_MESSAGES
          Evaluators::Normalizers::AnthropicNormalizer.new
        else
          Evaluators::Normalizers::ChatCompletionNormalizer.new
        end
      end

      def normalize_response(raw_response)
        if @test.single_turn?
          @normalizer.normalize_single_response(raw_response)
        else
          @normalizer.normalize_conversation(raw_response)
        end
      end

      def run_evaluators(normalized_data)
        @test.evaluator_configs.map do |config|
          evaluator_class = EvaluatorRegistry.get(config.evaluator_key)

          # Instantiate with normalized data
          evaluator = evaluator_class.new(normalized_data, config.config)

          {
            evaluator_key: config.evaluator_key,
            score: evaluator.evaluate_score,
            result: evaluator.evaluate
          }
        end
      end
    end
  end
end
```

---

## Part 8: Migration Plan

### Phase 1: Create New Structure (Non-Breaking)

1. Create `ApiTypes` module
2. Add `api_type` method to testables
3. Create new folder structure under `evaluators/`
4. Create new base classes
5. Create normalizers

### Phase 2: Migrate Evaluators

1. Move each evaluator to appropriate folder
2. Update inheritance to new base classes
3. Replace `compatible_with` with `compatible_with_apis`
4. Update evaluator logic to use normalized data

### Phase 3: Update Registry and UI

1. Update `EvaluatorRegistry` with new methods
2. Update test form to use new filtering
3. Update test runner to use normalizers

### Phase 4: Cleanup

1. Remove old base classes
2. Remove deprecated methods
3. Update documentation

---

## Summary

| Concept | Old | New |
|---------|-----|-----|
| Evaluator categories | 6 base classes | 2 categories: `SingleResponse`, `Conversational` |
| Compatibility | `compatible_with` (testable classes) | `compatible_with_apis` (API types) |
| Data format | Raw API responses | Normalized standard format |
| Filtering | By testable type | By test mode + API type |
| File search | Requires `run_steps` directly | Uses normalized `file_search_results` |

### Key Benefits

1. **Simpler mental model**: Only 2 categories to understand
2. **API-agnostic evaluators**: Same evaluator works across APIs
3. **Future-proof**: Easy to add new APIs (just add normalizer)
4. **Better UI**: Users see only relevant evaluators
5. **Testable**: Evaluators can be tested with normalized data, no API mocking needed
