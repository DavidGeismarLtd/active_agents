# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Concerns
      # Concern providing accessor methods for conversation data.
      #
      # This concern is included in BaseEvaluator to provide convenient
      # methods for accessing messages, tool usage, and other response data.
      #
      # The data is expected to be pre-normalized from test_run.output_data or
      # simulated conversation runners which return NormalizedLlmResponse objects.
      #
      module ConversationDataAccessors
        extend ActiveSupport::Concern

        # === Message Accessors ===

        # Get all messages from the data
        # @return [Array<Hash>] array of message hashes
        def messages
          @messages ||= data[:messages] || []
        end

        # Get the last message (usually the assistant's response)
        # @return [Hash, nil] the last message or nil
        def last_message
          messages.last
        end

        # Get the response text (from last assistant message)
        # For backward compatibility with single-response evaluators
        # @return [String] the response text
        def response_text
          @response_text ||= begin
            # Find the last assistant message
            assistant_msg = messages.reverse.find { |m| m[:role] == "assistant" }
            assistant_msg&.dig(:content) || ""
          end
        end

        # Get all assistant messages
        # @return [Array<Hash>] array of assistant message hashes
        def assistant_messages
          @assistant_messages ||= messages.select { |m| m[:role] == "assistant" }
        end

        # Get all user messages
        # @return [Array<Hash>] array of user message hashes
        def user_messages
          @user_messages ||= messages.select { |m| m[:role] == "user" }
        end

        # === Tool Usage Accessors ===

        # Get aggregated tool usage
        # @return [Array<Hash>] array of tool usage records
        def tool_usage
          data[:tool_usage] || []
        end

        # Get web search results
        # @return [Array<Hash>] array of web search result records
        def web_search_results
          data[:web_search_results] || []
        end

        # Get code interpreter results
        # @return [Array<Hash>] array of code interpreter result records
        def code_interpreter_results
          data[:code_interpreter_results] || []
        end

        # Get file search results
        # @return [Array<Hash>] array of file search result records
        def file_search_results
          data[:file_search_results] || []
        end

        # Get Assistants API run steps (nil for other APIs)
        # @return [Array<Hash>, nil] array of run steps or nil
        def run_steps
          data[:run_steps]
        end

        # Check if run steps are available (Assistants API only)
        # @return [Boolean] true if run_steps data is present
        def run_steps_available?
          run_steps.present?
        end

        # Get response metadata
        # @return [Hash] metadata about the response
        def response_metadata
          data[:metadata] || {}
        end

        private

        # Normalize input to standard format
        #
        # Data is expected to be pre-normalized from test_run.output_data or
        # directly from the simulated conversation runners.
        #
        # @param input [String, Hash] raw input
        # @return [Hash] normalized data hash with symbol keys
        def normalize_input(input)
          case input
          when String
            # Simple string response for direct evaluation
            {
              messages: [ { role: "assistant", content: input, tool_calls: [], turn: 1 } ],
              tool_usage: [],
              web_search_results: [],
              code_interpreter_results: [],
              file_search_results: [],
              run_steps: nil,
              metadata: {}
            }
          when Hash
            # Data should already be in normalized format from runners
            input = input.deep_symbolize_keys
            {
              messages: input[:messages] || [],
              tool_usage: input[:tool_usage] || [],
              web_search_results: input[:web_search_results] || [],
              code_interpreter_results: input[:code_interpreter_results] || [],
              file_search_results: input[:file_search_results] || [],
              run_steps: input[:run_steps],
              metadata: input[:metadata] || {}
            }
          else
            # Fallback: convert to string
            {
              messages: [ { role: "assistant", content: input.to_s, tool_calls: [], turn: 1 } ],
              tool_usage: [],
              web_search_results: [],
              code_interpreter_results: [],
              file_search_results: [],
              run_steps: nil,
              metadata: {}
            }
          end
        end
      end
    end
  end
end
