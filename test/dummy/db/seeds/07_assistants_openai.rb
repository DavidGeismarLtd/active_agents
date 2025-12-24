# frozen_string_literal: true

# ============================================================================
# OpenAI Assistants (Multi-turn Conversation Testing)
# ============================================================================

puts "  Creating OpenAI assistants..."

# ============================================================================
# 1. Medical Triage Assistant
# ============================================================================

medical_assistant = PromptTracker::Openai::Assistant.new(
  name: "medical_triage_assistant",
  description: "Helps triage patient symptoms and recommend next steps",
  assistant_id: "asst_medical_triage_001",  # Mock ID for demo
  category: "healthcare",
  skip_fetch_from_openai: true,  # Don't fetch from OpenAI during seeding
  metadata: {
    "instructions" => <<~INSTRUCTIONS.strip,
      You are a medical triage assistant. Your role is to:
      1. Ask clarifying questions about symptoms (duration, severity, other symptoms)
      2. Assess urgency level based on symptoms
      3. Provide clear next steps (emergency care, doctor visit, self-care)
      4. Show empathy and professionalism
      5. NEVER provide medical diagnoses - only triage guidance

      Always be empathetic, ask relevant follow-up questions, and provide clear guidance.
    INSTRUCTIONS
    "model" => "gpt-4o",
    "tools" => []
  }
)
medical_assistant.save!

# Create dataset for medical assistant
medical_dataset = PromptTracker::Dataset.create!(
  testable: medical_assistant,
  name: "Common Symptoms",
  description: "Test cases for common medical symptoms"
)

medical_dataset.dataset_rows.create!([
  {
    row_data: {
      "user_prompt" => "I have a severe headache and sensitivity to light",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "user_prompt" => "I've had a fever of 102°F for 2 days",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "user_prompt" => "I have chest pain that comes and goes",
      "max_turns" => 2
    }
  },
  {
    row_data: {
      "user_prompt" => "I've had a persistent cough for a week",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "user_prompt" => "I have abdominal pain after eating",
      "max_turns" => 3
    }
  }
])

# Create test with ConversationJudgeEvaluator
medical_test = PromptTracker::Test.create!(
  testable: medical_assistant,
  name: "Symptom Triage Quality",
  description: "Evaluates quality of symptom triage conversations",
  enabled: true
)

medical_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    "judge_model" => "gpt-4o",
    "evaluation_prompt" => <<~PROMPT.strip,
      Evaluate this medical triage response for:
      1. Empathy and bedside manner (0-100)
      2. Asking appropriate follow-up questions (0-100)
      3. Providing clear next steps (0-100)
      4. Avoiding medical advice beyond triage scope (0-100)

      Consider the overall quality of the triage conversation.
    PROMPT
    "threshold_score" => 75
  }
)

puts "  ✓ Created medical triage assistant with dataset and test"

# ============================================================================
# 2. Customer Support Assistant
# ============================================================================

support_assistant = PromptTracker::Openai::Assistant.new(
  name: "customer_support_assistant",
  description: "Handles customer inquiries and resolves common issues",
  assistant_id: "asst_support_001",  # Mock ID for demo
  category: "customer-service",
  skip_fetch_from_openai: true,  # Don't fetch from OpenAI during seeding
  metadata: {
    "instructions" => <<~INSTRUCTIONS.strip,
      You are a customer support assistant. Your role is to:
      1. Listen to customer concerns with empathy
      2. Ask clarifying questions to understand the issue
      3. Provide clear solutions or next steps
      4. Maintain a professional yet friendly tone
      5. Escalate to human support when necessary

      Always be helpful, patient, and solution-oriented.
    INSTRUCTIONS
    "model" => "gpt-4o-mini",
    "tools" => []
  }
)
support_assistant.save!

# Create dataset for support assistant
support_dataset = PromptTracker::Dataset.create!(
  testable: support_assistant,
  name: "Common Support Issues",
  description: "Test cases for common customer support scenarios"
)

support_dataset.dataset_rows.create!([
  {
    row_data: {
      "user_prompt" => "I can't log into my account",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "user_prompt" => "I was charged twice for my subscription",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "user_prompt" => "How do I export my data?",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "user_prompt" => "The app keeps crashing when I try to upload files",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "user_prompt" => "I want to cancel my subscription",
      "max_turns" => 4
    }
  }
])

# Create test with ConversationJudgeEvaluator
support_test = PromptTracker::Test.create!(
  testable: support_assistant,
  name: "Support Quality & Resolution",
  description: "Evaluates quality of customer support conversations",
  enabled: true
)

support_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    "judge_model" => "gpt-4o-mini",
    "evaluation_prompt" => <<~PROMPT.strip,
      Evaluate this support conversation for:
      1. Professionalism and empathy (0-100)
      2. Problem-solving approach (0-100)
      3. Clear communication (0-100)
      4. Timely resolution (0-100)

      Consider the overall quality of the support interaction.
    PROMPT
    "threshold_score" => 70
  }
)

puts "  ✓ Created customer support assistant with dataset and test"

# ============================================================================
# 3. Technical Support Assistant
# ============================================================================

tech_assistant = PromptTracker::Openai::Assistant.new(
  name: "technical_support_assistant",
  description: "Provides technical troubleshooting for software issues",
  assistant_id: "asst_tech_support_001",  # Mock ID for demo
  category: "technical",
  skip_fetch_from_openai: true,  # Don't fetch from OpenAI during seeding
  metadata: {
    "instructions" => <<~INSTRUCTIONS.strip,
      You are a technical support assistant. Your role is to:
      1. Use systematic troubleshooting methodology
      2. Ask diagnostic questions to narrow down the issue
      3. Provide clear, step-by-step solutions
      4. Explain technical concepts in accessible language
      5. Escalate complex issues to engineering when needed

      Always be methodical, clear, and patient with users of all technical levels.
    INSTRUCTIONS
    "model" => "gpt-4o",
    "tools" => [ { "type" => "code_interpreter" } ]
  }
)
tech_assistant.save!

# Create dataset for tech support assistant
tech_dataset = PromptTracker::Dataset.create!(
  testable: tech_assistant,
  name: "Technical Issues",
  description: "Test cases for common technical support scenarios"
)

tech_dataset.dataset_rows.create!([
  {
    row_data: {
      "user_prompt" => "Our API is returning 500 errors intermittently",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "user_prompt" => "The application is running very slowly since yesterday",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "user_prompt" => "I'm getting 'connection refused' when trying to connect to the database",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "user_prompt" => "Our deployment failed with a cryptic error message",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "user_prompt" => "Users are reporting authentication errors after login",
      "max_turns" => 4
    }
  }
])

# Create test with ConversationJudgeEvaluator
tech_test = PromptTracker::Test.create!(
  testable: tech_assistant,
  name: "Technical Troubleshooting Quality",
  description: "Evaluates quality of technical support conversations",
  enabled: true
)

tech_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    "judge_model" => "gpt-4o",
    "evaluation_prompt" => <<~PROMPT.strip,
      Evaluate this technical support conversation for:
      1. Systematic troubleshooting approach (0-100)
      2. Asking relevant diagnostic questions (0-100)
      3. Technical accuracy (0-100)
      4. Clear explanations for non-technical users (0-100)

      Consider the overall quality of the technical support interaction.
    PROMPT
    "threshold_score" => 80
  }
)

puts "  ✓ Created technical support assistant with dataset and test"

puts "\n  ✅ Created 3 OpenAI assistants with datasets and tests"
