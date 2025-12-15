# Testing track_llm_call from Rails Console

This guide shows you how to test the `track_llm_call` feature from the Rails console.

## Prerequisites

Make sure you have:
1. Rails console running: `bin/rails console`
2. OpenAI API key set: `ENV['OPENAI_API_KEY']` (or other LLM provider)

## Quick Start (Copy & Paste)

```ruby
# 1. Create a prompt
prompt = PromptTracker::Prompt.create!(
  name: "test_greeting",
  description: "Test greeting prompt"
)

# 2. Create an active version
version = prompt.prompt_versions.create!(
  template: "Hello {{name}}, welcome to {{service}}!",
  variables_schema: [
    { "name" => "name", "type" => "string", "required" => true },
    { "name" => "service", "type" => "string", "required" => true }
  ],
  status: "active",
  source: "console"
)

# 3. Track an LLM call (with mock response)
result = PromptTracker::LlmCallService.track(
  prompt_name: "test_greeting",
  variables: { name: "John", service: "PromptTracker" },
  provider: "openai",
  model: "gpt-4"
) do |rendered_prompt|
  puts "📝 Rendered prompt: #{rendered_prompt}"
  # Mock response (replace with actual LLM call)
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

## With Real OpenAI API Call

```ruby
# Make sure you have the ruby_llm gem configured
result = PromptTracker::LlmCallService.track(
  prompt_name: "test_greeting",
  variables: { name: "Alice", service: "PromptTracker" },
  provider: "openai",
  model: "gpt-4o-mini"
) do |rendered_prompt|
  # Use the LlmClientService to make the actual call
  response = PromptTracker::LlmClientService.call(
    provider: "openai",
    model: "gpt-4o-mini",
    prompt: rendered_prompt,
    temperature: 0.7
  )
  response[:text]  # Return just the text
end

puts "✅ Real LLM response: #{result[:response_text]}"
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
  prompt_name: "test_greeting",
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
  prompt_name: "test_greeting",
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
prompt = PromptTracker::Prompt.find_by(name: "test_greeting")
responses = PromptTracker::LlmResponse.where(prompt_version: prompt.prompt_versions)

puts "\n📊 All tracked calls:"
responses.each do |r|
  puts "  [#{r.created_at}] v#{r.prompt_version.version_number}: #{r.response_text[0..50]}..."
end
```

## Common Patterns

### Pattern 1: Simple Mock Testing
```ruby
result = PromptTracker::LlmCallService.track(
  prompt_name: "test_greeting",
  variables: { name: "Test" },
  provider: "openai",
  model: "gpt-4"
) { |prompt| "Mock response" }
```

### Pattern 2: With Error Handling
```ruby
begin
  result = PromptTracker::LlmCallService.track(
    prompt_name: "nonexistent_prompt",
    variables: {},
    provider: "openai",
    model: "gpt-4"
  ) { |prompt| "Response" }
rescue PromptTracker::LlmCallService::PromptNotFoundError => e
  puts "❌ Error: #{e.message}"
end
```

### Pattern 3: Batch Testing
```ruby
["Alice", "Bob", "Charlie"].each do |name|
  PromptTracker::LlmCallService.track(
    prompt_name: "test_greeting",
    variables: { name: name, service: "PromptTracker" },
    provider: "openai",
    model: "gpt-4"
  ) { |prompt| "Hello #{name}!" }
end

puts "✅ Created #{PromptTracker::LlmResponse.count} tracked calls"
```

## Cleanup

```ruby
# Delete all test data
PromptTracker::Prompt.find_by(name: "test_greeting")&.destroy
```

