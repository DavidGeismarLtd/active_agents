# frozen_string_literal: true

module PromptTracker
  module Openai
    module Responses
      # Executes function calls and returns their outputs.
      #
      # This class handles the execution of function calls from the OpenAI Responses API.
      # In the current implementation, it provides mock responses, but can be extended
      # to support real function execution.
      #
      # @example Execute a function call with default mock
      #   executor = FunctionExecutor.new
      #   result = executor.execute(tool_call)
      #   # => '{"success":true,"message":"Mock result for get_weather","data":{...}}'
      #
      # @example Execute with custom mock responses
      #   executor = FunctionExecutor.new(
      #     mock_function_outputs: {
      #       "get_weather" => { temperature: 72, condition: "sunny" }
      #     }
      #   )
      #   result = executor.execute(tool_call)
      #   # => '{"temperature":72,"condition":"sunny"}'
      #
      class FunctionExecutor
        # @param mock_function_outputs [Hash, nil] custom mock responses keyed by function name
        def initialize(mock_function_outputs: nil)
          @mock_function_outputs = mock_function_outputs
        end

        # Execute a function call and return the result
        #
        # @param tool_call [Hash] the function call details
        #   - :function_name [String] name of the function to execute
        #   - :arguments [Hash, String] function arguments
        # @return [String] function execution result as JSON string
        def execute(tool_call)
          function_name = tool_call[:function_name]
          custom_mock = @mock_function_outputs&.dig(function_name)

          if custom_mock
            format_custom_mock(custom_mock)
          else
            default_mock_response(function_name, tool_call[:arguments])
          end
        end

        private

        # Format custom mock response to JSON string
        #
        # @param custom_mock [Hash, String] the custom mock value
        # @return [String] JSON string
        def format_custom_mock(custom_mock)
          custom_mock.is_a?(Hash) ? custom_mock.to_json : custom_mock
        end

        # Generate a default mock response
        #
        # @param function_name [String] name of the function
        # @param arguments [Hash, String] function arguments
        # @return [String] JSON string with mock response
        def default_mock_response(function_name, arguments)
          {
            success: true,
            message: "Mock result for #{function_name}",
            data: arguments
          }.to_json
        end
      end
    end
  end
end
