# frozen_string_literal: true

module PromptTracker
  module Openai
    module Assistants
      # Normalizes OpenAI Assistants API data into PromptTracker's internal model_config format
      #
      # The OpenAI Assistants API returns tools as an array of hashes:
      #   [{"type"=>"file_search", "file_search"=>{...}}, {"type"=>"code_interpreter"}]
      #
      # We normalize this to a simple string array:
      #   ["file_search", "code_interpreter"]
      #
      # Tool-specific configuration (like file_search ranking options) is stored separately
      # in the tool_resources field, which we preserve as-is.
      #
      # @example
      #   assistant_data = {
      #     "id" => "asst_abc123",
      #     "model" => "gpt-4o",
      #     "tools" => [{"type" => "file_search", "file_search" => {...}}],
      #     "tool_resources" => {"file_search" => {"vector_store_ids" => ["vs_123"]}}
      #   }
      #
      #   config = ModelConfigNormalizer.normalize(assistant_data)
      #   # => {
      #   #   provider: "openai",
      #   #   api: "assistants",
      #   #   assistant_id: "asst_abc123",
      #   #   model: "gpt-4o",
      #   #   tools: ["file_search"],  # ← normalized to string array
      #   #   tool_resources: {"file_search" => {"vector_store_ids" => ["vs_123"]}},
      #   #   ...
      #   # }
      #
      class ModelConfigNormalizer
        # Normalize OpenAI assistant data to PromptTracker model_config format
        #
        # @param assistant_data [Hash] raw assistant data from OpenAI API
        # @return [Hash] normalized model_config hash
        def self.normalize(assistant_data)
          new(assistant_data).normalize
        end

        def initialize(assistant_data)
          @assistant_data = assistant_data
        end

        # Normalize the assistant data
        #
        # @return [Hash] normalized model_config
        def normalize
          {
            provider: "openai",
            api: "assistants",
            assistant_id: assistant_data["id"],
            model: assistant_data["model"],
            temperature: assistant_data["temperature"] || 0.7,
            top_p: assistant_data["top_p"] || 1.0,
            tools: normalize_tools,
            tool_resources: assistant_data["tool_resources"] || {},
            metadata: build_metadata
          }
        end

        private

        attr_reader :assistant_data

        # Normalize tools from OpenAI hash format to string array
        #
        # OpenAI format: [{"type"=>"file_search", "file_search"=>{...}}, {"type"=>"code_interpreter"}]
        # Our format: ["file_search", "code_interpreter"]
        #
        # @return [Array<String>] array of tool type strings
        def normalize_tools
          raw_tools = assistant_data["tools"] || []

          raw_tools.map do |tool|
            # Extract type from hash or use string directly
            tool.is_a?(Hash) ? tool["type"] : tool.to_s
          end.compact.select(&:present?)
        end

        # Build metadata hash with assistant info
        #
        # @return [Hash] metadata hash
        def build_metadata
          {
            name: assistant_data["name"],
            description: assistant_data["description"],
            synced_at: Time.current.iso8601
          }
        end
      end
    end
  end
end
