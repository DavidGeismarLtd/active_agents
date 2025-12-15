# Testing track_llm_call from Rails Console

This guide shows you how to test the `track_llm_call` feature from the Rails console.

## Prerequisites

Make sure you have:
1. Rails console running: `bin/rails console`
2. OpenAI API key set: `ENV['OPENAI_API_KEY']` (or other LLM provider)

## Response Format Contract

The block you provide to `track_llm_call` must return either:
- **A String** (just the response text) - simplest option
- **A Hash** with `:text` (required), `:tokens_prompt`, `:tokens_completion`, `:metadata` (optional)

Provider and model are **optional** - they default to the prompt version's `model_config`.

## Quick Start (Copy & Paste)

```ruby
# 1. Create a prompt
prompt = PromptTracker::Prompt.create!(
  name: "Test Greeting",
  slug: "test_greeting",
  description: "Test greeting prompt"
)

# 2. Create an active version with model_config
version = prompt.prompt_versions.create!(
  user_prompt: "Hello {{name}}, welcome to {{service}}!",
  variables_schema: [
    { "name" => "name", "type" => "string", "required" => true },
    { "name" => "service", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "model" => "gpt-4",
    "temperature" => 0.7
  },
  status: "active"
)

# 3. Track an LLM call (simplest - just return string)
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  variables: { name: "John", service: "PromptTracker" }
  # provider/model automatically from version's model_config
) do |rendered_prompt|
  puts "📝 Rendered prompt: #{rendered_prompt}"
  # Just return the text (simplest)
  "Hello! Nice to meet you, John!"
end

# 4. Check the results
puts "\n✅ Tracking successful!"
puts "Response text: #{result[:response_text]}"
puts "Tracking ID: #{result[:tracking_id]}"
puts "LLM Response ID: #{result[:llm_response].id}"

# 5. View the tracked response
response = result[:llm_response]
puts "\n📊 Response details:"
puts "  Prompt: #{response.prompt_version.prompt.name}"
puts "  Version: #{response.prompt_version.version_number}"
puts "  Rendered: #{response.rendered_prompt}"
puts "  Response: #{response.response_text}"
puts "  Provider: #{response.provider}"
puts "  Model: #{response.model}"
```

## With Structured Response (includes token counts)

```ruby
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  variables: { name: "Alice", service: "PromptTracker" }
) do |rendered_prompt|
  # Make actual API call
  client = OpenAI::Client.new
  response = client.chat(
    parameters: {
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: rendered_prompt }]
    }
  )

  # Return structured hash with token counts
  {
    text: response.dig("choices", 0, "message", "content"),
    tokens_prompt: response.dig("usage", "prompt_tokens"),
    tokens_completion: response.dig("usage", "completion_tokens"),
    metadata: { model: response["model"], id: response["id"] }
  }
end

puts "✅ Response: #{result[:response_text]}"
puts "📊 Tokens: #{result[:llm_response].tokens_total}"
```

## Override Provider/Model (for testing)

```ruby
# Override the version's model_config to test with a different model
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  variables: { name: "Bob", service: "PromptTracker" },
  provider: "anthropic",  # Override
  model: "claude-3-opus"  # Override
) do |rendered_prompt|
  "Hello Bob! (from Claude)"
end

puts "✅ Used provider: #{result[:llm_response].provider}"
puts "✅ Used model: #{result[:llm_response].model}"
```

## With Auto-Evaluators

```ruby
# 1. Add an evaluator config to the prompt version
config = version.evaluator_configs.create!(
  evaluator_key: :length_check,
  enabled: true,
  run_mode: "sync",
  priority: 1,
  weight: 1.0,
  config: {
    min_length: 10,
    max_length: 200,
    ideal_min: 20,
    ideal_max: 100
  }
)

# 2. Track a call (auto-evaluation will trigger)
result = PromptTracker::LlmCallService.track(
  prompt_name: "test_greeting",
  variables: { name: "Bob", service: "PromptTracker" },
  provider: "openai",
  model: "gpt-4"
) do |rendered_prompt|
  "Hello Bob! Welcome to PromptTracker. How can I help you today?"
end

# 3. Check evaluations
response = result[:llm_response]
puts "\n📊 Evaluations:"
response.evaluations.each do |eval|
  puts "  #{eval.evaluator_key}: #{eval.score}/100 (#{eval.passed? ? '✅ PASSED' : '❌ FAILED'})"
end
```

## With User Context & Metadata

```ruby
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  variables: { name: "Charlie", service: "PromptTracker" },
  provider: "openai",
  model: "gpt-4",
  user_id: "user_123",
  session_id: "session_abc",
  environment: "production",
  metadata: {
    ip_address: "192.168.1.1",
    user_agent: "Mozilla/5.0...",
    feature_flag: "new_greeting_v2"
  }
) do |rendered_prompt|
  "Hello Charlie! Welcome!"
end

# Check the metadata
puts result[:llm_response].metadata
# => {"ip_address"=>"192.168.1.1", "user_agent"=>"Mozilla/5.0...", ...}
```

## Using Specific Version

```ruby
# Create version 2
version2 = prompt.prompt_versions.create!(
  template: "Hi {{name}}! 👋",
  variables_schema: [
    { "name" => "name", "type" => "string", "required" => true }
  ],
  status: "deprecated",
  source: "console"
)

# Track using version 2 (not the active version)
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  version: 2,  # Specify version number
  variables: { name: "Diana" },
  provider: "openai",
  model: "gpt-4"
) do |rendered_prompt|
  puts "Using version 2: #{rendered_prompt}"
  "Hi Diana! 👋"
end
```

## Viewing All Tracked Calls

```ruby
# Get all responses for a prompt
prompt = PromptTracker::Prompt.find_by(slug: "test_greeting")
responses = PromptTracker::LlmResponse.where(prompt_version: prompt.prompt_versions)

puts "\n📊 All tracked calls:"
responses.each do |r|
  puts "  [#{r.created_at}] v#{r.prompt_version.version_number}: #{r.response_text[0..50]}..."
end
```

## Common Patterns

### Pattern 1: Simple Mock Testing (String Response)
```ruby
result = PromptTracker::LlmCallService.track(
  prompt_slug: "test_greeting",
  variables: { name: "Test" }
) { |prompt| "Mock response" }
```

### Pattern 2: With Error Handling
```ruby
begin
  result = PromptTracker::LlmCallService.track(
    prompt_slug: "nonexistent_prompt",
    variables: {}
  ) { |prompt| "Response" }
rescue PromptTracker::LlmCallService::PromptNotFoundError => e
  puts "❌ Error: #{e.message}"
end

# Error if block returns invalid format
begin
  result = PromptTracker::LlmCallService.track(
    prompt_slug: "test_greeting",
    variables: { name: "Test" }
  ) { |prompt| 123 }  # Invalid - not string or hash
rescue PromptTracker::LlmResponseContract::InvalidResponseError => e
  puts "❌ Error: #{e.message}"
end
```

### Pattern 3: Batch Testing
```ruby
["Alice", "Bob", "Charlie"].each do |name|
  PromptTracker::LlmCallService.track(
    prompt_slug: "test_greeting",
    variables: { name: name, service: "PromptTracker" }
  ) { |prompt| "Hello #{name}!" }
end

puts "✅ Created #{PromptTracker::LlmResponse.count} tracked calls"
```

## Cleanup

```ruby
# Delete all test data
PromptTracker::Prompt.find_by(slug: "test_greeting")&.destroy
```
