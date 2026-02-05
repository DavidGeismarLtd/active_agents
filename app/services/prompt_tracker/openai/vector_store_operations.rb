# frozen_string_literal: true

module PromptTracker
  module Openai
    # OpenAI-specific vector store operations.
    #
    # Implements vector store operations for OpenAI's Vector Stores API.
    # Used by VectorStoreService for OpenAI provider.
    #
    # @example List vector stores
    #   Openai::VectorStoreOperations.list_vector_stores
    #   # => [{ id: "vs_123", name: "Docs", status: "completed", ... }]
    #
    class VectorStoreOperations
      class OperationError < StandardError; end

      class << self
        # List all vector stores
        #
        # @return [Array<Hash>] array of vector store hashes
        def list_vector_stores
          response = client.vector_stores.list

          (response["data"] || []).map do |vs|
            {
              id: vs["id"],
              name: vs["name"],
              status: vs["status"],
              file_counts: vs["file_counts"],
              created_at: vs["created_at"] ? Time.at(vs["created_at"]) : nil
            }
          end
        end

        # Create a new vector store
        #
        # @param name [String] vector store name
        # @param file_ids [Array<String>] file IDs to add
        # @return [Hash] created vector store data
        def create_vector_store(name:, file_ids: [])
          params = { name: name }
          params[:file_ids] = file_ids if file_ids.present?

          response = client.vector_stores.create(parameters: params)

          {
            id: response["id"],
            name: response["name"],
            status: response["status"],
            file_counts: response["file_counts"],
            created_at: response["created_at"] ? Time.at(response["created_at"]) : nil
          }
        end

        # List files in a vector store
        #
        # @param vector_store_id [String] the vector store ID
        # @return [Array<Hash>] array of file hashes
        def list_vector_store_files(vector_store_id:)
          response = client.vector_store_files.list(vector_store_id: vector_store_id)

          (response["data"] || []).map do |vsf|
            # Get file details to include filename (cached to avoid N+1 API calls)
            file_details = Rails.cache.fetch("openai_file_#{vsf['id']}", expires_in: 1.hour) do
              client.files.retrieve(id: vsf["id"])
            end

            {
              id: vsf["id"],
              vector_store_id: vsf["vector_store_id"],
              status: vsf["status"],
              filename: file_details["filename"],
              bytes: file_details["bytes"],
              created_at: vsf["created_at"] ? Time.at(vsf["created_at"]) : nil
            }
          end
        end

        # Add a file to a vector store
        #
        # @param vector_store_id [String] the vector store ID
        # @param file_id [String] the file ID to add
        # @return [Hash] result
        def add_file_to_vector_store(vector_store_id:, file_id:)
          response = client.vector_store_files.create(
            vector_store_id: vector_store_id,
            parameters: { file_id: file_id }
          )

          {
            id: response["id"],
            vector_store_id: response["vector_store_id"],
            status: response["status"],
            created_at: response["created_at"] ? Time.at(response["created_at"]) : nil
          }
        end

        # Get vector store file status
        #
        # @param vector_store_id [String] the vector store ID
        # @param file_id [String] the file ID
        # @return [Hash] status information
        def get_vector_store_file_status(vector_store_id:, file_id:)
          response = client.vector_store_files.retrieve(
            vector_store_id: vector_store_id,
            id: file_id
          )

          {
            status: response["status"],
            id: response["id"],
            vector_store_id: response["vector_store_id"],
            last_error: response["last_error"]
          }
        end

        private

        # Build OpenAI client
        #
        # @return [OpenAI::Client] configured client
        # @raise [OperationError] if API key is not configured
        def client
          @client ||= begin
            require "openai"

            api_key = PromptTracker.configuration.api_key_for(:openai) ||
                      ENV["OPENAI_API_KEY"]

            raise OperationError, "OpenAI API key not configured" if api_key.blank?

            OpenAI::Client.new(access_token: api_key)
          end
        end
      end
    end
  end
end
