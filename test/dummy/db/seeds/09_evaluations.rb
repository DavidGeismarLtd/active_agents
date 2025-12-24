# frozen_string_literal: true

# ============================================================================
# Sample Evaluations
# ============================================================================

puts "  Creating sample evaluations..."

# Get successful responses
successful_responses = PromptTracker::LlmResponse.successful.limit(5)

successful_responses.each_with_index do |response, i|
  # Keyword evaluation
  score = rand(70..100)
  response.evaluations.create!(
    score: score,
    passed: score >= 80,
    evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
    metadata: {
      "required_found" => rand(2..3),
      "forbidden_found" => 0,
      "total_keywords" => 3
    },
    evaluation_context: "tracked_call"
  )

  # Length evaluation
  score = rand(70..95)
  response.evaluations.create!(
    score: score,
    passed: score >= 80,
    evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
    metadata: {
      "actual_length" => rand(80..150),
      "min_length" => 50,
      "max_length" => 200
    },
    evaluation_context: "tracked_call"
  )

  # LLM judge evaluation (for some responses)
  if i.even?
    score = rand(70..95)
    response.evaluations.create!(
      score: score,
      passed: score >= 80,
      evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
      metadata: {
        "judge_model" => "gpt-4o",
        "custom_instructions" => "Evaluate helpfulness and professionalism",
        "reasoning" => "Good balance of professionalism and warmth",
        "evaluation_cost_usd" => 0.0002
      },
      evaluation_context: "tracked_call"
    )
  end
end

puts "  ✓ Created sample evaluations (~15 evaluations for tracked calls)"
