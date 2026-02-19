# frozen_string_literal: true

# PromptTracker Configuration
#
# This file configures PromptTracker settings.
# Structure:
#   1. Core Settings (paths, auth)
#   2. Providers (api_key, name, APIs, models - all in one place)
#   3. Contexts (usage scenarios with defaults)
#   4. Feature Flags
#   5. Tool UI Metadata (optional)

PromptTracker.configure do |config|
  # ===========================================================================
  # 1. CORE SETTINGS
  # ===========================================================================
  config.prompts_path = Rails.root.join("app", "prompts")
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # ===========================================================================
  # 2. PROVIDERS
  # ===========================================================================
  # Each provider contains: api_key, display name, available APIs, and models.
  # A provider is only enabled if api_key is present.
  # Tool capabilities are defined in ApiCapabilities, not here.
  config.providers = {
    openai: {
      api_key: ENV["OPENAI_LOUNA_API_KEY"],
      name: "OpenAI",
      apis: {
        chat_completions: { name: "Chat Completions", description: "Standard chat API with messages", default: true },
        responses: { name: "Responses", description: "Stateful conversations with built-in tools" },
        assistants: { name: "Assistants", description: "Full assistant features with threads and runs" }
      },
      models: [
        { id: "gpt-5.2", name: "GPT-5 (Aug 2025)", category: "Latest",
          capabilities: [ :chat, :structured_output, :vision, :function_calling, :reasoning ],
          supported_apis: [ :chat_completions, :responses ] },
        { id: "gpt-4.1", name: "GPT-4.1 (Aug 2025)", category: "Latest",
          capabilities: [ :chat, :structured_output, :vision, :function_calling, :reasoning ],
          supported_apis: [ :chat_completions, :responses ] },
        { id: "gpt-4o", name: "GPT-4o", category: "Latest",
          capabilities: [ :chat, :structured_output, :vision, :function_calling ],
          supported_apis: [ :chat_completions, :responses, :assistants ] },
        { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest",
          capabilities: [ :chat, :structured_output, :vision, :function_calling ],
          supported_apis: [ :chat_completions, :responses, :assistants ] },
        { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4",
          capabilities: [ :chat, :vision, :function_calling ],
          supported_apis: [ :chat_completions, :responses, :assistants ] },
        { id: "gpt-4", name: "GPT-4", category: "GPT-4",
          capabilities: [ :chat, :function_calling ],
          supported_apis: [ :chat_completions, :assistants ] },
        { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5",
          capabilities: [ :chat, :function_calling ],
          supported_apis: [ :chat_completions, :assistants ] }
      ]
    },

    anthropic: {
      api_key: ENV["ANTHROPIC_API_KEY"],
      name: "Anthropic",
      apis: {
        messages: { name: "Messages", description: "Claude chat API", default: true }
      },
      models: [
        { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5",
          capabilities: [ :chat, :structured_output, :function_calling ] },
        { id: "claude-opus-4-1", name: "Claude Opus 4.1",
          capabilities: [ :chat, :structured_output, :function_calling ] },
        { id: "claude-haiku-4-5", name: "Claude Haiku 4.5",
          capabilities: [ :chat, :structured_output, :function_calling ] },
        { id: "claude-3-7-sonnet-latest", name: "Claude Sonnet 3.7",
          capabilities: [ :chat, :structured_output, :function_calling ] },
        { id: "claude-3-5-haiku-latest", name: "Claude 3.5 Haiku",
          capabilities: [ :chat, :structured_output, :function_calling ] }
      ]
    }
  }

  # ===========================================================================
  # 3. CONTEXTS
  # ===========================================================================
  # Usage scenarios with their default selections.
  # Each context specifies which provider/api/model to use by default.
  config.contexts = {
    playground: {
      description: "Prompt version testing in the playground",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    llm_judge: {
      description: "LLM-as-judge evaluation of responses",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    dataset_generation: {
      description: "Generating test dataset rows via LLM",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    prompt_generation: {
      description: "AI-assisted prompt creation and enhancement",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o-mini"
    }
  }

  # ===========================================================================
  # 4. FEATURE FLAGS
  # ===========================================================================
  config.features = {
    openai_assistant_sync: true  # Show "Sync OpenAI Assistants" button in Testing Dashboard
  }

  # ===========================================================================
  # 5. TOOL UI METADATA (Optional - defaults provided by engine)
  # ===========================================================================
  # Customize the display metadata for built-in API tools.
  # Uncomment and modify to customize:
  #
  # config.builtin_tools = {
  #   web_search: { name: "Web Search", description: "Search the web", icon: "bi-globe" },
  #   file_search: { name: "File Search", description: "Search files", icon: "bi-file-earmark-search" },
  #   code_interpreter: { name: "Code Interpreter", description: "Execute Python code", icon: "bi-code-slash" }
  # }
end
