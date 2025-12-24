# frozen_string_literal: true

# ============================================================================
# Advanced Tests with Multiple Evaluators
# ============================================================================

puts "  Creating advanced tests with multiple evaluators..."

# Get prompt versions
support_greeting_v3 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "customer_support_greeting" })
  .where(status: "active")
  .first!

email_summary_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "email_summary_generator" })
  .where(status: "active")
  .first!

code_review_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "code_review_assistant" })
  .where(status: "active")
  .first!

# Test 1: Comprehensive Quality Check with Multiple Evaluators
test_comprehensive_quality = support_greeting_v3.tests.create!(
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
test_email_format = email_summary_v1.tests.create!(
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
test_code_review_quality = code_review_v1.tests.create!(
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
test_exact_match = support_greeting_v3.tests.create!(
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
test_technical_patterns = code_review_v1.tests.create!(
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

puts "  ✓ Created advanced tests (5 tests with multiple evaluators)"
