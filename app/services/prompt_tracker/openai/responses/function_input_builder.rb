# frozen_string_literal: true

module PromptTracker
  module Openai
    module Responses
      # Builds input arrays for function call continuation in the OpenAI Responses API.
      #
      # The Responses API requires a specific format when sending function outputs back:
      # each function_call must be paired with its corresponding function_call_output.
      # This class handles building that paired structure.
      #
      # @example Build continuation input
      #   executor = FunctionExecutor.new
      #   builder = FunctionInputBuilder.new(executor: executor)
      #   input = builder.build_continuation_input(tool_calls)
      #   # => [
      #   #   { type: "function_call", call_id: "call_123", name: "get_weather", arguments: "..." },
      #   #   { type: "function_call_output", call_id: "call_123", output: "..." },
      #   #   ...
      #   # ]
      #
      class FunctionInputBuilder
        # @param executor [FunctionExecutor] the executor to use for function calls
        def initialize(executor:)
          @executor = executor
        end

        # Build the complete continuation input from tool calls
        #
        # This is a convenience method that builds outputs and pairs them in one call.
        #
        # @param tool_calls [Array<Hash>] the tool calls from the API response
        # @return [Array<Hash>] paired function_call + function_call_output items
        def build_continuation_input(tool_calls)
          outputs = build_outputs(tool_calls)
          pair_calls_with_outputs(tool_calls, outputs)
        end

        # Build function_call_output items for each tool call
        #
        # @param tool_calls [Array<Hash>] the tool calls to process
        # @return [Array<Hash>] function_call_output items
        def build_outputs(tool_calls)
          tool_calls.map do |tool_call|
            {
              type: "function_call_output",
              call_id: tool_call[:id],
              output: @executor.execute(tool_call)
            }
          end
        end

        # Pair each function_call with its corresponding function_call_output
        #
        # The OpenAI Responses API requires BOTH the original function_call AND
        # the corresponding function_call_output to be included in the input array,
        # interleaved sequentially.
        #
        # @param tool_calls [Array<Hash>] the original function calls from the response
        # @param function_outputs [Array<Hash>] the function_call_output items
        # @return [Array<Hash>] interleaved function_call + function_call_output items
        def pair_calls_with_outputs(tool_calls, function_outputs)
          tool_calls.each_with_index.flat_map do |tool_call, index|
            [
              build_function_call_item(tool_call),
              function_outputs[index]
            ]
          end
        end

        private

        # Build a function_call item from a tool call
        #
        # @param tool_call [Hash] the original tool call
        # @return [Hash] formatted function_call item for the API
        def build_function_call_item(tool_call)
          {
            type: "function_call",
            call_id: tool_call[:id],
            name: tool_call[:function_name],
            arguments: normalize_arguments(tool_call[:arguments])
          }
        end

        # Normalize arguments to JSON string format
        #
        # @param arguments [Hash, String] the arguments to normalize
        # @return [String] JSON string
        def normalize_arguments(arguments)
          arguments.is_a?(String) ? arguments : arguments.to_json
        end
      end
    end
  end
end
