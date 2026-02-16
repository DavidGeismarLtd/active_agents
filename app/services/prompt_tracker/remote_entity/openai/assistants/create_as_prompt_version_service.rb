# frozen_string_literal: true

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        # Service for creating a new Prompt and PromptVersion from OpenAI Assistant data.
        #
        # This service handles the initial import of an assistant:
        # - Creates a new Prompt record
        # - Creates a new PromptVersion record with the assistant's configuration
        #
        # Use case:
        # - Importing assistants from OpenAI into PromptTracker for the first time
        # - Used by SyncOpenaiAssistantsToPromptVersionsService for bulk imports
        #
        # @example Create from assistant data
        #   result = CreateAsPromptVersionService.call(assistant_data: data)
        #   result.success? # => true
        #   result.prompt # => Prompt
        #   result.prompt_version # => PromptVersion
        #
        class CreateAsPromptVersionService
          Result = Data.define(:success?, :prompt, :prompt_version, :errors)

          class CreateError < StandardError; end

          # Create a Prompt and PromptVersion from assistant data.
          #
          # @param assistant_data [Hash] assistant data from OpenAI API
          # @return [Result] result with success?, prompt, prompt_version, errors
          def self.call(assistant_data:)
            new(assistant_data: assistant_data).call
          end

          attr_reader :assistant_data

          def initialize(assistant_data:)
            @assistant_data = assistant_data
          end

          # Create the Prompt and PromptVersion.
          #
          # @return [Result] result object
          def call
            # Fetch vector store names for better display
            vector_store_names = fetch_vector_store_names

            # Use FieldNormalizer to convert OpenAI data to PromptTracker format
            attributes = FieldNormalizer.from_openai(assistant_data, vector_store_names: vector_store_names)

            # Create the Prompt
            prompt = Prompt.create!(
              name: assistant_name,
              slug: generate_slug,
              description: assistant_data["description"] || "Synced from OpenAI Assistant",
              category: "assistant"
            )

            # Create the PromptVersion
            version = prompt.prompt_versions.create!(
              system_prompt: attributes[:system_prompt],
              user_prompt: "{{user_message}}",  # Default template for assistant conversations
              version_number: 1,
              status: "draft",
              model_config: attributes[:model_config],
              notes: "Synced from OpenAI Assistant: #{assistant_name}"
            )

            success_result(prompt, version)
          rescue => e
            failure_result([ e.message ])
          end

          private

          # Get assistant ID
          def assistant_id
            assistant_data["id"]
          end

          # Get assistant name with fallback
          def assistant_name
            assistant_data["name"].presence || "Assistant #{assistant_id}"
          end

          # Fetch vector store names from OpenAI for display purposes.
          #
          # @return [Hash] mapping of vector store IDs to names, e.g., {"vs_abc123" => "My Store"}
          def fetch_vector_store_names
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

          # Generate a unique slug for the assistant
          #
          # @return [String] slug for the prompt (e.g., "assistant_asst_abc123")
          def generate_slug
            # Sanitize assistant_id to ensure it only contains valid characters
            sanitized_id = assistant_id.to_s
                                        .downcase
                                        .gsub(/[^a-z0-9_]+/, "_")
                                        .gsub(/^_+|_+$/, "")
                                        .gsub(/_+/, "_")

            base_slug = "assistant_#{sanitized_id}"

            # Ensure uniqueness by appending a counter if needed
            slug = base_slug
            counter = 1
            while Prompt.exists?(slug: slug)
              slug = "#{base_slug}_#{counter}"
              counter += 1
            end

            slug
          end

          # Build success result
          def success_result(prompt, version)
            Result.new(
              success?: true,
              prompt: prompt,
              prompt_version: version,
              errors: []
            )
          end

          # Build failure result
          def failure_result(errors)
            Result.new(
              success?: false,
              prompt: nil,
              prompt_version: nil,
              errors: errors
            )
          end
        end
      end
    end
  end
end
