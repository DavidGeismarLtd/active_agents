# frozen_string_literal: true

module PromptTracker
  # Retrieves relevant chunks from a configured vector database and formats
  # them as a context block to prepend to the system prompt.
  #
  # Called by the LLM pipeline for any non-OpenAI provider that has
  # `vector_db_config` set inside `tool_config.file_search`.
  #
  # @example Usage in a conversation runner
  #   context = RagContextInjector.retrieve(
  #     tool_config: model_config["tool_config"],
  #     user_message: "What is the refund policy?"
  #   )
  #   system_prompt = "#{context}\n\n#{original_system_prompt}" if context
  #
  class RagContextInjector
    # Retrieve relevant chunks and return a formatted context string.
    #
    # @param tool_config [Hash] the tool_config hash from model_config
    #   Expected shape:
    #   {
    #     "file_search" => {
    #       "vector_db_config" => {
    #         "provider"         => "pinecone",
    #         "vector_store_ids" => ["my-collection"]
    #       }
    #     }
    #   }
    # @param user_message [String] the latest user message used as the query
    # @param top_k [Integer] number of chunks to retrieve per collection
    # @return [String, nil] formatted context block, or nil if RAG is not configured
    def self.retrieve(tool_config:, user_message:, top_k: 5)
      return nil if user_message.blank?

      vdb_config = tool_config&.dig("file_search", "vector_db_config")
      return nil unless vdb_config.present?

      provider         = vdb_config["provider"].to_sym
      vector_store_ids = Array(vdb_config["vector_store_ids"])

      return nil unless PromptTracker.configuration.vector_database_configured?(provider)
      return nil if vector_store_ids.empty?

      chunks = vector_store_ids.flat_map do |store_id|
        VectorStoreService.query(
          provider:        provider,
          vector_store_id: store_id,
          query_text:      user_message,
          top_k:           top_k
        )
      rescue StandardError => e
        Rails.logger.error("[RagContextInjector] Query failed for #{provider}/#{store_id}: #{e.message}")
        []
      end

      return nil if chunks.empty?

      format_context(chunks)
    end

    private

    def self.format_context(chunks)
      lines = chunks.map do |chunk|
        score_str = chunk[:score] ? " (relevance: #{chunk[:score].round(2)})" : ""
        source    = chunk[:filename] ? " [source: #{chunk[:filename]}]" : ""
        "- #{chunk[:text]}#{source}#{score_str}"
      end

      <<~CONTEXT
        [Retrieved context from knowledge base]
        #{lines.join("\n")}
        [End of retrieved context]
      CONTEXT
    end
  end
end
