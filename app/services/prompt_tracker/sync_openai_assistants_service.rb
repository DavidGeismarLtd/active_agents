# frozen_string_literal: true

module PromptTracker
  # Service for syncing all OpenAI Assistants from the API.
  #
  # Fetches all assistants from OpenAI API and creates or updates them
  # in the local database.
  #
  # @example Sync all assistants
  #   result = SyncOpenaiAssistantsService.call
  #   result[:created]  # => 5
  #   result[:updated]  # => 3
  #   result[:total]    # => 8
  #
  class SyncOpenaiAssistantsService
    class SyncError < StandardError; end

    # Sync all assistants from OpenAI API
    #
    # @return [Hash] result with :created, :updated, :total, :assistants keys
    # @raise [SyncError] if API call fails
    def self.call
      new.call
    end

    attr_reader :client, :created_count, :updated_count

    def initialize
      @client = build_client
      @created_count = 0
      @updated_count = 0
    end

    # Execute the sync
    #
    # @return [Hash] result with :created, :updated, :total, :assistants keys
    def call
      assistants_data = fetch_all_assistants
      synced_assistants = sync_assistants(assistants_data)

      {
        created: created_count,
        updated: updated_count,
        total: synced_assistants.count,
        assistants: synced_assistants
      }
    end

    private

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    def build_client
      require "openai"

      # Try OPENAI_LOUNA_API_KEY first (used in existing code), fallback to OPENAI_API_KEY
      api_key = ENV["OPENAI_LOUNA_API_KEY"] || ENV["OPENAI_API_KEY"]
      raise SyncError, "OPENAI_LOUNA_API_KEY or OPENAI_API_KEY environment variable not set" if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end

    # Fetch all assistants from OpenAI API
    #
    # @return [Array<Hash>] array of assistant data from API
    def fetch_all_assistants
      response = client.assistants.list
      response["data"] || []
    rescue => e
      raise SyncError, "Failed to fetch assistants from OpenAI: #{e.message}"
    end

    # Sync assistants to database
    #
    # @param assistants_data [Array<Hash>] array of assistant data from API
    # @return [Array<PromptTracker::Openai::Assistant>] synced assistants
    def sync_assistants(assistants_data)
      assistants_data.map do |assistant_data|
        sync_assistant(assistant_data)
      end.compact
    end

    # Sync a single assistant
    #
    # @param assistant_data [Hash] assistant data from API
    # @return [PromptTracker::Openai::Assistant] the synced assistant
    def sync_assistant(assistant_data)
      assistant_id = assistant_data["id"]
      return nil if assistant_id.blank?

      assistant = PromptTracker::Openai::Assistant.find_or_initialize_by(assistant_id: assistant_id)

      if assistant.new_record?
        @created_count += 1
      else
        @updated_count += 1
      end

      # Skip the fetch_from_openai callback since we already have the data
      assistant.skip_fetch_from_openai = true

      assistant.assign_attributes(
        name: assistant_data["name"] || assistant_id,
        description: assistant_data["description"],
        metadata: {
          instructions: assistant_data["instructions"],
          model: assistant_data["model"],
          tools: assistant_data["tools"] || [],
          file_ids: assistant_data["file_ids"] || [],
          temperature: assistant_data["temperature"],
          top_p: assistant_data["top_p"],
          response_format: assistant_data["response_format"],
          tool_resources: assistant_data["tool_resources"] || {},
          last_synced_at: Time.current.iso8601
        }
      )

      assistant.save!
      assistant
    rescue => e
      Rails.logger.error "Failed to sync assistant #{assistant_id}: #{e.message}"
      nil
    end
  end
end
