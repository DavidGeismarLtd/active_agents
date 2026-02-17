# frozen_string_literal: true

module PromptTracker
  module Anthropic
    module Messages
      # Builds messages for function call continuation in the Anthropic Messages API.
      #
      # Unlike OpenAI's Responses API which uses input items, Anthropic requires
      # adding messages to the conversation history:
      # 1. The assistant message with tool_use content blocks (already in history)
      # 2. A user message with tool_result content blocks
      #
      # @example Build tool result message
      #   builder = FunctionInputBuilder.new(executor: executor)
      #   tool_result_message = builder.build_tool_result_message(tool_calls)
      #   # => {
      #   #   role: "user",
      #   #   content: [
      #   #     { type: "tool_result", tool_use_id: "toolu_123", content: "..." },
      #   #     ...
      #   #   ]
      #   # }
      #
      class FunctionInputBuilder
        # @param executor [Object] the executor to use for function calls
        #   Must respond to #execute(tool_call) and return a String
        def initialize(executor:)
          @executor = executor
        end

        # Build a user message containing tool_result content blocks
        #
        # This is the Anthropic format for sending tool outputs back to Claude.
        # All tool results are combined into a single user message.
        #
        # @param tool_calls [Array<Hash>] the tool calls from the API response
        # @return [Hash] a user message with tool_result content blocks
        def build_tool_result_message(tool_calls)
          {
            role: "user",
            content: build_tool_result_blocks(tool_calls)
          }
        end

        # Build individual tool_result content blocks
        #
        # @param tool_calls [Array<Hash>] the tool calls to process
        # @return [Array<Hash>] tool_result content blocks
        def build_tool_result_blocks(tool_calls)
          tool_calls.map do |tool_call|
            build_tool_result_block(tool_call)
          end
        end

        private

        # Build a single tool_result content block
        #
        # @param tool_call [Hash] the tool call to process
        #   - :id [String] the tool use ID
        #   - :function_name [String] name of the function
        #   - :arguments [Hash, String] function arguments
        # @return [Hash] a tool_result content block
        def build_tool_result_block(tool_call)
          output = @executor.execute(tool_call)

          {
            type: "tool_result",
            tool_use_id: tool_call[:id],
            content: format_output(output)
          }
        end

        # Format output for tool_result content
        #
        # Anthropic accepts either a string or an array of content blocks.
        # For simplicity, we use string format.
        #
        # @param output [String, Hash] the executor output
        # @return [String] formatted output
        def format_output(output)
          output.is_a?(String) ? output : output.to_json
        end
      end
    end
  end
end
