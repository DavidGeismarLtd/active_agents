# frozen_string_literal: true

module PromptTracker
  # Provider-agnostic service for vector store operations.
  #
  # Routes vector store operations to provider-specific implementations.
  # Currently supports OpenAI, but designed to support other providers in the future.
  #
  # This service decouples vector store operations from specific contexts
  # (like AssistantPlaygroundService) so they can be used from:
  # - Response API (file_search tool)
  # - Assistants API (tool_resources.file_search)
  # - Generic Playground
  # - Any other context that needs vector stores
  #
  # @example List vector stores
  #   VectorStoreService.list_vector_stores(provider: :openai)
  #   # => [{ id: "vs_123", name: "Docs", ... }]
  #
  # @example Create vector store
  #   VectorStoreService.create_vector_store(
  #     provider: :openai,
  #     name: "Customer Support Docs",
  #     file_ids: ["file_abc123"]
  #   )
  #
  class VectorStoreService
    class VectorStoreError < StandardError; end

    class << self
      # List all vector stores for a provider
      #
      # @param provider [Symbol] the provider (:openai, etc.)
      # @return [Array<Hash>] array of vector store hashes
      def list_vector_stores(provider:)
        operations_class = operations_class_for(provider)
        operations_class.list_vector_stores
      end

      # Create a new vector store
      #
      # @param provider [Symbol] the provider
      # @param name [String] vector store name
      # @param file_ids [Array<String>] file IDs to add
      # @return [Hash] created vector store data
      def create_vector_store(provider:, name:, file_ids: [])
        operations_class = operations_class_for(provider)
        operations_class.create_vector_store(name: name, file_ids: file_ids)
      end

      # List files in a vector store
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @return [Array<Hash>] array of file hashes
      def list_vector_store_files(provider:, vector_store_id:)
        operations_class = operations_class_for(provider)
        operations_class.list_vector_store_files(vector_store_id: vector_store_id)
      end

      # Add a file to a vector store
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @param file_id [String] the file ID to add
      # @return [Hash] result
      def add_file_to_vector_store(provider:, vector_store_id:, file_id:)
        operations_class = operations_class_for(provider)
        operations_class.add_file_to_vector_store(
          vector_store_id: vector_store_id,
          file_id: file_id
        )
      end

      # Get vector store file status
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @param file_id [String] the file ID
      # @return [Hash] status information
      def get_vector_store_file_status(provider:, vector_store_id:, file_id:)
        operations_class = operations_class_for(provider)
        operations_class.get_vector_store_file_status(
          vector_store_id: vector_store_id,
          file_id: file_id
        )
      end

      private

      # Get the operations class for a provider
      #
      # @param provider [Symbol] the provider
      # @return [Class] the operations class
      # @raise [VectorStoreError] if provider is not supported
      def operations_class_for(provider)
        case provider.to_sym
        when :openai
          Openai::VectorStoreOperations
        else
          raise VectorStoreError, "Unsupported provider: #{provider}"
        end
      end
    end
  end
end
