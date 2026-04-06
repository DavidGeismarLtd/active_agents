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
    openai: { api_key: ENV["OPENAI_LOUNA_API_KEY"] },
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
    },
    test_generation: {
      description: "AI-powered test case generation for prompts",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o",
      default_temperature: 0.7
    },
    interlocutor_simulation: {
      description: "Simulating user responses in multi-turn conversations",
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o-mini",
      default_temperature: 0.7
    }
  }

  # ===========================================================================
  # 3b. VECTOR DATABASES (External RAG)
  # ===========================================================================
  # When configured, any LLM provider (Anthropic, Google, etc.) can use RAG.
  # If empty, only OpenAI's native file search is available.
  config.vector_databases = {
    pinecone: {
      api_key:            ENV["PINECONE_API_KEY"],
      index_name:         ENV.fetch("PINECONE_INDEX_NAME", "prompt-tracker"),
      region:             ENV.fetch("PINECONE_REGION", "us-east-1"),
      embedding_provider: :openai,
      embedding_model:    "text-embedding-3-small"
    }
  }

  # ===========================================================================
  # 4. FUNCTION EXECUTION PROVIDERS
  # ===========================================================================
  # Similar to LLM providers, but for code execution backends.
  # A provider is only enabled if all required credentials are present.
  # See docs/aws_lambda_setup.md for AWS Lambda setup instructions.
  config.function_providers = {
    aws_lambda: {
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      execution_role_arn: ENV["LAMBDA_EXECUTION_ROLE_ARN"],
      function_prefix: ENV.fetch("LAMBDA_FUNCTION_PREFIX", "prompt-tracker")
    }
    # Future providers can be added here:
    # google_cloud_functions: { ... },
    # local_docker: { ... }
  }

  # ===========================================================================
  # 5. FEATURE FLAGS
  # ===========================================================================
  config.features = {
    monitoring: true,            # Enable the Monitoring section (tracked calls, auto-evaluations)
    openai_assistant_sync: true, # Show "Sync OpenAI Assistants" button in Testing Dashboard
    functions: true             # Enable the Functions section (code-based agent functions) - requires AWS Lambda config
  }

  # ===========================================================================
  # 6. ASSISTANT CHATBOT
  # ===========================================================================
  config.assistant_chatbot = {
    enabled: true,
    model: {
      provider: :openai,
      api: :chat_completions,
      model: "gpt-4o",
      temperature: 0.7
    },
    ui: {
      name: "PromptTracker Assistant",
      position: :bottom_right,
      theme: :auto
    },
    conversation: {
      max_messages: 50,
      ttl: 3600,
      storage: :session
    },
    capabilities: {
      create_prompts: true,
      generate_tests: true,
      run_tests: true,
      get_info: true,
      search: true
    },
    security: {
      rate_limit: 60,
      require_auth: false,
      audit_enabled: true
    }
  }
end
