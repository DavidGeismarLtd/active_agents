# frozen_string_literal: true

# ============================================================================
# Sample A/B Tests
# ============================================================================

puts "  Creating sample A/B tests..."

# Get prompts and versions
support_greeting = PromptTracker::Prompt.find_by!(name: "customer_support_greeting")
support_greeting_v3 = support_greeting.prompt_versions.find_by!(status: "active")
support_greeting_v4 = support_greeting.prompt_versions.where(status: "draft").first!
support_greeting_v5 = support_greeting.prompt_versions.where(status: "draft").last!

email_summary = PromptTracker::Prompt.find_by!(name: "email_summary_generator")
email_summary_v1 = email_summary.prompt_versions.find_by!(status: "active")
email_summary_v2 = email_summary.prompt_versions.find_by!(status: "draft")

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
    passed: rand > 0.2,  # 80% pass rate
    evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
    metadata: { "judge_model" => "gpt-4o" },
    evaluation_context: "tracked_call"
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
    passed: rand > 0.3,  # 70% pass rate
    evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
    metadata: { "judge_model" => "gpt-4o" },
    evaluation_context: "tracked_call"
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

puts "  ✓ Created A/B tests (1 draft, 1 running with responses, 1 completed)"
