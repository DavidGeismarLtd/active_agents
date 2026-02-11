# frozen_string_literal: true

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        # Normalizer for bidirectional field mapping between PromptTracker and OpenAI Assistants API.
        #
        # This normalizer handles the conversion of field names and formats between:
        # - PromptTracker's internal representation (PromptVersion model)
        # - OpenAI Assistants API format (as documented in docs/llm_providers/openai/assistants_api.md)
        #
        # Field Mappings:
        # - system_prompt ↔ instructions
        # - notes ↔ description
        # - tools (array of symbols) ↔ tools (array of hashes with "type" key)
        # - model_config[:model] ↔ model
        # - model_config[:temperature] ↔ temperature
        # - model_config[:top_p] ↔ top_p
        #
        # @example Convert PromptVersion to OpenAI format
        #   params = FieldNormalizer.to_openai(prompt_version)
        #   # => { model: "gpt-4o", instructions: "You are...", tools: [{"type": "code_interpreter"}], ... }
        #
        # @example Convert OpenAI response to PromptTracker format
        #   attributes = FieldNormalizer.from_openai(assistant_data)
        #   # => { system_prompt: "You are...", notes: "Description", model_config: {...} }
        #
        class FieldNormalizer
          # Convert PromptVersion to OpenAI Assistants API format.
          #
          # @param prompt_version [PromptVersion] the prompt version to convert
          # @return [Hash] parameters for OpenAI Assistants API create/update
          def self.to_openai(prompt_version)
            model_config = prompt_version.model_config || {}

            {
              model: model_config[:model] || model_config["model"],
              name: prompt_version.prompt.name,
              instructions: prompt_version.system_prompt,
              description: prompt_version.notes,
              tools: format_tools_for_openai(model_config[:tools] || model_config["tools"] || []),
              tool_resources: format_tool_resources_for_openai(model_config[:tool_config] || model_config["tool_config"]),
              temperature: model_config[:temperature] || model_config["temperature"] || 0.7,
              top_p: model_config[:top_p] || model_config["top_p"] || 1.0,
              # OpenAI requires all metadata values to be strings (max 512 chars each)
              metadata: {
                prompt_id: prompt_version.prompt_id.to_s,
                prompt_slug: prompt_version.prompt.slug,
                version_id: prompt_version.id.to_s,
                version_number: prompt_version.version_number.to_s,
                managed_by: "prompt_tracker",
                last_synced_at: Time.current.iso8601
              }
            }.compact
          end

          # Convert OpenAI Assistant data to PromptTracker format.
          #
          # @param assistant_data [Hash] the assistant data from OpenAI API
          # @param vector_store_names [Hash] optional mapping of vector store IDs to names
          #   e.g., {"vs_abc123" => "My Documents", "vs_def456" => "Knowledge Base"}
          # @return [Hash] attributes for PromptVersion model
          def self.from_openai(assistant_data, vector_store_names: {})
            {
              system_prompt: assistant_data["instructions"] || "",
              notes: assistant_data["description"],
              model_config: {
                provider: "openai",
                api: "assistants",
                assistant_id: assistant_data["id"],
                model: assistant_data["model"],
                temperature: assistant_data["temperature"] || 0.7,
                top_p: assistant_data["top_p"] || 1.0,
                tools: format_tools_from_openai(assistant_data["tools"] || []),
                tool_config: format_tool_config_from_openai(assistant_data["tool_resources"], vector_store_names: vector_store_names),
                metadata: {
                  name: assistant_data["name"],
                  description: assistant_data["description"],
                  synced_at: Time.current.iso8601,
                  synced_from: "openai"
                }
              }
            }
          end

          # Format tools array for OpenAI API (symbols → hashes with "type" key).
          #
          # @param tools [Array<Symbol, String>] array of tool symbols (e.g., [:code_interpreter, :file_search])
          # @return [Array<Hash>] array of tool hashes (e.g., [{"type" => "code_interpreter"}])
          #
          # @example
          #   format_tools_for_openai([:code_interpreter, :file_search])
          #   # => [{"type" => "code_interpreter"}, {"type" => "file_search"}]
          def self.format_tools_for_openai(tools)
            return [] if tools.blank?

            tools.map do |tool|
              if tool.is_a?(Hash)
                tool # Already in correct format
              else
                { "type" => tool.to_s }
              end
            end
          end

          # Format tools array from OpenAI API (hashes → symbols).
          #
          # @param tools [Array<Hash>] array of tool hashes from OpenAI (e.g., [{"type" => "code_interpreter"}])
          # @return [Array<Symbol>] array of tool symbols (e.g., [:code_interpreter])
          #
          # @example
          #   format_tools_from_openai([{"type" => "code_interpreter"}, {"type" => "file_search"}])
          #   # => [:code_interpreter, :file_search]
          def self.format_tools_from_openai(tools)
            return [] if tools.blank?

            tools.map do |tool|
              tool["type"]&.to_sym || tool[:type]&.to_sym
            end.compact
          end

          # Convert OpenAI tool_resources to PromptTracker tool_config format.
          #
          # OpenAI format:
          #   {"file_search" => {"vector_store_ids" => ["vs_xxx"]}}
          #
          # PromptTracker format:
          #   {"file_search" => {"vector_store_ids" => ["vs_xxx"], "vector_stores" => [{"id" => "vs_xxx", "name" => "My Store"}]}}
          #
          # @param tool_resources [Hash] OpenAI tool_resources hash
          # @param vector_store_names [Hash] optional mapping of vector store IDs to names
          #   e.g., {"vs_abc123" => "My Documents"}
          # @return [Hash] PromptTracker tool_config hash
          def self.format_tool_config_from_openai(tool_resources, vector_store_names: {})
            return {} if tool_resources.blank?

            tool_config = {}

            # Convert file_search resources
            if tool_resources["file_search"].present?
              vector_store_ids = tool_resources.dig("file_search", "vector_store_ids") || []
              tool_config["file_search"] = {
                "vector_store_ids" => vector_store_ids,
                "vector_stores" => vector_store_ids.map do |id|
                  { "id" => id, "name" => vector_store_names[id] || id }
                end
              }
            end

            # Convert code_interpreter resources (if any)
            if tool_resources["code_interpreter"].present?
              tool_config["code_interpreter"] = tool_resources["code_interpreter"]
            end

            tool_config
          end

          # Convert PromptTracker tool_config to OpenAI tool_resources format.
          #
          # PromptTracker format:
          #   {"file_search" => {"vector_store_ids" => ["vs_xxx"], "vector_stores" => [...]}}
          #
          # OpenAI format:
          #   {"file_search" => {"vector_store_ids" => ["vs_xxx"]}}
          #
          # @param tool_config [Hash] PromptTracker tool_config hash
          # @return [Hash, nil] OpenAI tool_resources hash or nil if empty
          def self.format_tool_resources_for_openai(tool_config)
            return nil if tool_config.blank?

            tool_resources = {}

            # Convert file_search config
            if tool_config["file_search"].present? || tool_config[:file_search].present?
              file_search = tool_config["file_search"] || tool_config[:file_search]
              vector_store_ids = file_search["vector_store_ids"] || file_search[:vector_store_ids] || []
              if vector_store_ids.present?
                tool_resources["file_search"] = { "vector_store_ids" => vector_store_ids }
              end
            end

            # Convert code_interpreter config (if any)
            if tool_config["code_interpreter"].present? || tool_config[:code_interpreter].present?
              code_interpreter = tool_config["code_interpreter"] || tool_config[:code_interpreter]
              tool_resources["code_interpreter"] = code_interpreter
            end

            tool_resources.presence
          end
        end
      end
    end
  end
end
