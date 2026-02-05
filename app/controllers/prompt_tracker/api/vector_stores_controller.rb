# frozen_string_literal: true

module PromptTracker
  module Api
    # API controller for vector stores
    # Provides endpoints for listing and creating OpenAI vector stores
    class VectorStoresController < ApplicationController
      # GET /prompt_tracker/api/vector_stores
      # Returns list of available vector stores from OpenAI
      def index
        vector_stores = fetch_vector_stores
        render json: { vector_stores: vector_stores }
      end

      # POST /prompt_tracker/api/vector_stores
      # Creates a new vector store with uploaded files
      def create
        name = params[:name]
        files = params[:files]

        if name.blank?
          render json: { error: "Name is required" }, status: :unprocessable_entity
          return
        end

        if files.blank?
          render json: { error: "At least one file is required" }, status: :unprocessable_entity
          return
        end

        result = create_vector_store_with_files(name, files)
        render json: result, status: :created
      end

      # GET /prompt_tracker/api/vector_stores/:id/files
      # Returns list of files in a specific vector store
      def files
        vector_store_id = params[:id]

        if vector_store_id.blank?
          render json: { error: "Vector store ID is required" }, status: :unprocessable_entity
          return
        end

        files = fetch_vector_store_files(vector_store_id)

        render json: { files: files }
      end

      private

      def openai_client
        api_key = PromptTracker.configuration.api_key_for(:openai)

        raise "OpenAI API key not configured" unless api_key.present?

        OpenAI::Client.new(access_token: api_key)
      end

      def fetch_vector_stores
        client = openai_client
        response = client.vector_stores.list

        (response["data"] || []).map do |store|
          {
            id: store["id"],
            name: store["name"] || store["id"],
            file_counts: store["file_counts"],
            created_at: store["created_at"]
          }
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch vector stores: #{e.message}")
        []
      end

      def create_vector_store_with_files(name, uploaded_files)
        client = openai_client

        # Step 1: Upload files to OpenAI
        file_ids = upload_files(client, uploaded_files)

        # Step 2: Create vector store
        vector_store = client.vector_stores.create(
          parameters: { name: name }
        )

        # Step 3: Add files to vector store
        file_ids.each do |file_id|
          client.vector_store_files.create(
            vector_store_id: vector_store["id"],
            parameters: { file_id: file_id }
          )
        end

        {
          id: vector_store["id"],
          name: vector_store["name"],
          file_count: file_ids.size
        }
      end

      def upload_files(client, uploaded_files)
        Array(uploaded_files).map do |file|
          response = client.files.upload(
            parameters: {
              file: file.tempfile,
              purpose: "assistants"
            }
          )
          response["id"]
        end
      end

      def fetch_vector_store_files(vector_store_id)
        VectorStoreService.list_vector_store_files(
          provider: :openai,
          vector_store_id: vector_store_id
        )
      rescue StandardError => e
        Rails.logger.error("Failed to fetch vector store files: #{e.message}")
        []
      end
    end
  end
end
