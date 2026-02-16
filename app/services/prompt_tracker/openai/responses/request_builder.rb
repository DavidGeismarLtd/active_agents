# frozen_string_literal: true

module PromptTracker
  module Openai
    module Responses
      # Builds request parameters for OpenAI Responses API.
      #
      # Handles the construction of API parameters including input, instructions,
      # tools, and response options. Delegates tool formatting to ToolFormatter.
      #
      # @example Build parameters for a single-turn request
      #   builder = RequestBuilder.new(
      #     model: "gpt-4o",
      #     input: "What's the weather?",
      #     instructions: "You are a helpful assistant.",
      #     tools: [:web_search],
      #     temperature: 0.7
      #   )
      #   params = builder.build
      #   # => { model: "gpt-4o", input: "What's the weather?", instructions: "...", ... }
      #
      # @example Build parameters for a multi-turn conversation
      #   builder = RequestBuilder.new(
      #     model: "gpt-4o",
      #     input: "What's my name?",
      #     previous_response_id: "resp_123"
      #   )
      #   params = builder.build
      #
      class RequestBuilder
        attr_reader :model, :input, :instructions, :previous_response_id,
                    :tools, :tool_config, :temperature, :max_tokens, :options

        # @param model [String] the model ID (e.g., "gpt-4o")
        # @param input [String, Array] the user message or array of input items
        # @param instructions [String, nil] optional system instructions
        # @param previous_response_id [String, nil] ID for multi-turn conversations
        # @param tools [Array<Symbol>] Response API tools
        # @param tool_config [Hash] configuration for tools
        # @param temperature [Float] the temperature (0.0-2.0)
        # @param max_tokens [Integer, nil] maximum output tokens
        # @param options [Hash] additional API parameters
        def initialize(
          model:,
          input:,
          instructions: nil,
          previous_response_id: nil,
          tools: [],
          tool_config: {},
          temperature: nil,
          max_tokens: nil,
          **options
        )
          @model = model
          @input = input
          @instructions = instructions
          @previous_response_id = previous_response_id
          @tools = tools || []
          @tool_config = tool_config || {}
          @temperature = temperature
          @max_tokens = max_tokens
          @options = options
        end

        # Build the request parameters
        #
        # @return [Hash] API parameters ready for the Responses API
        def build
          params = {
            model: model,
            input: input
          }

          if multi_turn_request?
            build_multi_turn_params(params)
          else
            build_single_turn_params(params)
          end

          add_web_search_includes(params)
          merge_additional_options(params)

          params
        end

        private

        # @return [Boolean] true if this is a multi-turn conversation
        def multi_turn_request?
          previous_response_id.present?
        end

        # Build parameters for multi-turn conversations
        #
        # When using previous_response_id:
        # - Temperature and other sampling parameters are inherited
        # - Instructions can be passed to override the previous instructions
        # - Tools MUST be passed on every request (not inherited)
        #
        # @param params [Hash] the parameters hash to modify
        def build_multi_turn_params(params)
          params[:previous_response_id] = previous_response_id
          params[:instructions] = instructions if instructions.present?
          params[:tools] = tool_formatter.format if tools.any?
        end

        # Build parameters for single-turn requests
        #
        # @param params [Hash] the parameters hash to modify
        def build_single_turn_params(params)
          params[:instructions] = instructions if instructions.present?
          params[:temperature] = temperature if temperature
          params[:max_output_tokens] = max_tokens if max_tokens
          params[:tools] = tool_formatter.format if tools.any?
        end

        # Add web search source includes if web search tool is enabled
        #
        # This adds action.sources to web_search_call items in the response
        #
        # @param params [Hash] the parameters hash to modify
        def add_web_search_includes(params)
          return unless tool_formatter.has_web_search_tool? && !multi_turn_request?

          params[:include] = [ "web_search_call.action.sources" ]
        end

        # Merge additional options, handling include arrays properly
        #
        # @param params [Hash] the parameters hash to modify
        def merge_additional_options(params)
          # Combine include arrays to prevent overwriting
          if options[:include].present?
            params[:include] = (params[:include] || []) + Array(options[:include])
            params[:include].uniq!
          end

          params.merge!(options.except(:timeout, :include))
        end

        # @return [ToolFormatter] formatter for tools
        def tool_formatter
          @tool_formatter ||= ToolFormatter.new(tools: tools, tool_config: tool_config)
        end
      end
    end
  end
end
