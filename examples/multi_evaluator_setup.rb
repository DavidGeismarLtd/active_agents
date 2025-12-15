# frozen_string_literal: true

# Example: Setting up multi-evaluator configuration for a prompt
#
# This script demonstrates how to:
# 1. Create a prompt with evaluator configs
# 2. Set up weighted scoring with dependencies
# 3. Create a response and see auto-evaluation in action
# 4. View the evaluation breakdown
#
# Run this in Rails console:
#   load 'examples/multi_evaluator_setup.rb'

puts "\n" + "=" * 80
puts "Multi-Evaluator Setup Example"
puts "=" * 80

# Step 1: Create or find a prompt
puts "\n📝 Step 1: Creating prompt..."
prompt = PromptTracker::Prompt.find_or_create_by!(name: "customer_support_greeting") do |p|
  p.description = "Greeting message for customer support"
end
puts "✅ Prompt created: #{prompt.name}"

# Step 2: Create a prompt version
puts "\n📄 Step 2: Creating prompt version..."
version = prompt.prompt_versions.find_or_create_by!(version_number: 1) do |v|
  v.template = "Hello {{customer_name}}, how can I help you today?"
  v.status = "active"
  v.source = "api"
end
puts "✅ Version created: v#{version.version_number}"

# Step 3: Configure evaluators with weights and dependencies
puts "\n⚙️  Step 3: Configuring evaluators..."

# Clear existing configs
prompt.evaluator_configs.destroy_all

# Tier 1: Basic validation (sync, fast, no dependencies)
length_config = prompt.evaluator_configs.create!(
  evaluator_key: :length,
  enabled: true,
  run_mode: "sync",
  priority: 1,
  weight: 0.15,
  config: {
    min_length: 10,
    max_length: 200
  }
)
puts "  ✅ Length Check configured (weight: 15%, sync, priority: 1)"

keyword_config = prompt.evaluator_configs.create!(
  evaluator_key: :keyword,
  enabled: true,
  run_mode: "sync",
  priority: 2,
  weight: 0.30,
  config: {
    required_keywords: [ "hello", "help" ],
    forbidden_keywords: [],
    case_sensitive: false
  }
)
puts "  ✅ Keyword Check configured (weight: 30%, sync, priority: 2)"

# Tier 2: Format validation (depends on length check)
format_config = prompt.evaluator_configs.create!(
  evaluator_key: :format,
  enabled: true,
  run_mode: "sync",
  priority: 3,
  weight: 0.25,
  depends_on: "length",
  min_dependency_score: 50,
  config: {
    expected_format: "plain",
    strict: false
  }
)
puts "  ✅ Format Check configured (weight: 25%, sync, priority: 3, depends on: length >= 50)"

# Tier 3: LLM Judge (depends on keyword check)
# Note: This will be scheduled as async job
judge_config = prompt.evaluator_configs.create!(
  evaluator_key: :llm_judge,
  enabled: false, # Disabled for now since we don't have LLM API configured
  run_mode: "async",
  priority: 4,
  weight: 0.30,
  depends_on: "keyword",
  min_dependency_score: 80,
  config: {
    judge_model: "gpt-4o",
    custom_instructions: "Evaluate as a customer support manager. Consider helpfulness, professionalism, and clarity."
  }
)
puts "  ⚠️  GPT-4 Judge configured but DISABLED (weight: 30%, async, priority: 4, depends on: keyword >= 80)"

puts "\n📊 Total weight: #{prompt.evaluator_configs.enabled.sum(:weight)} (should be close to 1.0 for weighted average)"

# Step 4: Create a response and trigger auto-evaluation
puts "\n🚀 Step 4: Creating response (auto-evaluation will trigger)..."

response = PromptTracker::LlmResponse.create!(
  prompt_version: version,
  rendered_prompt: "Hello John, how can I help you today?",
  response_text: "Hello! I'm here to help you with any questions or concerns you may have.",
  variables_used: { customer_name: "John" },
  provider: "openai",
  model: "gpt-4",
  status: "success",
  response_time_ms: 1200,
  tokens_total: 25,
  cost_usd: 0.0005
)

puts "✅ Response created: ID #{response.id}"
puts "   Auto-evaluation triggered automatically!"

# Give sync evaluations a moment to complete
sleep(0.5)

# Step 5: View evaluation results
puts "\n📈 Step 5: Evaluation Results"
puts "-" * 80

response.reload

if response.evaluations.any?
  puts "\n📊 Evaluation Results:"
  puts "   Total evaluations: #{response.evaluations.count}"
  puts "   Passed: #{response.evaluations.where(passed: true).count}"
  puts "   Failed: #{response.evaluations.where(passed: false).count}"

  puts "\n📋 Individual Evaluations:"
  response.evaluation_breakdown.each do |eval|
    status_icon = eval[:score] >= 80 ? "✅" : (eval[:score] >= 60 ? "⚠️" : "❌")
    puts "\n  #{status_icon} #{eval[:evaluator_name]}"
    puts "     Score: #{eval[:score]}/100"
    puts "     Weight: #{(eval[:normalized_weight] * 100).round(1)}%"
    puts "     Type: #{eval[:evaluator_type]}"
    puts "     Feedback: #{eval[:feedback]}" if eval[:feedback]
  end

  # Check if response passes threshold
  puts "\n✅ Quality Check:"
  if response.passes_threshold?(80)
    puts "   ✅ Response meets quality standards (all evaluations >= 80)"
  else
    puts "   ⚠️  Response needs improvement"
    weakest = response.weakest_evaluation
    puts "   Weakest area: #{weakest.evaluator_id} (#{weakest.score}/100)"
  end
else
  puts "⚠️  No evaluations found yet. This might happen if:"
  puts "   - All evaluators are disabled"
  puts "   - Dependencies were not met"
  puts "   - There was an error during evaluation"
end

# Step 6: Show how to query evaluations
puts "\n" + "=" * 80
puts "📚 Additional Examples"
puts "=" * 80

puts "\n# Get all evaluations for this response:"
puts "response.evaluations"
puts "# => #{response.evaluations.count} evaluation(s)"

puts "\n# Get evaluation breakdown with weights:"
puts "response.evaluation_breakdown"

puts "\n# Check if response passes threshold:"
puts "response.passes_threshold?(80)"
puts "# => #{response.passes_threshold?(80)}"

puts "\n# Get weakest evaluation:"
puts "response.weakest_evaluation&.evaluator_id"
puts "# => #{response.weakest_evaluation&.evaluator_id}"

puts "\n# Get all evaluator configs for this prompt:"
puts "prompt.evaluator_configs.enabled.count"
puts "# => #{prompt.evaluator_configs.enabled.count} enabled config(s)"

puts "\n# View all available evaluators in registry:"
puts "PromptTracker::EvaluatorRegistry.all.keys"
puts "# => #{PromptTracker::EvaluatorRegistry.all.keys.inspect}"

puts "\n" + "=" * 80
puts "✅ Example Complete!"
puts "=" * 80
puts "\nYou can now:"
puts "  1. View the response: PromptTracker::LlmResponse.find(#{response.id})"
puts "  2. View evaluations: PromptTracker::LlmResponse.find(#{response.id}).evaluations"
puts "  3. Modify configs: PromptTracker::Prompt.find(#{prompt.id}).evaluator_configs"
puts "  4. Create more responses to see auto-evaluation in action"
puts "\n"
