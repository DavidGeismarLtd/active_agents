# frozen_string_literal: true

# Quick test to verify the evaluator system works
puts "\n🧪 Quick Evaluator System Test\n\n"

# Clean up any existing test data
puts "Cleaning up test data..."
PromptTracker::Prompt.where(name: "test_prompt").destroy_all

# Create a simple prompt
puts "Creating test prompt..."
prompt = PromptTracker::Prompt.create!(
  name: "test_prompt",
  description: "Test prompt for evaluator system",
  category: "test",
  score_aggregation_strategy: "weighted_average"
)

# Create a version
puts "Creating prompt version..."
version = prompt.prompt_versions.create!(
  template: "Say hello to {{name}}",
  version_number: 1,
  status: "active",
  source: "api"
)

# Configure a simple evaluator
puts "Configuring length evaluator..."
config = prompt.evaluator_configs.create!(
  evaluator_key: :length_check,
  enabled: true,
  run_mode: "sync",
  priority: 1,
  weight: 1.0,
  config: {
    min_length: 5,
    max_length: 100
  }
)

puts "✅ Setup complete!\n\n"

# Create a response (this should trigger auto-evaluation)
puts "Creating response (auto-evaluation should trigger)..."
response = PromptTracker::LlmResponse.create!(
  prompt_version: version,
  rendered_prompt: "Say hello to John",
  response_text: "Hello John! How are you today?",
  variables_used: { name: "John" },
  provider: "openai",
  model: "gpt-4",
  status: "success",
  response_time_ms: 500,
  tokens_total: 10,
  cost_usd: 0.0001
)

puts "✅ Response created: ID #{response.id}\n\n"

# Give it a moment for the callback to complete
sleep(0.5)

# Check results
response.reload

puts "📊 Results:"
puts "  Evaluations count: #{response.evaluations.count}"

if response.evaluations.any?
  puts "  ✅ Auto-evaluation worked!"
  puts "  Passed: #{response.evaluations.where(passed: true).count}/#{response.evaluations.count}"

  response.evaluations.each do |eval|
    puts "\n  Evaluation:"
    puts "    Evaluator: #{eval.evaluator_id}"
    puts "    Type: #{eval.evaluator_type}"
    puts "    Score: #{eval.score}/100"
    puts "    Feedback: #{eval.feedback}" if eval.feedback
  end
else
  puts "  ❌ No evaluations found!"
  puts "  This might indicate an error in the auto-evaluation system."
end

puts "\n✅ Test complete!\n\n"
