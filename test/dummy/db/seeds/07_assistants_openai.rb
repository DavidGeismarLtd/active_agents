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
      "interlocutor_simulation_prompt" => "You are a patient experiencing a severe headache with sensitivity to light. You're worried it might be a migraine or something more serious. Be concerned but cooperative, and answer questions about duration and severity.",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a patient who has had a fever of 102°F for 2 days. You're feeling weak and concerned. You want to know if you should go to the emergency room or if you can wait to see your regular doctor.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a middle-aged patient experiencing chest pain that comes and goes. You're anxious about whether this could be heart-related. Be worried and ask direct questions about urgency.",
      "max_turns" => 2
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a patient with a persistent cough that has lasted for a week. You're a non-smoker and wondering if it could be COVID or something else. Be curious and ask about home remedies.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a patient experiencing abdominal pain after eating. You suspect it might be related to certain foods. Be detailed about your symptoms and ask for dietary advice.",
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
      "interlocutor_simulation_prompt" => "You are a frustrated customer who can't log into your account. You've tried resetting your password multiple times. Be impatient but willing to follow troubleshooting steps.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are an upset customer who was charged twice for your subscription. You want a refund immediately. Be firm but professional, and ask for confirmation of the refund.",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a customer who needs to export your data before switching to a competitor. Be polite but direct, and ask about data formats and privacy.",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a customer experiencing app crashes when uploading files. You're on a deadline and getting increasingly frustrated. Provide technical details when asked.",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a customer who wants to cancel your subscription because you found a cheaper alternative. Be open to retention offers but firm about canceling if not satisfied.",
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
      "interlocutor_simulation_prompt" => "You are a backend developer reporting that your API is returning 500 errors intermittently. You've checked the logs but can't find a pattern. Be technical and provide details when asked about error rates, endpoints affected, and recent changes.",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a DevOps engineer noticing that the application has been running very slowly since yesterday. You suspect it might be database-related. Be methodical and willing to run diagnostic commands.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a developer getting 'connection refused' errors when trying to connect to the database. You're working on a tight deadline and need a quick resolution. Be stressed but cooperative.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a DevOps engineer whose deployment just failed with a cryptic error message. You've tried redeploying twice with the same result. Be frustrated and provide the error message when asked.",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You are a product manager reporting that users are experiencing authentication errors after login. This started after a recent deployment. Be concerned about user impact and ask about rollback options.",
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
