# frozen_string_literal: true

# ============================================================================
# Code Review Agents
# ============================================================================

puts "  Creating code review agents..."

code_review = PromptTracker::Agent.create!(
  name: "code_review_assistant",
  description: "Provides constructive code review feedback",
  category: "development",
  tags: [ "code-quality", "engineering" ],
  created_by: "engineering@example.com"
)

code_review_v1 = code_review.agent_versions.create!(
    system_prompt: <<~SYSTEM.strip,
    You are a code review assistant that provides constructive feedback on code snippets.

    When given code, review the following {{language}} code and provide constructive feedback:

    ```{{language}}
    {{code}}
    ```

    Focus on:
    - Code quality and readability
    - Potential bugs or edge cases
    - Performance considerations
    - Best practices

    Be constructive and specific.
  SYSTEM
  status: "active",
  variables_schema: [
    { "name" => "language", "type" => "string", "required" => true },
    { "name" => "code", "type" => "string", "required" => true }
  ],
  model_config: {
    "provider" => "openai",
    "api" => "chat_completions",
    "model" => "gpt-4o",
    "temperature" => 0.4,
    "max_tokens" => 500
  },
  mcp_servers: [ "filesystem" ],
  created_by: "bob@example.com"
)

puts "  ✓ Created code review agents (1 agent, 1 version with MCP: filesystem)"
