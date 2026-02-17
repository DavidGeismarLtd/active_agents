# frozen_string_literal: true

module PromptTracker
  module Anthropic
    module Messages
      # Builds request parameters for Anthropic Messages API.
      #
      # Key differences from OpenAI:
      # - `max_tokens` is REQUIRED (no default)
      # - `system` is a separate parameter (not in messages array)
      # - Tool format uses `input_schema` instead of `parameters`
      # - No `previous_response_id` - conversations are stateless (client manages history)
      #
      # @example Build parameters for a request
      #   builder = RequestBuilder.new(
      #     model: "claude-3-5-sonnet-20241022",
      #     messages: [{ role: "user", content: "Hello!" }],
      #     system: "You are a helpful assistant.",
      #     max_tokens: 4096
      #   )
      #   params = builder.build
      #
      class RequestBuilder
        DEFAULT_MAX_TOKENS = 4096

        attr_reader :model, :messages, :system, :tools, :tool_config,
                    :temperature, :max_tokens, :options

        # @param model [String] the model ID (e.g., "claude-3-5-sonnet-20241022")
        # @param messages [Array<Hash>] array of message objects { role:, content: }
        # @param system [String, nil] system prompt (separate from messages in Anthropic)
        # @param tools [Array<Symbol>] tool symbols (:functions, :web_search)
        # @param tool_config [Hash] configuration for tools
        # @param temperature [Float, nil] the temperature (0.0-1.0)
        # @param max_tokens [Integer] maximum output tokens (REQUIRED for Anthropic)
        # @param options [Hash] additional API parameters
        def initialize(
          model:,
          messages:,
          system: nil,
          tools: [],
          tool_config: {},
          temperature: nil,
          max_tokens: DEFAULT_MAX_TOKENS,
          **options
        )
          @model = model
          @messages = messages
          @system = system
          @tools = tools || []
          @tool_config = tool_config || {}
          @temperature = temperature
          @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
          @options = options
        end

        # Build the request parameters
        #
        # @return [Hash] API parameters ready for Anthropic Messages API
        def build
          params = {
            model: model,
            messages: format_messages,
            max_tokens: max_tokens
          }

          # System prompt is a separate parameter in Anthropic API
          params[:system] = system if system.present?

          # Temperature (optional, defaults to 1.0 in Anthropic)
          params[:temperature] = temperature if temperature

          # Tools (formatted via ToolFormatter)
          params[:tools] = tool_formatter.format if tool_formatter.any?

          # Merge any additional options
          params.merge!(options.except(:timeout))

          params
        end

        private

        # Format messages for Anthropic API
        #
        # Ensures messages are in the correct format:
        # [{ role: "user", content: "..." }, { role: "assistant", content: "..." }]
        #
        # @return [Array<Hash>] formatted messages
        def format_messages
          messages.map do |msg|
            # Handle both string keys and symbol keys
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]

            { role: role.to_s, content: content.to_s }
          end
        end

        # @return [ToolFormatter] formatter for tools
        def tool_formatter
          @tool_formatter ||= ToolFormatter.new(tools: tools, tool_config: tool_config)
        end
      end
    end
  end
end
