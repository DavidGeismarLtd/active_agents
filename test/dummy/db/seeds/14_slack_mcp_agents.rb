# frozen_string_literal: true

# ============================================================================
# SLACK MCP AGENTS SEEDS
# ============================================================================
# This file creates example Slack task agents using the Slack MCP server.
# These agents demonstrate integration with external tools via Model Context Protocol.

puts "\n💬 Seeding Slack MCP Agents..."

# ============================================================================
# 1. Slack Channel Lister Prompt & Agent
# ============================================================================

slack_lister_prompt = PromptTracker::Prompt.create!(
  name: "slack_channel_lister",
  description: "Lists all Slack channels in the workspace",
  category: "integration",
  tags: [ "slack", "mcp", "channels" ]
)

slack_lister_version = slack_lister_prompt.prompt_versions.create!(
  user_prompt: "You are a helpful assistant that lists Slack channels.",
  system_prompt: "Use the available Slack tools to list all channels in the workspace. Present the results in a clear, organized format.",
  model_config: {
    provider: "openai",
    api: "chat_completions",
    model: "gpt-4o-mini",
    temperature: 0.3
  },
  mcp_servers: [ "slack" ],
  status: "active"
)

slack_lister_agent = PromptTracker::DeployedAgent.create!(
  prompt_version: slack_lister_version,
  name: "Slack Channel Lister",
  agent_type: "task",
  task_config: {
    "initial_prompt" => "List all Slack channels in the workspace and provide a summary of how many channels exist.",
    "execution" => {
      "max_iterations" => 3,
      "timeout_seconds" => 300
    }
  }
)

puts "  ✓ Created 'Slack Channel Lister' prompt, version, and agent"

# ============================================================================
# 2. Slack Message Sender Prompt & Agent
# ============================================================================

slack_sender_prompt = PromptTracker::Prompt.create!(
  name: "slack_message_sender",
  description: "Sends messages to Slack channels",
  category: "integration",
  tags: [ "slack", "mcp", "messaging" ]
)

slack_sender_version = slack_sender_prompt.prompt_versions.create!(
  user_prompt: "You are a helpful assistant that sends messages to Slack channels.",
  system_prompt: "Use the available Slack tools to send messages to specified channels. Always confirm the channel exists before sending.",
  model_config: {
    provider: "openai",
    api: "chat_completions",
    model: "gpt-4o-mini",
    temperature: 0.3
  },
  mcp_servers: [ "slack" ],
  status: "active"
)

slack_sender_agent = PromptTracker::DeployedAgent.create!(
  prompt_version: slack_sender_version,
  name: "Slack Message Sender",
  agent_type: "task",
  task_config: {
    "initial_prompt" => "First, list all available Slack channels. Then send the message '{{message}}' to the channel named '{{channel_name}}'.",
    "variables" => {
      "channel_name" => "general",
      "message" => "Hello from PromptTracker MCP integration! 🚀"
    },
    "execution" => {
      "max_iterations" => 5,
      "timeout_seconds" => 300
    }
  }
)

puts "  ✓ Created 'Slack Message Sender' prompt, version, and agent"

# ============================================================================
# 3. Slack Team Reporter Prompt & Agent
# ============================================================================

slack_reporter_prompt = PromptTracker::Prompt.create!(
  name: "slack_team_reporter",
  description: "Generates reports about Slack workspace activity",
  category: "integration",
  tags: [ "slack", "mcp", "reporting", "analytics" ]
)

slack_reporter_version = slack_reporter_prompt.prompt_versions.create!(
  user_prompt: "You are a helpful assistant that analyzes Slack workspace data.",
  system_prompt: "Use the available Slack tools to gather information about channels, users, and recent activity. Create comprehensive reports with insights.",
  model_config: {
    provider: "openai",
    api: "chat_completions",
    model: "gpt-4o",
    temperature: 0.5
  },
  mcp_servers: [ "slack" ],
  status: "active"
)

slack_reporter_agent = PromptTracker::DeployedAgent.create!(
  prompt_version: slack_reporter_version,
  name: "Slack Team Reporter",
  agent_type: "task",
  task_config: {
    "initial_prompt" => "Generate a workspace report including: 1) Total number of channels, 2) Total number of users, 3) Recent activity in the #general channel (last 5 messages).",
    "execution" => {
      "max_iterations" => 10,
      "timeout_seconds" => 600
    }
  }
)

puts "  ✓ Created 'Slack Team Reporter' prompt, version, and agent"

puts "  📊 Summary: Created 3 Slack MCP agents"
puts "     - Slack Channel Lister (ID: #{slack_lister_agent.id})"
puts "     - Slack Message Sender (ID: #{slack_sender_agent.id})"
puts "     - Slack Team Reporter (ID: #{slack_reporter_agent.id})"
