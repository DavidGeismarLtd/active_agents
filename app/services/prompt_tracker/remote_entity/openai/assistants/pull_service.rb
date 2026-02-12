# frozen_string_literal: true

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        # Service for pulling OpenAI Assistant data to update an existing PromptVersion.
        #
        # This service handles one-way synchronization:
        # - OpenAI Assistants (remote) → PromptTracker PromptVersions (local)
        #
        # Use case:
        # - When the assistant has been modified directly in OpenAI's interface
        # - User wants to pull those changes into their local PromptVersion
        #
        # @example Pull latest assistant data
        #   result = PullService.call(prompt_version: version)
        #   result.success? # => true
        #   result.prompt_version # => updated PromptVersion
        #
        class PullService
          Result = Data.define(:success?, :prompt_version, :synced_at, :errors)

          class PullError < StandardError; end

          # Pull assistant data from OpenAI and update the PromptVersion.
          #
          # @param prompt_version [PromptVersion] the prompt version to update
          # @return [Result] result with success?, prompt_version, synced_at, errors
          def self.call(prompt_version:)
            new(prompt_version: prompt_version).call
          end

          attr_reader :prompt_version, :model_config

          def initialize(prompt_version:)
            @prompt_version = prompt_version
            @model_config = prompt_version.model_config || {}
          end

          # Fetch assistant from OpenAI and update the PromptVersion.
          #
          # @return [Result] result object
          def call
            assistant_id = extract_assistant_id
            raise PullError, "No assistant_id found in model_config" if assistant_id.blank?

            # Fetch assistant from OpenAI
            assistant_data = client.assistants.retrieve(id: assistant_id)

            # Fetch vector store names for better display
            vector_store_names = fetch_vector_store_names(assistant_data)

            # Convert to PromptTracker format using FieldNormalizer
            attributes = FieldNormalizer.from_openai(assistant_data, vector_store_names: vector_store_names)

            # Update the PromptVersion with the remote data
            prompt_version.update!(
              system_prompt: attributes[:system_prompt],
              notes: attributes[:notes],
              model_config: attributes[:model_config]
            )

            success_result
          rescue => e
            failure_result([ e.message ])
          end

          private

          # Extract assistant_id from model_config
          def extract_assistant_id
            model_config[:assistant_id] || model_config["assistant_id"]
          end

          # Fetch vector store names from OpenAI for display purposes.
          #
          # @param assistant_data [Hash] the assistant data from OpenAI API
          # @return [Hash] mapping of vector store IDs to names, e.g., {"vs_abc123" => "My Store"}
          def fetch_vector_store_names(assistant_data)
            vector_store_ids = assistant_data.dig("tool_resources", "file_search", "vector_store_ids") || []
            return {} if vector_store_ids.empty?

            vector_store_ids.each_with_object({}) do |id, names|
              vs_data = PromptTracker::Openai::VectorStoreOperations.retrieve_vector_store(id: id)
              names[id] = vs_data[:name] || id
            rescue => e
              # If we can't fetch the name, fall back to using the ID
              Rails.logger.warn("Failed to fetch vector store name for #{id}: #{e.message}")
              names[id] = id
            end
          end

          # Build OpenAI client
          def client
            require "openai"

            api_key = PromptTracker.configuration.api_key_for(:openai)
            raise PullError, "OpenAI API key not configured" if api_key.blank?

            OpenAI::Client.new(access_token: api_key)
          end

          # Build success result
          def success_result
            Result.new(
              success?: true,
              prompt_version: prompt_version,
              synced_at: Time.current,
              errors: []
            )
          end

          # Build failure result
          def failure_result(errors)
            Result.new(
              success?: false,
              prompt_version: prompt_version,
              synced_at: nil,
              errors: errors
            )
          end
        end
      end
    end
  end
end
