# frozen_string_literal: true

# ============================================================================
# Basic Tests with Single Evaluators
# ============================================================================

puts "  Creating basic tests..."

# Get the active customer support greeting version
support_greeting_v3 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "customer_support_greeting" })
  .where(status: "active")
  .first!

# Tests for support greeting v3 (active version)
test_greeting_premium = support_greeting_v3.tests.create!(
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

test_greeting_technical = support_greeting_v3.tests.create!(
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

test_greeting_account = support_greeting_v3.tests.create!(
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

test_greeting_general = support_greeting_v3.tests.create!(
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
test_greeting_edge = support_greeting_v3.tests.create!(
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

puts "  ✓ Created basic tests (5 tests with single evaluators)"
