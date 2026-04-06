# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PromptTracker
  module Pinecone
    # Pinecone-specific vector store operations using the Pinecone REST API directly.
    #
    # The `pinecone` gem (v0.1.x) targets the legacy pod-based API and doesn't work
    # with Pinecone Serverless. We use the REST API at api.pinecone.io instead.
    #
    # Architecture:
    #   - Control plane (api.pinecone.io): list/create/describe indexes
    #   - Data plane ({index-host}): upsert, query, describe_index_stats
    #
    # One Pinecone index acts as the store; namespaces act as "collections".
    #
    # To add Qdrant in the future, mirror this class under
    # `PromptTracker::Qdrant::VectorStoreOperations` with the same public interface.
    #
    class VectorStoreOperations
      class OperationError < StandardError; end

      CONTROL_PLANE_HOST = "api.pinecone.io"

      class << self
        # List all Pinecone namespaces as "vector stores".
        #
        # @return [Array<Hash>] each with :id, :name, :file_counts, :created_at, :provider
        def list_vector_stores
          host = index_host
          return [] unless host

          stats = data_plane_post(host, "/describe_index_stats", {})
          namespaces = stats["namespaces"] || {}

          namespaces.map do |namespace, data|
            {
              id:          namespace,
              name:        namespace,
              file_counts: { total: data["vectorCount"] || 0 },
              created_at:  nil,
              provider:    "pinecone"
            }
          end
        rescue StandardError => e
          raise OperationError, "Failed to list Pinecone namespaces: #{e.message}"
        end

        # Create a new collection (namespace).
        # Pinecone namespaces are created implicitly on first upsert.
        #
        # @param name [String] namespace / collection name
        # @param file_ids [Array] unused
        # @return [Hash] with :id, :name, :provider
        def create_vector_store(name:, file_ids: [])
          { id: name, name: name, provider: "pinecone" }
        end

        # List files in a namespace.
        # First checks the local cache. If empty, queries Pinecone with a zero
        # vector to extract unique filenames from stored metadata.
        #
        # @param vector_store_id [String] namespace name
        # @return [Array<Hash>]
        def list_vector_store_files(vector_store_id:)
          cached = Rails.cache.read(file_cache_key(vector_store_id))
          return cached if cached.present?

          # Reconstruct from Pinecone metadata by querying with a zero vector
          files = reconstruct_file_list(vector_store_id)
          Rails.cache.write(file_cache_key(vector_store_id), files, expires_in: 1.hour) if files.present?
          files
        end

        # Upsert document chunks into a Pinecone namespace.
        #
        # @param namespace [String] target namespace
        # @param chunks [Array<Hash>] chunks from DocumentChunker
        # @param vectors [Array<Array<Float>>] one embedding vector per chunk
        # @param filename [String] original filename
        def upsert_chunks(namespace:, chunks:, vectors:, filename:)
          host = index_host!

          records = chunks.zip(vectors).map.with_index do |(chunk, vec), i|
            {
              id:       "#{filename}-#{i}",
              values:   vec,
              metadata: chunk[:metadata].merge(text: chunk[:text])
            }
          end

          records.each_slice(100) do |batch|
            data_plane_post(host, "/vectors/upsert", {
              vectors:   batch,
              namespace: namespace
            })
          end

          cache_file(namespace, filename)
        rescue StandardError => e
          raise OperationError, "Failed to upsert chunks to Pinecone: #{e.message}"
        end

        # Query for the most relevant chunks given a query string.
        #
        # @param namespace [String] namespace to search
        # @param query_text [String] natural language query
        # @param top_k [Integer] number of results
        # @return [Array<Hash>] each with :text, :score, :filename
        def query(namespace:, query_text:, top_k: 5)
          cfg          = pinecone_config
          emb_provider = cfg[:embedding_provider] || :openai
          emb_model    = cfg[:embedding_model]    || "text-embedding-3-small"
          query_vector = EmbeddingService.embed(query_text, provider: emb_provider, model: emb_model)

          host   = index_host!
          result = data_plane_post(host, "/query", {
            vector:          query_vector,
            namespace:       namespace,
            topK:            top_k,
            includeMetadata: true
          })

          (result["matches"] || []).map do |match|
            {
              text:     match.dig("metadata", "text"),
              score:    match["score"],
              filename: match.dig("metadata", "filename")
            }
          end
        rescue StandardError => e
          raise OperationError, "Pinecone query failed: #{e.message}"
        end

        def add_file_to_vector_store(vector_store_id:, file_id:)
          raise OperationError, "Use upsert_chunks to add files to a Pinecone collection"
        end

        def get_vector_store_file_status(vector_store_id:, file_id:)
          raise OperationError, "File status tracking is not supported for Pinecone"
        end

        private

        # -------------------------------------------------------------------
        # HTTP helpers
        # -------------------------------------------------------------------

        # POST to the data plane (index host).
        def data_plane_post(host, path, body)
          uri = URI("https://#{host}#{path}")
          req = Net::HTTP::Post.new(uri)
          req["Api-Key"]      = api_key
          req["Content-Type"] = "application/json"
          req["Accept"]       = "application/json"
          req.body            = body.to_json

          resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
            http.request(req)
          end

          raise OperationError, "Pinecone #{path} returned #{resp.code}: #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)

          JSON.parse(resp.body)
        end

        # GET from the control plane.
        def control_plane_get(path)
          uri = URI("https://#{CONTROL_PLANE_HOST}#{path}")
          req = Net::HTTP::Get.new(uri)
          req["Api-Key"]      = api_key
          req["Accept"]       = "application/json"

          resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
            http.request(req)
          end

          raise OperationError, "Pinecone #{path} returned #{resp.code}: #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)

          JSON.parse(resp.body)
        end

        # -------------------------------------------------------------------
        # Config helpers
        # -------------------------------------------------------------------

        # Resolve the data-plane host for the configured index.
        # Caches the result for 10 minutes since it doesn't change.
        #
        # @return [String, nil] host like "my-index-abc123.svc.aped-4627-b74a.pinecone.io"
        def index_host
          Rails.cache.fetch("pinecone_index_host_#{index_name}", expires_in: 10.minutes) do
            resp = control_plane_get("/indexes/#{index_name}")
            resp["host"]
          end
        rescue StandardError => e
          Rails.logger.warn("[Pinecone] Could not resolve index host for '#{index_name}': #{e.message}")
          nil
        end

        # Same as index_host but raises if the index doesn't exist.
        def index_host!
          host = index_host
          raise OperationError, "Pinecone index '#{index_name}' not found or unreachable. Create it at app.pinecone.io first." unless host
          host
        end

        def api_key
          cfg = pinecone_config
          key = cfg[:api_key]
          raise OperationError, "Pinecone API key not configured" if key.blank?
          key
        end

        def pinecone_config
          PromptTracker.configuration.vector_databases&.fetch(:pinecone, {}) || {}
        end

        def index_name
          pinecone_config[:index_name] || "prompt-tracker"
        end

        # Query Pinecone with a zero vector to retrieve metadata and extract
        # unique filenames. This is a fallback when the cache is empty (e.g.
        # after a server restart).
        def reconstruct_file_list(namespace)
          host = index_host
          return [] unless host

          # Get index dimension from describe_index_stats or config
          dimension = resolve_index_dimension(host)
          return [] unless dimension

          zero_vector = Array.new(dimension, 0.0)
          result = data_plane_post(host, "/query", {
            vector:          zero_vector,
            namespace:       namespace,
            topK:            100,
            includeMetadata: true
          })

          filenames = (result["matches"] || [])
            .map { |m| m.dig("metadata", "filename") }
            .compact
            .uniq

          filenames.map { |fn| { filename: fn, status: "completed", bytes: 0 } }
        rescue StandardError => e
          Rails.logger.warn("[Pinecone] Could not reconstruct file list for '#{namespace}': #{e.message}")
          []
        end

        # Get the dimension of the index (cached).
        def resolve_index_dimension(host)
          Rails.cache.fetch("pinecone_index_dimension_#{index_name}", expires_in: 10.minutes) do
            stats = data_plane_post(host, "/describe_index_stats", {})
            stats["dimension"]
          end
        rescue StandardError
          nil
        end

        def file_cache_key(namespace)
          "pinecone_files_#{namespace}"
        end

        def cache_file(namespace, filename)
          files = Rails.cache.fetch(file_cache_key(namespace), expires_in: 1.hour) { [] }
          files << { filename: filename, status: "completed", bytes: 0 }
          Rails.cache.write(
            file_cache_key(namespace),
            files.uniq { |f| f[:filename] },
            expires_in: 1.hour
          )
        end
      end
    end
  end
end
