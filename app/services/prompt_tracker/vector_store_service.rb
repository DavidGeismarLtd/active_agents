# frozen_string_literal: true

module PromptTracker
  # Provider-agnostic service for vector store operations.
  #
  # Routes vector store operations to provider-specific implementations.
  # Supports OpenAI (native file search) and Pinecone (external RAG).
  # Adding Qdrant in the future means adding a `:qdrant` branch in
  # `operations_class_for` and creating `Qdrant::VectorStoreOperations`.
  #
  # @example List vector stores
  #   VectorStoreService.list_vector_stores(provider: :openai)
  #   VectorStoreService.list_vector_stores(provider: :pinecone)
  #
  # @example Query for RAG (external providers only)
  #   VectorStoreService.query(
  #     provider: :pinecone,
  #     vector_store_id: "my-collection",
  #     query_text: "What is the refund policy?"
  #   )
  #
  class VectorStoreService
    class VectorStoreError < StandardError; end

    class << self
      # List all vector stores for a provider.
      #
      # @param provider [Symbol] the provider (:openai, :pinecone)
      # @return [Array<Hash>] array of vector store hashes
      def list_vector_stores(provider:)
        operations_class_for(provider).list_vector_stores
      end

      # Create a new vector store.
      #
      # @param provider [Symbol] the provider
      # @param name [String] vector store name
      # @param file_ids [Array<String>] file IDs to add (OpenAI only)
      # @return [Hash] created vector store data
      def create_vector_store(provider:, name:, file_ids: [])
        operations_class_for(provider).create_vector_store(name: name, file_ids: file_ids)
      end

      # List files in a vector store.
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID / namespace
      # @return [Array<Hash>] array of file hashes
      def list_vector_store_files(provider:, vector_store_id:)
        operations_class_for(provider).list_vector_store_files(vector_store_id: vector_store_id)
      end

      # Add a file to a vector store.
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @param file_id [String] the file ID to add
      # @return [Hash] result
      def add_file_to_vector_store(provider:, vector_store_id:, file_id:)
        operations_class_for(provider).add_file_to_vector_store(
          vector_store_id: vector_store_id,
          file_id: file_id
        )
      end

      # Get vector store file status.
      #
      # @param provider [Symbol] the provider
      # @param vector_store_id [String] the vector store ID
      # @param file_id [String] the file ID
      # @return [Hash] status information
      def get_vector_store_file_status(provider:, vector_store_id:, file_id:)
        operations_class_for(provider).get_vector_store_file_status(
          vector_store_id: vector_store_id,
          file_id: file_id
        )
      end

      # Query a vector store for relevant chunks (external RAG providers only).
      # Used at inference time to inject retrieved context into the system prompt.
      #
      # @param provider [Symbol] the vector DB provider (:pinecone)
      # @param vector_store_id [String] namespace / collection ID
      # @param query_text [String] natural language query
      # @param top_k [Integer] number of results to return
      # @return [Array<Hash>] each with :text, :score, :filename
      def query(provider:, vector_store_id:, query_text:, top_k: 5)
        operations_class_for(provider).query(
          namespace:  vector_store_id,
          query_text: query_text,
          top_k:      top_k
        )
      end

      # Resolve the operations class for a provider.
      # Public so that controllers can use it directly when needed.
      #
      # @param provider [Symbol, String] the provider key
      # @return [Class] the operations class
      # @raise [VectorStoreError] if provider is not supported
      def operations_class_for(provider)
        case provider.to_sym
        when :openai
          Openai::VectorStoreOperations
        when :pinecone
          Pinecone::VectorStoreOperations
        # Phase 2: when :qdrant then Qdrant::VectorStoreOperations
        else
          raise VectorStoreError, "Unsupported vector store provider: #{provider}"
        end
      end
    end
  end
end
