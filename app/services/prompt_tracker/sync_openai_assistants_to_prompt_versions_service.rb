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
    # @param assistant_data [Hash] assistant data from OpenAI API
    def create_prompt_and_version_from_assistant(assistant_data)
      assistant_id = assistant_data["id"]
      # Ensure we always have a valid name (fallback to assistant_id if name is blank)
      assistant_name = assistant_data["name"].presence || "Assistant #{assistant_id}"

      # Create the Prompt
      prompt = Prompt.create!(
        name: assistant_name,
        slug: generate_slug(assistant_id),
        description: assistant_data["description"] || "Synced from OpenAI Assistant",
        category: "assistant"
      )

      # Create the PromptVersion
      version = prompt.prompt_versions.create!(
        system_prompt: assistant_data["instructions"] || "",
        user_prompt: "{{user_message}}",  # Default template for assistant conversations
        version_number: 1,
        status: "draft",
        model_config: build_model_config(assistant_data),
        notes: "Synced from OpenAI Assistant: #{assistant_name}"
      )

      @created_prompts << prompt
      @created_versions << version
    rescue => e
      @errors << "Failed to create prompt/version for #{assistant_name}: #{e.message}"
    end

    # Build model_config hash from assistant data
    #
    # Uses ModelConfigNormalizer to ensure tools are in the correct format
    # (string array instead of OpenAI's hash format)
    #
    # @param assistant_data [Hash] assistant data from OpenAI API
    # @return [Hash] normalized model_config hash
    def build_model_config(assistant_data)
      Openai::Assistants::ModelConfigNormalizer.normalize(assistant_data)
    end

    # Generate a unique slug for the assistant
    #
    # @param assistant_id [String] the OpenAI assistant ID (e.g., "asst_abc123")
    # @return [String] slug for the prompt (e.g., "assistant_asst_abc123")
    def generate_slug(assistant_id)
      # Sanitize assistant_id to ensure it only contains valid characters
      # Replace hyphens with underscores, remove other invalid chars
      sanitized_id = assistant_id.to_s
                                  .downcase
                                  .gsub(/[^a-z0-9_]+/, "_")  # Replace invalid chars with underscore
                                  .gsub(/^_+|_+$/, "")        # Remove leading/trailing underscores
                                  .gsub(/_+/, "_")            # Collapse multiple underscores

      # Use sanitized assistant_id as base for slug
      # "asst_abc123" → "assistant_asst_abc123"
      base_slug = "assistant_#{sanitized_id}"

      # Ensure uniqueness by appending a counter if needed
      slug = base_slug
      counter = 1
      while Prompt.exists?(slug: slug)
        slug = "#{base_slug}_#{counter}"
        counter += 1
      end

      slug
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
