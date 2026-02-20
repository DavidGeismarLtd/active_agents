# frozen_string_literal: true

# PromptTracker Configuration
#
# This file configures PromptTracker settings.
#
# Structure:
#   1. Core Settings (auth)
#   2. Providers (minimal: just api_key; RubyLLM provides models)
#   3. Contexts (usage scenarios with defaults)
#   4. Feature Flags

PromptTracker.configure do |config|
  # ===========================================================================
  # 1. CORE SETTINGS
  # ===========================================================================
  config.basic_auth_username = nil
  config.basic_auth_password = nil

  # ===========================================================================
  # 2. PROVIDERS
  # ===========================================================================
  # Minimal config: just API keys!
  # - Provider names default from ProviderDefaults (e.g., "OpenAI", "Anthropic")
  # - APIs default from ProviderDefaults (e.g., chat_completions, messages)
  # - Models auto-populate from RubyLLM's model registry (always up-to-date)
  #
  # A provider is only enabled if api_key is present.
  config.providers = {
    openai: { api_key: ENV["OPENAI_API_KEY"] },
    anthropic: { api_key: ENV["ANTHROPIC_API_KEY"] },
    google: { api_key: ENV["GOOGLE_API_KEY"] }
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
end
