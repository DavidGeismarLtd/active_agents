# frozen_string_literal: true

# PromptTracker Configuration
#
# This file is used to configure PromptTracker settings.

PromptTracker.configure do |config|
  # ===========================================================================
  # Path Configuration
  # ===========================================================================
  config.prompts_path = Rails.root.join("app", "prompts")

  # ===========================================================================
  # Authentication
  # ===========================================================================
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # ===========================================================================
  # API Keys (per provider, not per API)
  # ===========================================================================
  # A provider is only available if its key is set.
  config.api_keys = {
    openai: ENV["OPENAI_API_KEY"],
    anthropic: ENV["ANTHROPIC_API_KEY"]
  }

  # ===========================================================================
  # Providers and Their APIs
  # ===========================================================================
  # Define providers and the APIs they offer.
  config.providers = {
    openai: {
      name: "OpenAI",
      apis: {
        chat_completions: {
          name: "Chat Completions",
          description: "Standard chat API with messages",
          default: true
        },
        responses: {
          name: "Responses",
          description: "Stateful conversations with built-in tools",
          capabilities: [ :web_search, :file_search, :code_interpreter, :functions ]
        },
        assistants: {
          name: "Assistants",
          description: "Full assistant features with threads and runs"
        }
      }
    },
    anthropic: {
      name: "Anthropic",
      apis: {
        messages: {
          name: "Messages",
          description: "Claude chat API",
          default: true
        }
      }
    },
    google: {
      name: "Google",
      apis: {
        gemini: {
          name: "Gemini",
          description: "Google Gemini API",
          default: true
        }
      }
    }
  }

  # ===========================================================================
  # Master Model Registry
  # ===========================================================================
  # All available models in the system. Each model can have capabilities.
  # supported_apis: Array of API keys this model works with (nil = all)
  config.models = {
    openai: [
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
    ],
    anthropic: [
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5",
        capabilities: [ :chat, :structured_output, :vision ] },
      { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", category: "Claude 3.5",
        capabilities: [ :chat, :structured_output ] },
      { id: "claude-3-opus-20240229", name: "Claude 3 Opus", category: "Claude 3",
        capabilities: [ :chat, :vision ] },
      { id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", category: "Claude 3",
        capabilities: [ :chat ] },
      { id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", category: "Claude 3",
        capabilities: [ :chat ] }
    ]
  }

  # ===========================================================================
  # OpenAI Assistants Configuration (separate API key, optional)
  # ===========================================================================
  config.openai_assistants = {
    api_key: ENV["OPENAI_LOUNA_API_KEY"],
    available_models: [
      { id: "gpt-4o", name: "GPT-4o" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini" },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo" },
      { id: "gpt-4", name: "GPT-4" },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo" }
    ]
  }

  # ===========================================================================
  # Context-Specific Model Restrictions
  # ===========================================================================
  config.contexts = {
    # Playground: prompt version testing - all models allowed
    playground: {
      providers: nil,
      models: nil,
      require_capability: nil
    },

    # LLM Judge: evaluating responses - needs structured output
    llm_judge: {
      providers: [ :openai, :anthropic ],
      models: nil,
      require_capability: :structured_output
    },

    # Dataset Generation: generating test data rows
    dataset_generation: {
      providers: [ :openai ],
      models: nil,
      require_capability: :structured_output
    },

    # Prompt Generation: AI-assisted prompt creation
    prompt_generation: {
      providers: [ :openai ],
      models: [ "gpt-4o-mini" ],
      require_capability: nil
    }
  }

  # ===========================================================================
  # Default Selections
  # ===========================================================================
  config.defaults = {
    playground_provider: :openai,
    playground_api: :chat_completions,
    playground_model: "gpt-4o",
    llm_judge_model: "gpt-4o",
    dataset_generation_model: "gpt-4o",
    prompt_generation_model: "gpt-4o-mini"
  }

  # ===========================================================================
  # Built-in Tools (Optional - defaults are provided)
  # ===========================================================================
  # Customize the display metadata for built-in API tools.
  # These are used by Response API and Assistants API.
  # Uncomment and modify to customize:
  #
  # config.builtin_tools = {
  #   web_search: {
  #     name: "Web Search",
  #     description: "Search the web for current information",
  #     icon: "bi-globe"
  #   },
  #   file_search: {
  #     name: "File Search",
  #     description: "Search through uploaded files",
  #     icon: "bi-file-earmark-search"
  #   },
  #   code_interpreter: {
  #     name: "Code Interpreter",
  #     description: "Execute Python code for analysis",
  #     icon: "bi-code-slash"
  #   }
  # }
end
