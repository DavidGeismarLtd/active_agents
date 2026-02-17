# frozen_string_literal: true

module PromptTracker
  module Anthropic
    module Messages
      # Formats tools for Anthropic Messages API requests.
      #
      # Handles conversion of PromptTracker's internal tool format to the
      # format expected by Anthropic's Messages API.
      #
      # Key differences from OpenAI:
      # - Tool property `parameters` → `input_schema`
      # - No separate `type: "function"` wrapper
      # - Tool format: { name:, description:, input_schema: }
      #
      # @example Format tools for API request
      #   formatter = ToolFormatter.new(
      #     tools: [:functions],
      #     tool_config: {
      #       "functions" => [
      #         { "name" => "get_weather", "description" => "Get weather", "parameters" => {...} }
      #       ]
      #     }
      #   )
      #   formatted_tools = formatter.format
      #   # => [{ name: "get_weather", description: "Get weather", input_schema: {...} }]
      #
      class ToolFormatter
        attr_reader :tools, :tool_config

        # @param tools [Array<Symbol, Hash>] tool symbols or custom tool hashes
        # @param tool_config [Hash] configuration for tools (string keys from database JSONB)
        def initialize(tools:, tool_config: {})
          @tools = tools || []
          @tool_config = tool_config || {}
        end

        # Format all tools into Anthropic API format
        #
        # @return [Array<Hash>] formatted tools for Anthropic API
        def format
          formatted = []

          tools.each do |tool|
            # Allow passing custom tool hashes directly (already in Anthropic format)
            if tool.is_a?(Hash)
              formatted << tool
              next
            end

            case tool.to_sym
            when :functions
              # Custom function definitions
              formatted.concat(format_function_tools)
            when :web_search
              # Anthropic's built-in web search tool
              formatted << { type: "web_search", name: "web_search" }
            else
              # Unknown tool type - skip or add as-is
              # (Anthropic doesn't have file_search or code_interpreter built-in)
              nil
            end
          end

          formatted
        end

        # Check if any tools are configured
        #
        # @return [Boolean] true if there are tools to format
        def any?
          tools.any?
        end

        private

        # Format custom function definitions into Anthropic API format
        #
        # Anthropic tool format:
        # {
        #   "name": "get_weather",
        #   "description": "Get weather for a location",
        #   "input_schema": {
        #     "type": "object",
        #     "properties": { "location": { "type": "string" } },
        #     "required": ["location"]
        #   }
        # }
        #
        # @return [Array<Hash>] formatted function tools
        def format_function_tools
          functions = tool_config["functions"] || []

          functions.map do |func|
            {
              name: func["name"],
              description: func["description"] || "",
              input_schema: func["parameters"] || { type: "object", properties: {} }
            }
          end
        end
      end
    end
  end
end
