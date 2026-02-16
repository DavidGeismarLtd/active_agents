# frozen_string_literal: true

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        # Service for pushing PromptVersion changes to OpenAI Assistants API.
        #
        # This service handles one-way synchronization:
        # - PromptTracker PromptVersions (local) → OpenAI Assistants (remote)
        #
        # Strategy:
        # - Each Prompt has ONE corresponding remote assistant
        # - Multiple PromptVersions update the same remote assistant
        # - Version metadata is stored in assistant's metadata field
        #
        # @example Create a new assistant
        #   result = PushService.create(prompt_version: version)
        #   result.success? # => true
        #   result.assistant_id # => "asst_abc123"
        #
        # @example Update an existing assistant
        #   result = PushService.update(prompt_version: version)
        #   result.success? # => true
        #
        class PushService
          Result = Data.define(:success?, :assistant_id, :synced_at, :errors)

          class PushError < StandardError; end

          # Create a new assistant on OpenAI.
          #
          # @param prompt_version [PromptVersion] the prompt version to push
          # @return [Result] result with success?, assistant_id, synced_at, errors
          def self.create(prompt_version:)
            new(prompt_version: prompt_version).create
          end

          # Update an existing assistant on OpenAI.
          #
          # @param prompt_version [PromptVersion] the prompt version to push
          # @return [Result] result with success?, assistant_id, synced_at, errors
          def self.update(prompt_version:)
            new(prompt_version: prompt_version).update
          end

          attr_reader :prompt_version, :model_config

          def initialize(prompt_version:)
            @prompt_version = prompt_version
            @model_config = prompt_version.model_config || {}
          end

          # Create a new assistant on OpenAI and update the PromptVersion with the assistant_id.
          #
          # @return [Result] result object
          def create
            params = FieldNormalizer.to_openai(prompt_version)

            # Call OpenAI API to create assistant
            response = client.assistants.create(parameters: params)

            # Update the PromptVersion with the assistant_id
            update_prompt_version_with_assistant_id(response["id"])

            success_result(response["id"])
          rescue => e
            failure_result(nil, [ e.message ])
          end

          # Update an existing assistant on OpenAI.
          #
          # @return [Result] result object
          def update
            assistant_id = extract_assistant_id
            raise PushError, "No assistant_id found in model_config" if assistant_id.blank?

            params = FieldNormalizer.to_openai(prompt_version)

            # Call OpenAI API to update assistant
            response = client.assistants.modify(
              id: assistant_id,
              parameters: params
            )

            # Update sync metadata
            update_sync_metadata

            success_result(response["id"])
          rescue => e
            failure_result(extract_assistant_id, [ e.message ])
          end

          private

          # Extract assistant_id from model_config
          def extract_assistant_id
            model_config[:assistant_id] || model_config["assistant_id"]
          end

          # Update PromptVersion with the assistant_id after creation
          def update_prompt_version_with_assistant_id(assistant_id)
            updated_config = model_config.deep_dup
            updated_config[:assistant_id] = assistant_id
            updated_config[:metadata] ||= {}
            updated_config[:metadata][:synced_at] = Time.current.iso8601
            updated_config[:metadata][:sync_status] = "synced"

            prompt_version.update!(model_config: updated_config)
          end

          # Update sync metadata after successful update
          def update_sync_metadata
            updated_config = model_config.deep_dup
            updated_config[:metadata] ||= {}
            updated_config[:metadata][:synced_at] = Time.current.iso8601
            updated_config[:metadata][:sync_status] = "synced"

            prompt_version.update!(model_config: updated_config)
          end

          # Build OpenAI client
          def client
            require "openai"
            api_key = PromptTracker.configuration.api_key_for(:openai) || ENV["OPENAI_LOUNA_API_KEY"]
            raise PushError, "OpenAI API key not configured" if api_key.blank?

            OpenAI::Client.new(access_token: api_key)
          end

          # Build success result
          def success_result(assistant_id)
            Result.new(
              success?: true,
              assistant_id: assistant_id,
              synced_at: Time.current,
              errors: []
            )
          end

          # Build failure result
          def failure_result(assistant_id, errors)
            Result.new(
              success?: false,
              assistant_id: assistant_id,
              synced_at: nil,
              errors: errors
            )
          end
        end
      end
    end
  end
end
