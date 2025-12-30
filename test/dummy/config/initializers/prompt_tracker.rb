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
  # API Keys
  # ===========================================================================
  # Direct API key configuration. A provider is only available if its key is set.
  config.api_keys = {
    openai: ENV["OPENAI_API_KEY"],
    anthropic: ENV["ANTHROPIC_API_KEY"],
    google: ENV["GOOGLE_API_KEY"]
  }

  # ===========================================================================
  # Master Model Registry
  # ===========================================================================
  # All available models in the system. Each model can have capabilities.
  config.models = {
    openai: [
      { id: "gpt-4o", name: "GPT-4o", category: "Latest",
        capabilities: [ :chat, :structured_output, :vision, :function_calling ] },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest",
        capabilities: [ :chat, :structured_output, :vision, :function_calling ] },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4",
        capabilities: [ :chat, :vision, :function_calling ] },
      { id: "gpt-4", name: "GPT-4", category: "GPT-4",
        capabilities: [ :chat, :function_calling ] },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5",
        capabilities: [ :chat, :function_calling ] }
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
  # OpenAI Assistants Configuration (separate from chat completions)
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
  # Default Models
  # ===========================================================================
  config.defaults = {
    playground_provider: :openai,
    playground_model: "gpt-4o",
    llm_judge_model: "gpt-4o",
    dataset_generation_model: "gpt-4o",
    prompt_generation_model: "gpt-4o-mini"
  }
end
