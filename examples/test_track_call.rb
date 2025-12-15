# frozen_string_literal: true

# Quick test script for track_llm_call feature
# Run with: bin/rails console
# Then: load 'examples/test_track_call.rb'

puts "\n" + "=" * 80
puts "🚀 Testing track_llm_call Feature"
puts "=" * 80

# Step 1: Create a test prompt
puts "\n📝 Step 1: Creating test prompt..."
prompt = PromptTracker::Prompt.create!(
  name: "console_test_greeting",
  description: "Test greeting prompt for console testing"
)
puts "✅ Created prompt: #{prompt.name} (ID: #{prompt.id})"

# Step 2: Create an active version
puts "\n📝 Step 2: Creating active version..."
version = prompt.prompt_versions.create!(
  template: "Hello {{name}}, welcome to {{service}}! How can I help you with {{topic}} today?",
  variables_schema: [
    { "name" => "name", "type" => "string", "required" => true },
    { "name" => "service", "type" => "string", "required" => true },
    { "name" => "topic", "type" => "string", "required" => true }
  ],
  status: "active"
)
puts "✅ Created version #{version.version_number} (ID: #{version.id})"

# Step 3: Add an auto-evaluator
puts "\n📝 Step 3: Adding length evaluator..."
evaluator_config = version.evaluator_configs.create!(
  evaluator_key: :length,
  enabled: true,
  config: {
    min_length: 10,
    max_length: 500,
    ideal_min: 20,
    ideal_max: 200
  }
)
puts "✅ Added evaluator: #{evaluator_config.evaluator_key}"

# Step 4: Track a simple call (mock response)
puts "\n📝 Step 4: Tracking LLM call (mock response)..."
result = PromptTracker::LlmCallService.track(
  prompt_name: "console_test_greeting",
  variables: {
    name: "John",
    service: "PromptTracker",
    topic: "prompt testing"
  },
  provider: "openai",
  model: "gpt-4"
) do |rendered_prompt|
  puts "   📄 Rendered prompt: #{rendered_prompt}"
  # Mock response
  "Hello John! I'd be happy to help you with prompt testing. What specific aspect would you like to explore?"
end

puts "✅ Tracking successful!"
puts "   Response text: #{result[:response_text]}"
puts "   Tracking ID: #{result[:tracking_id]}"
puts "   LLM Response ID: #{result[:llm_response].id}"

# Step 5: Check the evaluations
puts "\n📝 Step 5: Checking auto-evaluations..."
response = result[:llm_response]
if response.evaluations.any?
  response.evaluations.each do |evaluation|
    status = evaluation.passed? ? "✅ PASSED" : "❌ FAILED"
    puts "   #{evaluation.evaluator_key}: #{evaluation.score}/100 #{status}"
  end
else
  puts "   ⚠️  No evaluations found"
end

# Step 6: Track another call with different variables
puts "\n📝 Step 6: Tracking another call..."
result2 = PromptTracker::LlmCallService.track(
  prompt_name: "console_test_greeting",
  variables: {
    name: "Alice",
    service: "PromptTracker",
    topic: "evaluation systems"
  },
  provider: "openai",
  model: "gpt-4",
  user_id: "user_alice",
  session_id: "session_123",
  metadata: { test_run: true, source: "console" }
) do |rendered_prompt|
  "Hi Alice! Let me help you understand our evaluation systems. They're quite powerful!"
end

puts "✅ Second call tracked!"
puts "   Response: #{result2[:response_text]}"

# Step 7: View all tracked calls
puts "\n📝 Step 7: Viewing all tracked calls for this prompt..."
all_responses = PromptTracker::LlmResponse.where(prompt_version: prompt.prompt_versions)
puts "   Total tracked calls: #{all_responses.count}"
all_responses.each_with_index do |r, i|
  puts "   #{i + 1}. [#{r.created_at.strftime('%H:%M:%S')}] #{r.response_text[0..60]}..."
end

# Step 8: Show summary
puts "\n" + "=" * 80
puts "✅ Test Complete!"
puts "=" * 80
puts "\n📊 Summary:"
puts "   Prompt: #{prompt.name} (ID: #{prompt.id})"
puts "   Version: #{version.version_number} (ID: #{version.id})"
puts "   Evaluators: #{version.evaluator_configs.count}"
puts "   Tracked calls: #{all_responses.count}"
puts "   Evaluations: #{PromptTracker::Evaluation.where(llm_response: all_responses).count}"

puts "\n🔍 Explore further:"
puts "   # View the prompt"
puts "   prompt = PromptTracker::Prompt.find(#{prompt.id})"
puts ""
puts "   # View all responses"
puts "   responses = PromptTracker::LlmResponse.where(prompt_version_id: #{version.id})"
puts ""
puts "   # View evaluations"
puts "   evaluations = PromptTracker::Evaluation.where(llm_response: responses)"
puts ""
puts "   # Track another call"
puts "   result = PromptTracker::LlmCallService.track("
puts "     prompt_slug: '#{prompt.slug}',"
puts "     variables: { name: 'Your Name', service: 'PromptTracker', topic: 'testing' },"
puts "     provider: 'openai',"
puts "     model: 'gpt-4'"
puts "   ) { |prompt| 'Your mock response here' }"
puts ""
puts "   # Cleanup (delete test data)"
puts "   PromptTracker::Prompt.find(#{prompt.id}).destroy"

puts "\n" + "=" * 80
puts "🎉 Happy Testing!"
puts "=" * 80
puts "\n"
