# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding PromptTracker database..."

# Load all seed files in order
seed_files = Dir[Rails.root.join("db/seeds/*.rb")].sort

if seed_files.empty?
  puts "⚠️  No seed files found in db/seeds/"
  puts "   Expected files like: 01_cleanup.rb, 02_prompts_customer_support.rb, etc."
  exit 1
end

seed_files.each do |file|
  filename = File.basename(file)
  puts "\n📄 Loading #{filename}..."
  load file
end

puts "  Creating sample tests..."

# Tests for support greeting v3 (active version)
test_greeting_premium = support_greeting_v3.prompt_tests.create!(
  name: "Premium Customer Greeting",
  description: "Test greeting for premium customers with billing issues",
  tags: [ "premium", "billing" ],
  enabled: true
)

# Add pattern match evaluator
test_greeting_premium.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: { patterns: [ "John Smith", "billing" ], match_all: true }
)

# Create evaluator config for this test
test_greeting_premium.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
  config: { "min_length" => 10, "max_length" => 500 },
  enabled: true
)

test_greeting_technical = support_greeting_v3.prompt_tests.create!(
  name: "Technical Support Greeting",
  description: "Test greeting for technical support inquiries",
  tags: [ "technical" ],
  enabled: true
)

test_greeting_technical.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: { patterns: [ "Sarah Johnson", "technical" ], match_all: true }
)

test_greeting_technical.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
  config: { "min_length" => 10, "max_length" => 500 },
  enabled: true
)

test_greeting_account = support_greeting_v3.prompt_tests.create!(
  name: "Account Issue Greeting",
  description: "Test greeting for account-related questions",
  tags: [ "account" ],
  enabled: true
)

test_greeting_account.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: { patterns: [ "Mike Davis", "account" ], match_all: true }
)

test_greeting_account.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
  config: { "min_length" => 10, "max_length" => 500 },
  enabled: true
)

test_greeting_general = support_greeting_v3.prompt_tests.create!(
  name: "General Inquiry Greeting",
  description: "Test greeting for general customer inquiries",
  tags: [ "general" ],
  enabled: true
)

test_greeting_general.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: { patterns: [ "Emily Chen", "general" ], match_all: true }
)

test_greeting_general.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
  config: { "min_length" => 10, "max_length" => 500 },
  enabled: true
)

# Disabled test for edge case
test_greeting_edge = support_greeting_v3.prompt_tests.create!(
  name: "Edge Case - Very Long Name",
  description: "Test greeting with unusually long customer name",
  tags: [ "edge-case" ],
  enabled: false
)

test_greeting_edge.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: { patterns: [ "Alexander", "billing" ], match_all: true }
)

# ============================================================================
# Advanced Tests with Multiple Evaluators
# ============================================================================

puts "  Creating advanced tests with multiple evaluators..."

# Test 1: Comprehensive Quality Check with Multiple Evaluators
test_comprehensive_quality = support_greeting_v3.prompt_tests.create!(
  name: "Comprehensive Quality Check",
  description: "Tests greeting quality with multiple evaluators including LLM judge, length, and keyword checks",
  tags: [ "comprehensive", "quality", "critical" ],
  enabled: true
)

# Add pattern match evaluator (binary mode)
test_comprehensive_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: {
    patterns: [
      "Jennifer",
      "refund",
      "\\b(help|assist|support)\\b",  # Must contain help/assist/support
      "^Hi\\s+\\w+"  # Must start with "Hi" followed by a name
    ],
    match_all: true
  }
)

test_comprehensive_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",

  config: {
    "min_length" => 50,
    "max_length" => 200
  },
  enabled: true
)

test_comprehensive_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",

  config: {
    "required_keywords" => [ "help", "refund" ],
    "forbidden_keywords" => [ "unfortunately", "cannot", "unable" ],
    "case_sensitive" => false
  },
  enabled: true
)

test_comprehensive_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",

  config: {
    "judge_model" => "gpt-4o",
    "custom_instructions" => "Evaluate if the greeting is warm, professional, and acknowledges the customer's refund request appropriately. Consider helpfulness, professionalism, clarity, and tone."
  },
  enabled: true
)

# Test 2: Complex Pattern Matching for Email Format
test_email_format = email_summary_v1.prompt_tests.create!(
  name: "Email Summary Format Validation",
  description: "Validates email summary format with complex regex patterns",
  tags: [ "format", "validation", "email" ],
  enabled: true
)

# Add pattern match evaluator (binary mode)
test_email_format.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: {
    patterns: [
      "\\b(discuss|planning|goals?)\\b",  # Must mention discussion/planning/goals
      "\\b(Q4|quarter|fourth quarter)\\b",  # Must reference Q4
      "^[A-Z]",  # Must start with capital letter
      "\\.$",  # Must end with period
      "\\b\\d{1,2}\\s+(sentences?|points?)\\b"  # Should mention number of sentences/points
    ],
    match_all: true
  }
)

test_email_format.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",

  config: {
    "min_length" => 100,
    "max_length" => 400
  },
  enabled: true
)

test_email_format.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::FormatEvaluator",

  config: {
    "expected_format" => "plain",
    "strict" => false
  },
  enabled: true
)

test_email_format.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",

  config: {
    "judge_model" => "gpt-4o",
    "custom_instructions" => "Evaluate if the summary captures the key points of the email thread concisely and accurately. Consider accuracy, conciseness, and completeness."
  },
  enabled: true
)

# Test 3: Code Review Quality with LLM Judge
test_code_review_quality = code_review_v1.prompt_tests.create!(
  name: "Code Review Quality Assessment",
  description: "Tests code review feedback quality with LLM judge and keyword validation",
  tags: [ "code-review", "quality", "technical" ],
  enabled: true
)

# Add pattern match evaluator (binary mode)
test_code_review_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: {
    patterns: [
      "\\b(quality|readability|performance|best practice)\\b",  # Must mention quality aspects
      "\\b(bug|edge case|error|exception)\\b",  # Must mention potential issues
      "\\b(consider|suggest|recommend|improve)\\b",  # Must provide suggestions
      "```ruby",  # Must include code block
      "\\bsum\\b"  # Must reference the sum method
    ],
    match_all: true
  }
)

test_code_review_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",

  config: {
    "min_length" => 200,
    "max_length" => 1000
  },
  enabled: true
)

test_code_review_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",

  config: {
    "required_keywords" => [ "code", "quality", "readability" ],
    "forbidden_keywords" => [ "terrible", "awful", "stupid" ],
    "case_sensitive" => false
  },
  enabled: true
)

test_code_review_quality.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",

  config: {
    "judge_model" => "gpt-4o",
    "custom_instructions" => "Evaluate if the code review is constructive, technically accurate, and provides actionable feedback. The review should identify potential issues and suggest improvements. Consider helpfulness, technical accuracy, professionalism, and completeness."
  },
  enabled: true
)

# Test 4: Exact Output Match with Multiple Evaluators
test_exact_match = support_greeting_v3.prompt_tests.create!(
  name: "Exact Output Validation",
  description: "Tests for exact expected output with additional quality checks",
  tags: [ "exact-match", "critical", "smoke" ],
  enabled: true
)

# Add exact match evaluator (binary mode)
test_exact_match.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ExactMatchEvaluator",
  enabled: true,
  config: {
    expected_text: "Hi Alice! Thanks for contacting us. I'm here to help with your password reset question. What's going on?",
    case_sensitive: false,
    trim_whitespace: true
  }
)

# Add pattern match evaluator (binary mode)
test_exact_match.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: {
    patterns: [
      "^Hi Alice!",
      "password reset",
      "What's going on\\?$"
    ],
    match_all: true
  }
)

test_exact_match.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",

  config: {
    "min_length" => 50,
    "max_length" => 150
  },
  enabled: true
)

test_exact_match.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",

  config: {
    "judge_model" => "gpt-4o",
    "custom_instructions" => "Evaluate if the greeting matches the expected format and tone for a password reset inquiry. Consider accuracy, tone, and clarity."
  },
  enabled: true
)

# Test 5: Complex Regex Patterns for Technical Content
test_technical_patterns = code_review_v1.prompt_tests.create!(
  name: "Technical Content Pattern Validation",
  description: "Validates technical content with complex regex patterns for code snippets, technical terms, and formatting",
  tags: [ "technical", "complex-patterns", "code-review" ],
  enabled: true
)

# Add pattern match evaluator (binary mode)
test_technical_patterns.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  enabled: true,
  config: {
    patterns: [
      "```python[\\s\\S]*```",  # Must contain Python code block
      "\\b(list comprehension|comprehension)\\b",  # Must mention list comprehension
      "\\b(filter|filtering|condition)\\b",  # Must mention filtering
      "\\b(performance|efficiency|optimization)\\b",  # Must discuss performance
      "\\b(edge case|edge-case|boundary)\\b",  # Must mention edge cases
      "\\b(empty|None|null|zero)\\b",  # Must consider empty/null cases
      "(?i)\\b(test|testing|unit test)\\b",  # Must mention testing (case insensitive)
      "\\b[A-Z][a-z]+\\s+[a-z]+\\s+[a-z]+",  # Must have proper sentences
      "\\d+",  # Must contain at least one number
      "\\b(could|should|might|consider|recommend)\\b"  # Must use suggestive language
    ],
    match_all: true
  }
)

test_technical_patterns.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",

  config: {
    "min_length" => 250,
    "max_length" => 1200
  },
  enabled: true
)

test_technical_patterns.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",

  config: {
    "required_keywords" => [ "comprehension", "performance", "edge case" ],
    "forbidden_keywords" => [],
    "case_sensitive" => false
  },
  enabled: true
)

test_technical_patterns.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::FormatEvaluator",

  config: {
    "expected_format" => "markdown",
    "strict" => false
  },
  enabled: true
)

test_technical_patterns.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",

  config: {
    "judge_model" => "gpt-4o",
    "custom_instructions" => "Evaluate the technical accuracy and completeness of the code review. It should identify the list comprehension, discuss performance implications, mention edge cases, and suggest testing. Consider technical accuracy, completeness, helpfulness, and professionalism."
  },
  enabled: true
)

# ============================================================================
# 5. Create Sample LLM Responses
# ============================================================================

puts "  Creating sample LLM responses..."

# Successful responses for support greeting v3
5.times do |i|
  response = support_greeting_v3.llm_responses.create!(
    rendered_prompt: "Hi John! Thanks for contacting us. I'm here to help with your billing question. What's going on?",
    variables_used: { "customer_name" => "John", "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-4o",
    user_id: "user_#{i + 1}",
    session_id: "session_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "I'd be happy to help you with your billing question. Could you please provide more details about the specific issue you're experiencing?",
    response_time_ms: rand(800..1500),
    tokens_prompt: 25,
    tokens_completion: rand(20..30),
    tokens_total: rand(45..55),
    cost_usd: rand(0.0008..0.0015).round(6),
    response_metadata: { "finish_reason" => "stop", "model" => "gpt-4-0125-preview" }
  )
end

# Failed response
failed_response = support_greeting_v3.llm_responses.create!(
  rendered_prompt: "Hi Jane! Thanks for contacting us. I'm here to help with your technical question. What's going on?",
  variables_used: { "customer_name" => "Jane", "issue_category" => "technical" },
  provider: "openai",
  model: "gpt-4o",
  user_id: "user_6",
  session_id: "session_6",
  environment: "production"
)

failed_response.mark_error!(
  error_type: "OpenAI::RateLimitError",
  error_message: "Rate limit exceeded. Please try again in 20 seconds.",
  response_time_ms: 450
)

# Timeout response
timeout_response = support_greeting_v3.llm_responses.create!(
  rendered_prompt: "Hi Bob! Thanks for contacting us. I'm here to help with your account question. What's going on?",
  variables_used: { "customer_name" => "Bob", "issue_category" => "account" },
  provider: "anthropic",
  model: "claude-3-opus",
  user_id: "user_7",
  session_id: "session_7",
  environment: "production"
)

timeout_response.mark_timeout!(
  response_time_ms: 30000,
  error_message: "Request timed out after 30 seconds"
)

# Responses for older versions (v1 and v2)
2.times do |i|
  response = support_greeting_v1.llm_responses.create!(
    rendered_prompt: "Hello Sarah! Thank you for contacting support. How can I help you with billing today?",
    variables_used: { "customer_name" => "Sarah", "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-3.5-turbo",
    user_id: "user_old_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "I would be pleased to assist you with your billing inquiry.",
    response_time_ms: rand(600..1000),
    tokens_total: rand(30..40),
    cost_usd: rand(0.0003..0.0006).round(6)
  )
end

# Email summary responses
3.times do |i|
  response = email_summary_v1.llm_responses.create!(
    rendered_prompt: "Summarize the following email thread in 2-3 sentences:\n\nLong email thread here...",
    variables_used: { "email_thread" => "Long email thread here..." },
    provider: "openai",
    model: "gpt-4o",
    user_id: "user_email_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "The email thread discusses the upcoming product launch. The team agrees on a March 15th release date. Action items include finalizing the marketing materials and scheduling a press release.",
    response_time_ms: rand(1000..2000),
    tokens_total: rand(60..80),
    cost_usd: rand(0.0015..0.0025).round(6)
  )
end

# ============================================================================
# 5. Create Sample Evaluations
# ============================================================================

puts "  Creating sample evaluations..."

# Get successful responses
successful_responses = PromptTracker::LlmResponse.successful.limit(5)

successful_responses.each_with_index do |response, i|
  # Keyword evaluation
  score = rand(70..100)
  response.evaluations.create!(
    score: score,
    score_max: 100,
    passed: score >= 80,
    evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
    feedback: [ "Great response!", "Very helpful", "Could be more concise", "Perfect tone" ][i % 4],
    metadata: {
      "required_found" => rand(2..3),
      "forbidden_found" => 0,
      "total_keywords" => 3
    }
  )

  # Length evaluation
  score = rand(70..95)
  response.evaluations.create!(
    score: score,
    score_max: 100,
    passed: score >= 80,
    evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
    metadata: {
      "actual_length" => rand(80..150),
      "min_length" => 50,
      "max_length" => 200
    }
  )

  # LLM judge evaluation (for some responses)
  if i.even?
    score = rand(70..95)
    response.evaluations.create!(
      score: score,
      score_max: 100,
      passed: score >= 80,
      evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
      feedback: "The response is helpful and maintains a professional yet friendly tone.",
      metadata: {
        "judge_model" => "gpt-4o",
        "custom_instructions" => "Evaluate helpfulness and professionalism",
        "reasoning" => "Good balance of professionalism and warmth",
        "evaluation_cost_usd" => 0.0002
      }
    )
  end
end

# ============================================================================
# 6. Create Sample A/B Tests
# ============================================================================

puts "  Creating sample A/B tests..."

# A/B Test 1: Draft - Testing casual vs empathetic greeting
ab_test_greeting_draft = support_greeting.ab_tests.create!(
  name: "Casual vs Empathetic Greeting",
  description: "Testing if a more empathetic greeting improves customer satisfaction",
  hypothesis: "More empathetic greeting will increase satisfaction scores by 15%",
  status: "draft",
  metric_to_optimize: "quality_score",
  optimization_direction: "maximize",
  traffic_split: { "A" => 50, "B" => 50 },
  variants: [
    { "name" => "A", "version_id" => support_greeting_v4.id, "description" => "Casual version" },
    { "name" => "B", "version_id" => support_greeting_v5.id, "description" => "Empathetic version" }
  ],
  confidence_level: 0.95,
  minimum_sample_size: 100,
  created_by: "sarah@example.com"
)

# A/B Test 2: Running - Testing current vs casual greeting
ab_test_greeting_running = support_greeting.ab_tests.create!(
  name: "Current vs Casual Greeting",
  description: "Testing if casual greeting reduces response time while maintaining quality",
  hypothesis: "Casual greeting will reduce response time by 20% without hurting satisfaction",
  status: "running",
  metric_to_optimize: "response_time",
  optimization_direction: "minimize",
  traffic_split: { "A" => 70, "B" => 30 },
  variants: [
    { "name" => "A", "version_id" => support_greeting_v3.id, "description" => "Current active version" },
    { "name" => "B", "version_id" => support_greeting_v4.id, "description" => "Casual version" }
  ],
  confidence_level: 0.95,
  minimum_sample_size: 200,
  minimum_detectable_effect: 0.15,
  started_at: 3.days.ago,
  created_by: "john@example.com"
)

# Create some responses for the running A/B test
puts "  Creating A/B test responses..."

# Variant A responses (current version)
15.times do |i|
  response = support_greeting_v3.llm_responses.create!(
    rendered_prompt: "Hi #{[ 'Alice', 'Bob', 'Charlie' ][i % 3]}! Thanks for contacting us. I'm here to help with your billing question. What's going on?",
    variables_used: { "customer_name" => [ "Alice", "Bob", "Charlie" ][i % 3], "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-4o",
    user_id: "ab_test_user_a_#{i + 1}",
    session_id: "ab_test_session_a_#{i + 1}",
    environment: "production",
    ab_test_id: ab_test_greeting_running.id,
    ab_variant: "A"
  )

  response.mark_success!(
    response_text: "I'd be happy to help you with your billing question. Could you please provide more details?",
    response_time_ms: rand(1000..1400),
    tokens_prompt: 25,
    tokens_completion: rand(20..30),
    tokens_total: rand(45..55),
    cost_usd: rand(0.0008..0.0015).round(6),
    response_metadata: { "finish_reason" => "stop", "model" => "gpt-4-0125-preview" }
  )

  # Add evaluation
  response.evaluations.create!(
    score: rand(80..95),
    score_max: 100,
    passed: rand > 0.2,  # 80% pass rate
    evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
    metadata: { "judge_model" => "gpt-4o" }
  )
end

# Variant B responses (casual version)
8.times do |i|
  response = support_greeting_v4.llm_responses.create!(
    rendered_prompt: "Hey #{[ 'Dave', 'Eve', 'Frank' ][i % 3]}! What's up with billing?",
    variables_used: { "customer_name" => [ "Dave", "Eve", "Frank" ][i % 3], "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-4o",
    user_id: "ab_test_user_b_#{i + 1}",
    session_id: "ab_test_session_b_#{i + 1}",
    environment: "production",
    ab_test_id: ab_test_greeting_running.id,
    ab_variant: "B"
  )

  response.mark_success!(
    response_text: "Sure thing! What's the issue with your billing?",
    response_time_ms: rand(800..1100),
    tokens_prompt: 15,
    tokens_completion: rand(10..20),
    tokens_total: rand(25..35),
    cost_usd: rand(0.0005..0.0010).round(6),
    response_metadata: { "finish_reason" => "stop", "model" => "gpt-4-0125-preview" }
  )

  # Add evaluation
  response.evaluations.create!(
    score: rand(75..90),
    score_max: 100,
    passed: rand > 0.3,  # 70% pass rate
    evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
    metadata: { "judge_model" => "gpt-4o" }
  )
end

# A/B Test 3: Completed - Email summary format test
ab_test_email_completed = email_summary.ab_tests.create!(
  name: "Paragraph vs Bullet Points",
  description: "Testing if bullet point format is preferred over paragraph format",
  hypothesis: "Bullet points will be easier to scan and increase user satisfaction",
  status: "completed",
  metric_to_optimize: "quality_score",
  optimization_direction: "maximize",
  traffic_split: { "A" => 50, "B" => 50 },
  variants: [
    { "name" => "A", "version_id" => email_summary_v1.id, "description" => "Paragraph format" },
    { "name" => "B", "version_id" => email_summary_v2.id, "description" => "Bullet points" }
  ],
  confidence_level: 0.95,
  minimum_sample_size: 50,
  started_at: 10.days.ago,
  completed_at: 2.days.ago,
  results: {
    "winner" => "B",
    "is_significant" => true,
    "p_value" => 0.003,
    "improvement" => 18.5,
    "recommendation" => "Promote variant B to production",
    "A" => { "count" => 50, "mean" => 4.2, "std_dev" => 0.5 },
    "B" => { "count" => 50, "mean" => 4.8, "std_dev" => 0.4 }
  },
  created_by: "alice@example.com"
)

# ============================================================================
# Summary
# ============================================================================

puts "\n✅ Seeding complete!"
puts "\nCreated:"
puts "  - #{PromptTracker::Prompt.count} prompts"
puts "  - #{PromptTracker::PromptVersion.count} prompt versions"
puts "    - #{PromptTracker::PromptVersion.active.count} active"
puts "    - #{PromptTracker::PromptVersion.draft.count} draft"
puts "    - #{PromptTracker::PromptVersion.deprecated.count} deprecated"
puts "  - #{PromptTracker::PromptTest.count} prompt tests"
puts "    - #{PromptTracker::PromptTest.enabled.count} enabled"
puts "  - #{PromptTracker::LlmResponse.count} LLM responses"
puts "    - #{PromptTracker::LlmResponse.successful.count} successful"
puts "    - #{PromptTracker::LlmResponse.failed.count} failed"
puts "  - #{PromptTracker::Evaluation.count} evaluations"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%LlmJudgeEvaluator").count} LLM judge"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%KeywordEvaluator").count} keyword"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%LengthEvaluator").count} length"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%PatternMatchEvaluator").count} pattern match"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%ExactMatchEvaluator").count} exact match"
puts "    - #{PromptTracker::Evaluation.where("evaluator_type LIKE ?", "%FormatEvaluator").count} format"
puts "  - #{PromptTracker::AbTest.count} A/B tests"
puts "    - #{PromptTracker::AbTest.draft.count} draft"
puts "    - #{PromptTracker::AbTest.running.count} running"
puts "    - #{PromptTracker::AbTest.completed.count} completed"
puts "\nTotal cost: $#{PromptTracker::LlmResponse.sum(:cost_usd).round(4)}"
puts "Average response time: #{PromptTracker::LlmResponse.successful.average(:response_time_ms).to_i}ms"
puts "\n🎉 Ready to explore!"
puts "\n💡 Tips:"
puts "  - Visit /prompt_tracker to see all prompts"
puts "  - Check out the running A/B test: '#{ab_test_greeting_running.name}'"
puts "  - View tests for customer_support_greeting v3 (#{support_greeting_v3.prompt_tests.count} tests)"
puts "  - Advanced tests include:"
puts "    • Comprehensive Quality Check (3 evaluators: length, keyword, LLM judge)"
puts "    • Email Summary Format Validation (complex regex patterns)"
puts "    • Code Review Quality Assessment (LLM judge + keyword validation)"
puts "    • Exact Output Validation (exact match + quality checks)"
puts "    • Technical Content Pattern Validation (10 complex regex patterns + 4 evaluators)"
puts "  - Create new A/B tests with draft versions v4 and v5"
