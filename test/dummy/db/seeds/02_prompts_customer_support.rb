# frozen_string_literal: true

# ============================================================================
# Customer Support Prompts
# ============================================================================

puts "  Creating customer support prompts..."

support_greeting = PromptTracker::Prompt.create!(
  name: "customer_support_greeting",
  description: "Initial greeting for customer support interactions",
  category: "support",
  tags: [ "customer-facing", "greeting", "high-priority" ],
  created_by: "support-team@example.com"
)

# Version 1 - Original (using Chat Completion API)
support_greeting_v1 = support_greeting.prompt_versions.create!(
  user_prompt: "Hello {{customer_name}}! Thank you for contacting support. How can I help you with {{issue_category}} today?",
  status: "deprecated",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true },
    { "name" => "issue_category", "type" => "string", "required" => false }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "chat_completions",
    "model" => "gpt-4o-mini",
    "temperature" => 0.7,
    "max_tokens" => 150
  },
  notes: "Original version - too formal",
  created_by: "john@example.com"
)

# Version 2 - More casual
support_greeting_v2 = support_greeting.prompt_versions.create!(
  user_prompt: "Hi {{customer_name}}! 👋 Thanks for reaching out. What can I help you with today?",
  status: "deprecated",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "chat_completions",
    "model" => "gpt-4o-mini",
    "temperature" => 0.8,
    "max_tokens" => 100
  },
  notes: "Tested in web UI - more casual tone",
  created_by: "sarah@example.com"
)

# Version 3 - Current active version (using GPT-4o for better quality)
support_greeting_v3 = support_greeting.prompt_versions.create!(
  user_prompt: "Hi {{customer_name}}! Thanks for contacting us. I'm here to help with your {{issue_category}} question. What's going on?",
  status: "active",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true },
    { "name" => "issue_category", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "chat_completions",
    "model" => "gpt-4o",
    "temperature" => 0.7,
    "max_tokens" => 120
  },
  notes: "Best performing version - friendly but professional",
  created_by: "john@example.com"
)

# Version 4 - Draft: Testing with Responses API
support_greeting_v4 = support_greeting.prompt_versions.create!(
  user_prompt: "Hey {{customer_name}}! What's up with {{issue_category}}?",
  status: "draft",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true },
    { "name" => "issue_category", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "responses",
    "model" => "gpt-4o-mini",
    "temperature" => 0.9,
    "max_tokens" => 80
  },
  notes: "Testing Responses API - casual tone with web search capability",
  created_by: "sarah@example.com"
)

# Version 5 - Draft: Using Anthropic Claude
support_greeting_v5 = support_greeting.prompt_versions.create!(
  user_prompt: "Hi {{customer_name}}, I understand you're having an issue with {{issue_category}}. I'm here to help you resolve this. Can you tell me more about what's happening?",
  status: "draft",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true },
    { "name" => "issue_category", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "anthropic",
    "api" => "messages",
    "model" => "claude-sonnet-4-20250514",
    "temperature" => 0.6,
    "max_tokens" => 150
  },
  notes: "Testing Anthropic Claude - more empathetic approach",
  created_by: "alice@example.com"
)

puts "  ✓ Created customer support prompts (1 prompt, 5 versions)"
