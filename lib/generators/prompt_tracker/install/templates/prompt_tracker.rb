# frozen_string_literal: true

# PromptTracker Configuration
#
# This file configures PromptTracker settings.
# Structure:
#   1. Core Settings (paths, auth, dynamic configuration)
#   2. Providers (api_key, name, APIs, models - all in one place)
#   3. Contexts (usage scenarios with defaults)
#   4. Feature Flags
#   5. Tool UI Metadata (optional)
#
# For multi-tenant applications with per-organization API keys,
# see docs/dynamic_configuration.md for configuration_provider setup.

PromptTracker.configure do |config|
  # ===========================================================================
  # 1. CORE SETTINGS
  # ===========================================================================

  # Path to the directory containing prompt YAML files
  config.prompts_path = Rails.root.join("app", "prompts")

  # Basic Authentication for Web UI
  # If both username and password are set, the web UI will require HTTP Basic Auth.
  # SECURITY: Use environment variables for credentials in production.
  #
  # Example:
  #   config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  #   config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # Dynamic Configuration Provider (for multi-tenant applications)
  # Uncomment to enable per-request configuration based on your app's context.
  # See docs/dynamic_configuration.md for detailed setup guide.
  #
  # config.configuration_provider = -> {
  #   org = Current.organization
  #   return {} unless org
  #
  #   {
  #     providers: {
  #       openai: { api_key: org.openai_api_key },
  #       anthropic: { api_key: org.anthropic_api_key }
  #     }
  #   }
  # }

  # ===========================================================================
  # 2. PROVIDERS
  # ===========================================================================
  # Each provider contains: api_key, display name, available APIs, and models.
  # A provider is only enabled if api_key is present.
  # Tool capabilities are defined in ApiCapabilities (engine), not here.
  config.providers = {
    openai: {
      api_key: ENV["OPENAI_API_KEY"],
      name: "OpenAI",
      apis: {
        chat_completions: { name: "Chat Completions", description: "Standard chat API with messages", default: true },
        responses: { name: "Responses", description: "Stateful conversations with built-in tools" },
        assistants: { name: "Assistants", description: "Full assistant features with threads and runs" }
      },
      models: [
        { id: "gpt-4o", name: "GPT-4o", category: "Latest",
          capabilities: [ :chat, :structured_output, :vision, :function_calling ],
          supported_apis: [ :chat_completions, :responses, :assistants ] },
        { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest",
          capabilities: [ :chat, :structured_output, :function_calling ],
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
        { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet",
          capabilities: [ :chat, :structured_output, :function_calling ] },
        { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku",
          capabilities: [ :chat, :structured_output, :function_calling ] }
      ]
    },

    google: {
      api_key: ENV["GOOGLE_API_KEY"],
      name: "Google",
      apis: {
        gemini: { name: "Gemini", description: "Google Gemini API", default: true }
      },
      models: [
        { id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash (Experimental)", category: "Gemini 2.0",
          capabilities: [ :chat ] },
        { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", category: "Gemini 1.5",
          capabilities: [ :chat ] },
        { id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", category: "Gemini 1.5",
          capabilities: [ :chat ] }
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
    openai_assistant_sync: false  # Show "Sync OpenAI Assistants" button in Testing Dashboard
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
