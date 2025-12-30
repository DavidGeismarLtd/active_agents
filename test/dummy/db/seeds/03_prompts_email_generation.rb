# frozen_string_literal: true

# ============================================================================
# Email Generation Prompts
# ============================================================================

puts "  Creating email generation prompts..."

email_summary = PromptTracker::Prompt.create!(
  name: "email_summary_generator",
  description: "Generates concise summaries of long email threads",
  category: "email",
  tags: [ "productivity", "summarization" ],
  created_by: "product-team@example.com"
)

email_summary_v1 = email_summary.prompt_versions.create!(
  user_prompt: "Summarize the following email thread in 2-3 sentences:\n\n{{email_thread}}",
  status: "active",
  variables_schema: [
    { "name" => "email_thread", "type" => "string", "required" => true }
  ],
  model_config: { "temperature" => 0.3, "max_tokens" => 200 },
  created_by: "alice@example.com"
)

# Version 2 - Draft: Bullet point format
email_summary_v2 = email_summary.prompt_versions.create!(
  user_prompt: "Summarize the following email thread as bullet points (3-5 key points):\n\n{{email_thread}}",
  status: "draft",
  variables_schema: [
    { "name" => "email_thread", "type" => "string", "required" => true }
  ],
  model_config: { "temperature" => 0.3, "max_tokens" => 250 },
  notes: "Testing bullet point format for easier scanning",
  created_by: "bob@example.com"
)

puts "  ✓ Created email generation prompts (1 prompt, 2 versions)"
