# frozen_string_literal: true

module PromptTracker
  module Openai
    module Assistants
      # Normalizes OpenAI Assistants API data into PromptTracker's internal model_config format
      #
      # The OpenAI Assistants API returns tools as an array of hashes:
      #   [{"type"=>"file_search", "file_search"=>{...}}, {"type"=>"code_interpreter"}]
      #
      # We normalize this to a simple string array:
      #   ["file_search", "code_interpreter"]
      #
      # Tool-specific configuration is stored in TWO places:
      # - tool_resources: Original OpenAI format (preserved for API calls)
      # - tool_config: Unified format for UI consistency (extracted from tool_resources)
      #
      # @example
      #   assistant_data = {
      #     "id" => "asst_abc123",
      #     "model" => "gpt-4o",
      #     "tools" => [{"type" => "file_search", "file_search" => {...}}],
      #     "tool_resources" => {"file_search" => {"vector_store_ids" => ["vs_123"]}}
      #   }
      #
      #   config = ModelConfigNormalizer.normalize(assistant_data)
      #   # => {
      #   #   provider: "openai",
      #   #   api: "assistants",
      #   #   assistant_id: "asst_abc123",
      #   #   model: "gpt-4o",
      #   #   tools: ["file_search"],  # ← normalized to string array
      #   #   tool_config: {"file_search" => {"vector_store_ids" => ["vs_123"]}},  # ← unified UI format
      #   #   tool_resources: {"file_search" => {"vector_store_ids" => ["vs_123"]}},  # ← original API format
      #   #   ...
      #   # }
      #
      class ModelConfigNormalizer
        # Normalize OpenAI assistant data to PromptTracker model_config format
        #
        # @param assistant_data [Hash] raw assistant data from OpenAI API
        # @return [Hash] normalized model_config hash
        def self.normalize(assistant_data)
          new(assistant_data).normalize
        end

        def initialize(assistant_data)
          @assistant_data = assistant_data
        end

        # Normalize the assistant data
        #
        # @return [Hash] normalized model_config
        def normalize
          {
            provider: "openai",
            api: "assistants",
            assistant_id: assistant_data["id"],
            model: assistant_data["model"],
            temperature: assistant_data["temperature"] || 0.7,
            top_p: assistant_data["top_p"] || 1.0,
            tools: normalize_tools,
            tool_config: normalize_tool_config,
            tool_resources: assistant_data["tool_resources"] || {},
            metadata: build_metadata
          }
        end

        private

        attr_reader :assistant_data

        # Normalize tools from OpenAI hash format to string array
        #
        # OpenAI format: [{"type"=>"file_search", "file_search"=>{...}}, {"type"=>"code_interpreter"}]
        # Our format: ["file_search", "code_interpreter"]
        #
        # @return [Array<String>] array of tool type strings
        def normalize_tools
          raw_tools = assistant_data["tools"] || []

          raw_tools.map do |tool|
            # Extract type from hash or use string directly
            tool.is_a?(Hash) ? tool["type"] : tool.to_s
          end.compact.select(&:present?)
        end

        # Normalize tool_resources to unified tool_config format
        #
        # Converts Assistants API tool_resources structure to the same format
        # used by Responses API (tool_config) for UI consistency.
        #
        # For file_search, fetches vector store names from OpenAI API and stores
        # both IDs and full objects with names for UI display.
        #
        # @return [Hash] unified tool_config hash
        def normalize_tool_config
          tool_resources = assistant_data["tool_resources"] || {}
          config = {}

          # Extract file_search configuration
          if tool_resources.dig("file_search", "vector_store_ids")
            vector_store_ids = tool_resources["file_search"]["vector_store_ids"]

            # Fetch vector store details (with names) from OpenAI API
            vector_stores = fetch_vector_store_details(vector_store_ids)

            config["file_search"] = {
              "vector_store_ids" => vector_store_ids,  # Keep for backward compatibility
              "vector_stores" => vector_stores  # New format with names for UI
            }
          end

          # Extract code_interpreter configuration (if any exists in future)
          # Currently code_interpreter doesn't have configuration in tool_resources

          config
        end

        # Fetch vector store details from OpenAI API
        #
        # @param vector_store_ids [Array<String>] array of vector store IDs
        # @return [Array<Hash>] array of {id, name} hashes
        def fetch_vector_store_details(vector_store_ids)
          return [] if vector_store_ids.blank?

          vector_store_ids.map do |vs_id|
            # Try to fetch the vector store name from OpenAI API
            begin
              vs_data = openai_client.vector_stores.retrieve(id: vs_id)
              {
                "id" => vs_id,
                "name" => vs_data["name"] || vs_id
              }
            rescue StandardError => e
              # If fetch fails, fall back to using ID as name
              Rails.logger.warn("Failed to fetch vector store #{vs_id}: #{e.message}")
              {
                "id" => vs_id,
                "name" => vs_id
              }
            end
          end
        end

        # Build OpenAI client for fetching vector store details
        #
        # @return [OpenAI::Client] configured client
        def openai_client
          @openai_client ||= begin
            require "openai"

            api_key = PromptTracker.configuration.api_key_for(:openai) ||
                      ENV["OPENAI_API_KEY"]

            raise "OpenAI API key not configured" if api_key.blank?

            OpenAI::Client.new(access_token: api_key)
          end
        end

        # Build metadata hash with assistant info
        #
        # @return [Hash] metadata hash
        def build_metadata
          {
            name: assistant_data["name"],
            description: assistant_data["description"],
            synced_at: Time.current.iso8601
          }
        end
      end
    end
  end
end
