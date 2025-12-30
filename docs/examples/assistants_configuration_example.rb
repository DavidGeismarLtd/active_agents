# Example: OpenAI Assistants Configuration
# File: config/initializers/prompt_tracker.rb

PromptTracker.configure do |config|
  # ============================================================================
  # Available Models - Including OpenAI Assistants
  # ============================================================================

  config.available_models = {
    # Standard OpenAI Chat Completion Models
    openai: [
      { id: "gpt-4o", name: "GPT-4o", category: "Latest" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest" },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4" },
      { id: "gpt-4", name: "GPT-4", category: "GPT-4" },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5" }
    ],

    # OpenAI Assistants (Separate Provider)
    # Get your assistant IDs from: https://platform.openai.com/assistants
    # Or via API: openai api assistants.list
    openai_assistants: [
      # Customer Support Assistants
      {
        id: "asst_abc123xyz",
        name: "Customer Support - Tier 1",
        category: "Customer Support"
      },
      {
        id: "asst_def456uvw",
        name: "Customer Support - Technical",
        category: "Customer Support"
      },

      # Development Assistants
      {
        id: "asst_ghi789rst",
        name: "Code Review Assistant",
        category: "Development"
      },
      {
        id: "asst_jkl012opq",
        name: "Bug Triage Assistant",
        category: "Development"
      },

      # Content Assistants
      {
        id: "asst_mno345lmn",
        name: "Blog Post Writer",
        category: "Content"
      },
      {
        id: "asst_pqr678ijk",
        name: "Social Media Manager",
        category: "Content"
      },

      # Analytics Assistants
      {
        id: "asst_stu901ghi",
        name: "Data Analysis Assistant",
        category: "Analytics"
      },
      {
        id: "asst_vwx234def",
        name: "Report Generator",
        category: "Analytics"
      }
    ],

    # Anthropic Models
    anthropic: [
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5" },
      { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", category: "Claude 3.5" },
      { id: "claude-3-opus-20240229", name: "Claude 3 Opus", category: "Claude 3" }
    ]
  }

  # ============================================================================
  # Provider API Keys
  # ============================================================================
  # Note: openai_assistants uses the same API key as openai

  config.provider_api_key_env_vars = {
    openai: "OPENAI_API_KEY",
    openai_assistants: "OPENAI_API_KEY",  # Same key!
    anthropic: "ANTHROPIC_API_KEY"
  }

  # ============================================================================
  # Default Models for AI Features
  # ============================================================================

  config.prompt_generator_model = "gpt-4o-mini"
  config.dataset_generator_model = "gpt-4o"
  config.llm_judge_model = "gpt-4o"
end

# ============================================================================
# How to Find Your Assistant IDs
# ============================================================================

# Method 1: OpenAI Dashboard
# Visit: https://platform.openai.com/assistants
# Click on an assistant to see its ID (starts with "asst_")

# Method 2: OpenAI CLI
# $ openai api assistants.list

# Method 3: cURL
# $ curl https://api.openai.com/v1/assistants \
#   -H "Authorization: Bearer $OPENAI_API_KEY" \
#   -H "OpenAI-Beta: assistants=v2"

# Method 4: Ruby Script
# require 'openai'
# client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
# assistants = client.assistants.list
# assistants['data'].each do |asst|
#   puts "{ id: \"#{asst['id']}\", name: \"#{asst['name']}\", category: \"Assistants\" },"
# end

# ============================================================================
# UI Behavior After Configuration
# ============================================================================

# Provider Dropdown will show:
# ┌─────────────────────────┐
# │ Openai                  │  ← Chat Completion models
# │ Openai Assistants       │  ← Your configured assistants
# │ Anthropic               │  ← Claude models
# └─────────────────────────┘

# When "Openai Assistants" is selected, Model Dropdown shows:
# ┌─────────────────────────────────────┐
# │ Customer Support                    │
# │   Customer Support - Tier 1         │
# │   Customer Support - Technical      │
# │ Development                         │
# │   Code Review Assistant             │
# │   Bug Triage Assistant              │
# │ Content                             │
# │   Blog Post Writer                  │
# │   Social Media Manager              │
# │ Analytics                           │
# │   Data Analysis Assistant           │
# │   Report Generator                  │
# └─────────────────────────────────────┘

# ============================================================================
# Backend Implementation Notes
# ============================================================================

# In your LLM caller service, detect the provider:
#
# if provider.to_s == 'openai_assistants'
#   # Use OpenAI Assistants API
#   # 1. Create thread
#   # 2. Add message
#   # 3. Run assistant
#   # 4. Wait for completion
#   # 5. Retrieve response
# else
#   # Use standard Chat Completions API via ruby_llm gem
# end
