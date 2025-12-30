# frozen_string_literal: true

# ============================================================================
# Code Review Prompts
# ============================================================================

puts "  Creating code review prompts..."

code_review = PromptTracker::Prompt.create!(
  name: "code_review_assistant",
  description: "Provides constructive code review feedback",
  category: "development",
  tags: [ "code-quality", "engineering" ],
  created_by: "engineering@example.com"
)

code_review_v1 = code_review.prompt_versions.create!(
  user_prompt: <<~TEMPLATE,
    Review the following {{language}} code and provide constructive feedback:

    ```{{language}}
    {{code}}
    ```

    Focus on:
    - Code quality and readability
    - Potential bugs or edge cases
    - Performance considerations
    - Best practices

    Be constructive and specific.
  TEMPLATE
  status: "active",
  variables_schema: [
    { "name" => "language", "type" => "string", "required" => true },
    { "name" => "code", "type" => "string", "required" => true }
  ],
  model_config: { "temperature" => 0.4, "max_tokens" => 500 },
  created_by: "bob@example.com"
)

puts "  ✓ Created code review prompts (1 prompt, 1 version)"
