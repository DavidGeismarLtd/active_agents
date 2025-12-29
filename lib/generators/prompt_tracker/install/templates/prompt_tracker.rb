# frozen_string_literal: true

# PromptTracker Configuration
#
# This file is used to configure PromptTracker settings.

PromptTracker.configure do |config|
  # ===========================================================================
  # Basic Settings
  # ===========================================================================

  # Path to the directory containing prompt YAML files
  # Default: Rails.root.join("app", "prompts")
  config.prompts_path = Rails.root.join("app", "prompts")

  # Basic Authentication for Web UI
  # If both username and password are set, the web UI will require
  # HTTP Basic Authentication. If either is nil, the UI is public.
  #
  # SECURITY: It's recommended to use environment variables for credentials
  # and enable basic auth in production to protect sensitive data.
  #
  # Example with environment variables:
  #   config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  #   config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]
  #
  # Default: nil (public access)
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # ===========================================================================
  # API Keys
  # ===========================================================================
  # Direct API key configuration. A provider is only available if its key is set.
  # Use environment variables for security.
  config.api_keys = {
    openai: ENV["OPENAI_API_KEY"],
    anthropic: ENV["ANTHROPIC_API_KEY"],
    google: ENV["GOOGLE_API_KEY"]
  }

  # ===========================================================================
  # Model Registry
  # ===========================================================================
  # Master list of all available models. Each model can have:
  # - id: The actual model ID used in API calls (required)
  # - name: Human-readable name shown in the UI (required)
  # - category: Used to group models in optgroups (optional)
  # - capabilities: Array of capabilities like :chat, :structured_output (optional)
  config.models = {
    openai: [
      { id: "gpt-4o", name: "GPT-4o", category: "Latest", capabilities: [ :chat, :structured_output ] },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", category: "Latest", capabilities: [ :chat, :structured_output ] },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", category: "GPT-4", capabilities: [ :chat, :structured_output ] },
      { id: "gpt-4", name: "GPT-4", category: "GPT-4", capabilities: [ :chat ] },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", category: "GPT-3.5", capabilities: [ :chat ] }
    ],
    anthropic: [
      { id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", category: "Claude 3.5", capabilities: [ :chat, :structured_output ] },
      { id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", category: "Claude 3.5", capabilities: [ :chat, :structured_output ] },
      { id: "claude-3-opus-20240229", name: "Claude 3 Opus", category: "Claude 3", capabilities: [ :chat ] },
      { id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", category: "Claude 3", capabilities: [ :chat ] },
      { id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", category: "Claude 3", capabilities: [ :chat ] }
    ],
    google: [
      { id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash (Experimental)", category: "Gemini 2.0", capabilities: [ :chat ] },
      { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", category: "Gemini 1.5", capabilities: [ :chat ] },
      { id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", category: "Gemini 1.5", capabilities: [ :chat ] }
    ]
  }

  # ===========================================================================
  # Context-Specific Model Restrictions (Optional)
  # ===========================================================================
  # Define which providers/models are available in specific contexts.
  # If not specified, all configured providers/models are available.
  #
  # Options:
  # - providers: Array of allowed provider symbols, or nil for all
  # - models: Array of allowed model IDs, or nil for all
  # - require_capability: Symbol like :structured_output to filter models
  config.contexts = {
    # Playground allows all providers and models
    playground: {
      providers: nil,
      models: nil,
      require_capability: nil
    },
    # LLM Judge requires structured output capability
    llm_judge: {
      providers: nil,
      models: nil,
      require_capability: :structured_output
    },
    # OpenAI Assistant playground is OpenAI-only
    assistant_playground: {
      providers: [ :openai ],
      models: nil,
      require_capability: nil
    }
  }

  # ===========================================================================
  # Default Model Selections
  # ===========================================================================
  # Default models for various contexts. Users can still select different models.
  config.defaults = {
    playground_provider: :openai,
    playground_model: "gpt-4o",
    llm_judge_model: "gpt-4o",
    prompt_generator_model: "gpt-4o-mini",
    dataset_generator_model: "gpt-4o"
  }

  # ===========================================================================
  # OpenAI Assistants Configuration (Optional)
  # ===========================================================================
  # Separate configuration for OpenAI Assistants API.
  # This can use a different API key than the chat completions API.
  # config.openai_assistants = {
  #   api_key: ENV["OPENAI_ASSISTANTS_API_KEY"],
  #   available_models: [
  #     { id: "gpt-4o", name: "GPT-4o" },
  #     { id: "gpt-4-turbo", name: "GPT-4 Turbo" }
  #   ]
  # }
end
