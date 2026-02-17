# frozen_string_literal: true

module PromptTracker
  module RubyLlm
    # Builds dynamic RubyLLM::Tool subclasses from JSON tool configurations.
    #
    # This enables using JSON Schema-based tool definitions stored in PromptTracker
    # with RubyLLM's native tool handling. RubyLLM automatically handles the entire
    # tool execution loop (request → execute → result → continue).
    #
    # @example Build tools from a PromptTracker tool_config
    #   tool_config = {
    #     "functions" => [
    #       {
    #         "name" => "get_weather",
    #         "description" => "Get weather for a city",
    #         "parameters" => {
    #           "type" => "object",
    #           "properties" => {
    #             "city" => { "type" => "string", "description" => "City name" }
    #           },
    #           "required" => ["city"]
    #         }
    #       }
    #     ]
    #   }
    #
    #   tool_classes = DynamicToolBuilder.build(tool_config: tool_config)
    #   chat = RubyLLM.chat(model: 'gpt-4o').with_tool(tool_classes.first.new)
    #
    # @example With custom mock outputs for testing
    #   mock_outputs = { "get_weather" => { "temperature" => 72, "conditions" => "Sunny" } }
    #   tool_classes = DynamicToolBuilder.build(
    #     tool_config: tool_config,
    #     mock_function_outputs: mock_outputs
    #   )
    #
    class DynamicToolBuilder
      attr_reader :tool_config, :mock_function_outputs

      # Build RubyLLM::Tool subclasses from a tool configuration
      #
      # @param tool_config [Hash] PromptTracker tool configuration
      #   { "functions" => [{ "name" => "...", "description" => "...", "parameters" => {...} }] }
      # @param mock_function_outputs [Hash, nil] Optional mock outputs for testing
      #   { "function_name" => { "result" => "..." } }
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def self.build(tool_config:, mock_function_outputs: nil)
        new(tool_config: tool_config, mock_function_outputs: mock_function_outputs).build
      end

      def initialize(tool_config:, mock_function_outputs: nil)
        @tool_config = tool_config || {}
        @mock_function_outputs = mock_function_outputs
      end

      # Build all tool classes from the configuration
      #
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def build
        functions = tool_config["functions"] || []
        functions.map { |func_def| build_tool_class(func_def) }
      end

      private

      # Build a single RubyLLM::Tool subclass from a function definition
      #
      # @param func_def [Hash] Function definition with name, description, parameters
      # @return [Class] A RubyLLM::Tool subclass
      def build_tool_class(func_def)
        mock_outputs = mock_function_outputs
        func_name = func_def["name"]
        func_description = func_def["description"] || ""
        func_parameters = func_def["parameters"]

        Class.new(::RubyLLM::Tool) do
          # Set description
          description func_description

          # Set parameters using JSON Schema directly (v1.9+ feature)
          # This passes the schema hash directly to RubyLLM
          if func_parameters.present?
            params(**func_parameters.deep_symbolize_keys)
          end

          # Override name to return the function name from config
          define_method(:name) { func_name }

          # Class-level tool name for registration
          define_singleton_method(:tool_name) { func_name }

          # Execute returns mock data (since PromptTracker uses mock execution for testing)
          define_method(:execute) do |**args|
            custom_mock = mock_outputs&.dig(func_name)
            if custom_mock
              # Return custom mock output as-is if it's already a Hash
              custom_mock.is_a?(Hash) ? custom_mock : { result: custom_mock }
            else
              # Default mock response with execution details
              {
                status: "success",
                function: func_name,
                result: "Mock response for #{func_name}",
                received_arguments: args
              }
            end
          end
        end
      end
    end
  end
end
