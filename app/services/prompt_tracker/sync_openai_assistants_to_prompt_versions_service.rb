# frozen_string_literal: true

module PromptTracker
  # Service to sync OpenAI Assistants to Prompts and PromptVersions.
  #
  # Fetches assistants from OpenAI API and creates:
  # - One Prompt per assistant (with slug based on assistant_id)
  # - One PromptVersion per prompt (version_number: 1)
  # - model_config[:api] = "assistants"
  # - model_config[:assistant_id] = "asst_abc123" (NEW field)
  # - model_config[:model] = "gpt-4o" (actual model name)
  #
  # This creates a 1:1:1 relationship: Assistant → Prompt → PromptVersion
  #
  # Delegates to RemoteEntity::Openai::Assistants::CreateAsPromptVersionService
  # for the actual creation of each Prompt and PromptVersion.
  #
  # @example Sync all assistants
  #   result = SyncOpenaiAssistantsToPromptVersionsService.new.call
  #   result[:created_count]  # => 5
  #   result[:created_prompts]  # => [Prompt, ...]
  #   result[:created_versions]  # => [PromptVersion, ...]
  #
  class SyncOpenaiAssistantsToPromptVersionsService
    class SyncError < StandardError; end

    attr_reader :created_prompts, :created_versions, :errors

    # Initialize the service
    def initialize
      @created_prompts = []
      @created_versions = []
      @errors = []
    end

    # Execute the sync
    #
    # @return [Hash] result with :success, :created_count, :created_prompts, :created_versions, :errors keys
    def call
      fetch_assistants_from_openai.each do |assistant_data|
        create_prompt_and_version_from_assistant(assistant_data)
      end

      {
        success: errors.empty?,
        created_count: created_prompts.count,
        created_prompts: created_prompts,
        created_versions: created_versions,
        errors: errors
      }
    end

    private

    # Fetch all assistants from OpenAI API
    #
    # @return [Array<Hash>] array of assistant data from API
    # @raise [SyncError] if client cannot be built (API key missing)
    def fetch_assistants_from_openai
      client = build_client  # This will raise SyncError if API key is missing
      response = client.assistants.list

      response["data"] || []
    rescue SyncError
      # Re-raise SyncError (API key not configured)
      raise
    rescue StandardError => e
      # Catch other errors and add to errors array
      @errors << "Failed to fetch assistants: #{e.message}"
      []
    end

    # Create a Prompt and PromptVersion from assistant data
    #
    # Delegates to CreateAsPromptVersionService for the actual creation.
    #
    # @param assistant_data [Hash] assistant data from OpenAI API
    def create_prompt_and_version_from_assistant(assistant_data)
      assistant_name = assistant_data["name"].presence || "Assistant #{assistant_data['id']}"

      result = RemoteEntity::Openai::Assistants::CreateAsPromptVersionService.call(
        assistant_data: assistant_data
      )

      if result.success?
        @created_prompts << result.prompt
        @created_versions << result.prompt_version
      else
        @errors << "Failed to create prompt/version for #{assistant_name}: #{result.errors.join(', ')}"
      end
    end

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    # @raise [SyncError] if API key is not configured
    def build_client
      require "openai"

      api_key = PromptTracker.configuration.api_key_for(:openai) ||
                ENV["OPENAI_API_KEY"]
      raise SyncError, "OpenAI API key not configured" if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end
  end
end
