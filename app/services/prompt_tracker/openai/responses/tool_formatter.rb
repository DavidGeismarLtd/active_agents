# frozen_string_literal: true

module PromptTracker
  module Openai
    module Responses
      # Formats tools for OpenAI Responses API requests.
      #
      # Handles conversion of tool symbols and configurations into the
      # format expected by the Responses API.
      #
      # @example Format tools for API request
      #   formatter = ToolFormatter.new(
      #     tools: [:web_search, :file_search, :functions],
      #     tool_config: {
      #       "file_search" => { "vector_store_ids" => ["vs_123"] },
      #       "functions" => [{ "name" => "get_weather", "description" => "...", "parameters" => {...} }]
      #     }
      #   )
      #   formatted_tools = formatter.format
      #   # => [{ type: "web_search_preview" }, { type: "file_search", vector_store_ids: ["vs_123"] }, ...]
      #
      class ToolFormatter
        attr_reader :tools, :tool_config

        # @param tools [Array<Symbol, Hash>] tool symbols or custom tool hashes
        # @param tool_config [Hash] configuration for tools (string keys from database JSONB)
        def initialize(tools:, tool_config: {})
          @tools = tools || []
          @tool_config = tool_config || {}
        end

        # Format all tools into API format
        #
        # @return [Array<Hash>] formatted tools
        def format
          formatted = []

          tools.each do |tool|
            # Allow passing custom tool hashes directly
            if tool.is_a?(Hash)
              formatted << tool
              next
            end

            case tool.to_sym
            when :web_search
              formatted << { type: "web_search_preview" }
            when :file_search
              formatted << format_file_search_tool
            when :code_interpreter
              formatted << { type: "code_interpreter" }
            when :functions
              # Functions are added separately, not as a single tool
              formatted.concat(format_function_tools)
            else
              formatted << { type: tool.to_s }
            end
          end

          formatted
        end

        # Check if web search tool is enabled
        #
        # @return [Boolean] true if web search tool is present
        def has_web_search_tool?
          tools.any? do |tool|
            tool.is_a?(Symbol) && [ :web_search, :web_search_preview ].include?(tool) ||
            tool.is_a?(Hash) && [ "web_search", "web_search_preview" ].include?(tool[:type])
          end
        end

        private

        # Format file_search tool with optional vector_store_ids
        #
        # tool_config comes from database JSONB and always uses string keys
        #
        # @return [Hash] formatted file_search tool
        def format_file_search_tool
          file_search_config = tool_config["file_search"] || {}
          vector_store_ids = file_search_config["vector_store_ids"] || []

          # OpenAI Responses API has a hard limit of 2 vector stores
          # Enforce this limit as a fallback for backward compatibility
          vector_store_ids = vector_store_ids.first(2) if vector_store_ids.length > 2

          tool_hash = { type: "file_search" }
          tool_hash[:vector_store_ids] = vector_store_ids if vector_store_ids.any?
          tool_hash
        end

        # Format custom function definitions into API format
        #
        # tool_config and function hashes come from database JSONB and always use string keys
        #
        # @return [Array<Hash>] formatted function tools
        def format_function_tools
          functions = tool_config["functions"] || []

          functions.map do |func|
            tool_hash = {
              type: "function",
              name: func["name"],
              description: func["description"] || "",
              parameters: func["parameters"] || {}
            }

            # Handle strict mode:
            # - If strict is explicitly true, include it (requires additionalProperties: false in schema)
            # - If strict is explicitly false, include it to opt out of auto-normalization
            # - If strict is nil/omitted, don't include it (Responses API will auto-normalize to strict mode)
            if func["strict"] == true || func["strict"] == false
              tool_hash[:strict] = func["strict"]
            end

            tool_hash
          end
        end
      end
    end
  end
end
