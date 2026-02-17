# frozen_string_literal: true

module PromptTracker
  # Service for calling Anthropic Messages API using ruby_llm.
  #
  # The Messages API is Anthropic's primary interface for Claude models.
  # This service uses ruby_llm under the hood for simplicity while providing
  # a consistent PromptTracker interface.
  #
  # Key differences from OpenAI:
  # - `max_tokens` is REQUIRED (no default in Anthropic API)
  # - `system` is a separate parameter (not in messages array)
  # - Stateless: no `previous_response_id` - client manages conversation history
  #
  # @example Single-turn call
  #   response = AnthropicMessagesService.call(
  #     model: "claude-3-5-sonnet-20241022",
  #     messages: [{ role: "user", content: "Hello!" }],
  #     system: "You are a helpful assistant.",
  #     max_tokens: 4096
  #   )
  #   response.text  # => "Hello! How can I help you today?"
  #
  # @example With tools
  #   response = AnthropicMessagesService.call(
  #     model: "claude-3-5-sonnet-20241022",
  #     messages: [{ role: "user", content: "What's the weather in Berlin?" }],
  #     tools: [:functions],
  #     tool_config: { "functions" => [{ "name" => "get_weather", ... }] }
  #   )
  #
  class AnthropicMessagesService
    class MessagesApiError < StandardError; end

    DEFAULT_MAX_TOKENS = 4096

    # Make a Messages API call
    #
    # @param model [String] the model ID (e.g., "claude-3-5-sonnet-20241022")
    # @param messages [Array<Hash>] array of message objects { role:, content: }
    # @param system [String, nil] system prompt (separate from messages)
    # @param tools [Array<Symbol>] tools to enable (:functions, :web_search)
    # @param tool_config [Hash] configuration for tools
    # @param temperature [Float, nil] the temperature (0.0-1.0)
    # @param max_tokens [Integer] maximum output tokens (REQUIRED for Anthropic)
    # @param options [Hash] additional API parameters
    # @return [NormalizedLlmResponse] normalized response
    def self.call(model:, messages:, system: nil, tools: [], tool_config: {}, temperature: nil, max_tokens: DEFAULT_MAX_TOKENS, **options)
      new(
        model: model,
        messages: messages,
        system: system,
        tools: tools,
        tool_config: tool_config,
        temperature: temperature,
        max_tokens: max_tokens,
        **options
      ).call
    end

    attr_reader :model, :messages, :system, :tools, :tool_config,
                :temperature, :max_tokens, :options

    def initialize(model:, messages:, system: nil, tools: [], tool_config: {}, temperature: nil, max_tokens: DEFAULT_MAX_TOKENS, **options)
      @model = model
      @messages = messages
      @system = system
      @tools = tools || []
      @tool_config = tool_config || {}
      @temperature = temperature
      @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
      @options = options
    end

    # Execute the Messages API call
    #
    # @return [NormalizedLlmResponse] normalized response
    def call
      log_request

      chat = build_chat
      response = chat.ask(formatted_prompt)

      log_response(response)
      LlmResponseNormalizers::RubyLlm.normalize(response)
    end

    private

    # Build a RubyLLM chat instance with configured parameters
    #
    # @return [RubyLLM::Chat] configured chat instance
    def build_chat
      chat = RubyLLM.chat(model: model)

      # Apply system prompt if provided
      chat = chat.with_instructions(system) if system.present?

      # Apply temperature if specified
      chat = chat.with_temperature(temperature) if temperature

      # Apply max_tokens and tools via with_params
      # We use with_params for tools because ruby_llm's with_tools() expects
      # RubyLLM::Tool class instances, but we have raw tool definition hashes.
      # with_params lets us pass tools directly to the API payload.
      chat = chat.with_params do |p|
        p[:max_tokens] = max_tokens
        formatted_tools = build_formatted_tools
        p[:tools] = formatted_tools if formatted_tools.any?
      end

      chat
    end

    # Build formatted tools array for the API payload
    #
    # @return [Array<Hash>] formatted tools in Anthropic API format
    def build_formatted_tools
      return [] unless tools.any?

      tool_formatter = Anthropic::Messages::ToolFormatter.new(
        tools: tools,
        tool_config: tool_config
      )
      tool_formatter.format
    end

    # Format the prompt from messages array
    #
    # For simple single-turn, extract the user message content
    # For multi-turn, we'll need to handle conversation history differently
    #
    # @return [String] the prompt to send
    def formatted_prompt
      # For now, extract the last user message
      last_user_msg = messages.reverse.find { |m| (m[:role] || m["role"]) == "user" }
      last_user_msg ? (last_user_msg[:content] || last_user_msg["content"]) : ""
    end

    # Log the request details before making the API call
    def log_request
      tools_count = build_formatted_tools.length
      Rails.logger.info "[AnthropicMessagesService] Request: model=#{model}, messages=#{messages.length}, " \
                        "system=#{system.present?}, tools=#{tools_count}, max_tokens=#{max_tokens}"
    end

    # Log the response details after receiving the API response
    #
    # @param response [RubyLLM::Message] the RubyLLM response
    def log_response(response)
      tool_calls_count = response.respond_to?(:tool_calls) && response.tool_calls.present? ? response.tool_calls.length : 0
      Rails.logger.info "[AnthropicMessagesService] Response: model=#{response.model_id}, " \
                        "input_tokens=#{response.input_tokens}, output_tokens=#{response.output_tokens}, " \
                        "tool_calls=#{tool_calls_count}, stop_reason=#{response.respond_to?(:stop_reason) ? response.stop_reason : 'N/A'}"
    end
  end
end
