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

# ============================================================================
# 4. Travel Booking Assistant (with Functions)
# ============================================================================

travel_assistant = PromptTracker::Openai::Assistant.new(
  name: "travel_booking_assistant",
  description: "Helps users plan and book travel with function calling capabilities",
  assistant_id: "asst_travel_booking_001",  # Mock ID for demo
  category: "travel",
  skip_fetch_from_openai: true,  # Don't fetch from OpenAI during seeding
  metadata: {
    "instructions" => <<~INSTRUCTIONS.strip,
      You are a travel booking assistant. Your role is to:
      1. Help users search for flights and hotels
      2. Check weather at destinations
      3. Book travel arrangements when requested
      4. Provide travel recommendations and tips

      Use the available functions to look up real-time information.
      Always confirm booking details with the user before finalizing.
    INSTRUCTIONS
    "model" => "gpt-4o",
    "tools" => [
      {
        "type" => "function",
        "function" => {
          "name" => "search_flights",
          "description" => "Search for available flights between two airports",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "origin" => {
                "type" => "string",
                "description" => "Origin airport code (e.g., JFK, LAX)"
              },
              "destination" => {
                "type" => "string",
                "description" => "Destination airport code (e.g., LHR, CDG)"
              },
              "date" => {
                "type" => "string",
                "description" => "Departure date in YYYY-MM-DD format"
              },
              "passengers" => {
                "type" => "integer",
                "description" => "Number of passengers"
              }
            },
            "required" => [ "origin", "destination", "date" ]
          },
          "strict" => false
        }
      },
      {
        "type" => "function",
        "function" => {
          "name" => "search_hotels",
          "description" => "Search for available hotels in a city",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "city" => {
                "type" => "string",
                "description" => "City name to search for hotels"
              },
              "check_in" => {
                "type" => "string",
                "description" => "Check-in date in YYYY-MM-DD format"
              },
              "check_out" => {
                "type" => "string",
                "description" => "Check-out date in YYYY-MM-DD format"
              },
              "guests" => {
                "type" => "integer",
                "description" => "Number of guests"
              }
            },
            "required" => [ "city", "check_in", "check_out" ]
          },
          "strict" => false
        }
      },
      {
        "type" => "function",
        "function" => {
          "name" => "get_weather",
          "description" => "Get weather forecast for a location",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "location" => {
                "type" => "string",
                "description" => "City or location name"
              },
              "date" => {
                "type" => "string",
                "description" => "Date for weather forecast in YYYY-MM-DD format"
              }
            },
            "required" => [ "location" ]
          },
          "strict" => false
        }
      },
      {
        "type" => "function",
        "function" => {
          "name" => "book_flight",
          "description" => "Book a specific flight",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "flight_id" => {
                "type" => "string",
                "description" => "The flight ID to book"
              },
              "passenger_name" => {
                "type" => "string",
                "description" => "Full name of the passenger"
              },
              "seat_preference" => {
                "type" => "string",
                "enum" => [ "window", "aisle", "middle" ],
                "description" => "Preferred seat type"
              }
            },
            "required" => [ "flight_id", "passenger_name" ]
          },
          "strict" => false
        }
      }
    ]
  }
)
travel_assistant.save!

# Create dataset for travel assistant
travel_dataset = PromptTracker::Dataset.create!(
  testable: travel_assistant,
  name: "Travel Booking Scenarios",
  description: "Test cases for travel planning and booking with function calls"
)

travel_dataset.dataset_rows.create!([
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You want to book a flight from New York (JFK) to London (LHR) for next week. You're flexible on dates but prefer morning flights. Ask about prices and availability.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You're planning a vacation to Paris. You need both flights from Los Angeles and a hotel for 5 nights. Also ask about the weather during your trip.",
      "max_turns" => 5
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You want to check hotel options in Tokyo for a business trip. You need a hotel near the city center for 3 nights next month.",
      "max_turns" => 3
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You're looking to book a last-minute trip to Miami. Check if there are flights available from Chicago for this weekend and what the weather will be like.",
      "max_turns" => 4
    }
  },
  {
    row_data: {
      "interlocutor_simulation_prompt" => "You want to plan a family trip to Barcelona for 4 people. You need flights from Boston and a family-friendly hotel. Compare options and prices.",
      "max_turns" => 5
    }
  }
])

# Create test with Function Call Evaluator
travel_test = PromptTracker::Test.create!(
  testable: travel_assistant,
  name: "Travel Function Usage",
  description: "Evaluates if the assistant correctly uses travel-related functions",
  enabled: true
)

# Function Call Evaluator - check if search functions are called
travel_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::FunctionCallEvaluator",
  enabled: true,
  config: {
    "expected_functions" => [ "search_flights", "search_hotels", "get_weather" ],
    "require_all" => false,  # At least one of these should be called
    "check_arguments" => false,
    "threshold_score" => 80
  }
)

# Also add a conversation judge for quality
travel_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    "judge_model" => "gpt-4o-mini",
    "evaluation_prompt" => <<~PROMPT.strip,
      Evaluate this travel booking conversation for:
      1. Appropriate use of functions to gather information (0-100)
      2. Providing helpful travel recommendations (0-100)
      3. Clear communication of options and prices (0-100)
      4. Professional and friendly tone (0-100)

      Consider the overall quality of the travel planning interaction.
    PROMPT
    "threshold_score" => 75
  }
)

puts "  ✓ Created travel booking assistant with functions, dataset and test"

# Create a second test specifically for argument validation
travel_args_test = PromptTracker::Test.create!(
  testable: travel_assistant,
  name: "Travel Function Arguments",
  description: "Validates that function arguments are correctly formatted",
  enabled: true
)

travel_args_test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::FunctionCallEvaluator",
  enabled: true,
  config: {
    "expected_functions" => [ "search_flights" ],
    "require_all" => true,
    "check_arguments" => true,
    "expected_arguments" => {
      "search_flights" => {
        "origin" => "JFK"  # Expect JFK as origin for the first test case
      }
    },
    "threshold_score" => 80
  }
)

puts "  ✓ Created travel function arguments test"

puts "\n  ✅ Created 4 OpenAI assistants with datasets and tests"
