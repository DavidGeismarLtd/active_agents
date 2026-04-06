# frozen_string_literal: true

module PromptTracker
  module Api
    # API controller for vector stores.
    #
    # All endpoints accept an optional `provider` param (default: "openai").
    # When provider is "openai" the existing OpenAI-managed flow is used unchanged.
    # When provider is an external vector DB (e.g. "pinecone") the request is
    # routed to the corresponding VectorStoreOperations class.
    class VectorStoresController < ApplicationController
      # GET /prompt_tracker/api/vector_stores?provider=openai
      # GET /prompt_tracker/api/vector_stores?provider=pinecone
      def index
        provider     = params.fetch(:provider, "openai").to_sym
        vector_stores = if provider == :openai
          fetch_openai_vector_stores
        else
          VectorStoreService.list_vector_stores(provider: provider)
        end

        render json: { vector_stores: vector_stores, provider: provider }
      end

      # POST /prompt_tracker/api/vector_stores
      # Body params: name, files[], provider (default: "openai")
      def create
        name     = params[:name]
        files    = params[:files]
        provider = params.fetch(:provider, "openai").to_sym

        if name.blank?
          render json: { error: "Name is required" }, status: :unprocessable_entity
          return
        end

        if files.blank?
          render json: { error: "At least one file is required" }, status: :unprocessable_entity
          return
        end

        result = if provider == :openai
          create_openai_vector_store(name, files)
        else
          create_external_vector_store(provider, name, files)
        end

        render json: result, status: :created
      end

      # GET /prompt_tracker/api/vector_stores/:id/files?provider=openai
      def files
        vector_store_id = params[:id]
        provider        = params.fetch(:provider, "openai").to_sym

        if vector_store_id.blank?
          render json: { error: "Vector store ID is required" }, status: :unprocessable_entity
          return
        end

        files = VectorStoreService.list_vector_store_files(
          provider:        provider,
          vector_store_id: vector_store_id
        )

        render json: { files: files }
      rescue StandardError => e
        Rails.logger.error("[VectorStoresController] Failed to fetch files: #{e.message}")
        render json: { files: [] }
      end

      private

      # -----------------------------------------------------------------------
      # OpenAI path (unchanged from original)
      # -----------------------------------------------------------------------

      def openai_client
        api_key = PromptTracker.configuration.api_key_for(:openai)
        raise "OpenAI API key not configured" unless api_key.present?

        OpenAI::Client.new(access_token: api_key)
      end

      def fetch_openai_vector_stores
        client   = openai_client
        response = client.vector_stores.list

        (response["data"] || []).map do |store|
          {
            id:          store["id"],
            name:        store["name"] || store["id"],
            file_counts: store["file_counts"],
            created_at:  store["created_at"]
          }
        end
      rescue StandardError => e
        Rails.logger.error("[VectorStoresController] Failed to fetch OpenAI vector stores: #{e.message}")
        []
      end

      def create_openai_vector_store(name, uploaded_files)
        client   = openai_client
        file_ids = upload_files_to_openai(client, uploaded_files)

        vector_store = client.vector_stores.create(parameters: { name: name })

        file_ids.each do |file_id|
          client.vector_store_files.create(
            vector_store_id: vector_store["id"],
            parameters: { file_id: file_id }
          )
        end

        {
          id:         vector_store["id"],
          name:       vector_store["name"],
          provider:   "openai",
          file_count: file_ids.size
        }
      end

      def upload_files_to_openai(client, uploaded_files)
        Array(uploaded_files).map do |file|
          response = client.files.upload(
            parameters: { file: file.tempfile, purpose: "assistants" }
          )
          response["id"]
        end
      end

      # -----------------------------------------------------------------------
      # External vector DB path (Pinecone, future Qdrant, etc.)
      # -----------------------------------------------------------------------

      def create_external_vector_store(provider, name, uploaded_files)
        ops = VectorStoreService.operations_class_for(provider)
        ops.create_vector_store(name: name)

        cfg          = PromptTracker.configuration.vector_databases[provider]
        emb_provider = cfg[:embedding_provider] || :openai
        emb_model    = cfg[:embedding_model]    || "text-embedding-3-small"

        Array(uploaded_files).each do |file|
          chunks  = DocumentChunker.chunk(file)
          vectors = chunks.map { |c| EmbeddingService.embed(c[:text], provider: emb_provider, model: emb_model) }
          ops.upsert_chunks(namespace: name, chunks: chunks, vectors: vectors, filename: file.original_filename)
        end

        { id: name, name: name, provider: provider.to_s }
      end
    end
  end
end
