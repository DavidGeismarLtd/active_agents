# frozen_string_literal: true

module PromptTracker
  # Service for calling OpenAI Responses API.
  #
  # The Responses API is OpenAI's most advanced interface for generating model responses.
  # It supports:
  # - Text and image inputs, and text outputs
  # - Stateful conversations via previous_response_id
  # - Built-in tools (web_search, file_search, code_interpreter)
  # - Function calling
  #
  # This service is a thin orchestrator that delegates to:
  # - Openai::Responses::RequestBuilder for building API parameters
  # - Openai::Responses::ToolFormatter for formatting tools
  # - LlmResponseNormalizers::Openai::Responses for normalizing responses
  #
  # @example Single-turn call
  #   response = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     input: "What's the weather in Berlin?",
  #     instructions: "You are a helpful assistant."
  #   )
  #   response[:text]  # => "I don't have access to real-time weather..."
  #
  # @example With web search tool
  #   response = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     input: "What's the latest news about Ruby on Rails?",
  #     tools: [:web_search]
  #   )
  #
  # @example Multi-turn conversation
  #   response1 = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     input: "My name is Alice"
  #   )
  #   response2 = OpenaiResponseService.call_with_context(
  #     model: "gpt-4o",
  #     input: "What's my name?",
  #     previous_response_id: response1[:response_id]
  #   )
  #
  class OpenaiResponseService
    class ResponseApiError < StandardError; end

    # Make a single-turn Response API call
    #
    # @param model [String] the model ID (e.g., "gpt-4o")
    # @param input [String, Array] the user message or array of input items
    # @param instructions [String, nil] optional system instructions
    # @param tools [Array<Symbol>] Response API tools (:web_search, :file_search, :code_interpreter, :functions)
    # @param tool_config [Hash] configuration for tools (e.g., file_search vector_store_ids, function definitions)
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer, nil] maximum output tokens
    # @param options [Hash] additional API parameters
    # @return [NormalizedLlmResponse] normalized response
    def self.call(model:, input:, instructions: nil, tools: [], tool_config: {}, temperature: 0.7, max_tokens: nil, **options)
      new(
        model: model,
        input: input,
        instructions: instructions,
        tools: tools,
        tool_config: tool_config,
        temperature: temperature,
        max_tokens: max_tokens,
        **options
      ).call
    end

    # Make a multi-turn Response API call (continues a conversation)
    #
    # @param model [String] the model ID
    # @param input [String, Array] the user message or array of input items
    # @param previous_response_id [String] the ID from a previous response
    # @param tools [Array<Symbol>] Response API tools
    # @param tool_config [Hash] configuration for tools
    # @param options [Hash] additional API parameters
    # @return [NormalizedLlmResponse] normalized response
    def self.call_with_context(model:, input:, previous_response_id:, tools: [], tool_config: {}, **options)
      new(
        model: model,
        input: input,
        previous_response_id: previous_response_id,
        tools: tools,
        tool_config: tool_config,
        **options
      ).call
    end

    attr_reader :model, :input, :instructions, :previous_response_id,
                :tools, :tool_config, :temperature, :max_tokens, :options

    def initialize(model:, input:, instructions: nil, previous_response_id: nil,
                   tools: [], tool_config: {}, temperature: 0.7, max_tokens: nil, **options)
      @model = model
      @input = input
      @instructions = instructions
      @previous_response_id = previous_response_id
      @tools = tools
      @tool_config = tool_config || {}
      @temperature = temperature
      @max_tokens = max_tokens
      @options = options
    end

    # Execute the Response API call
    #
    # @return [Hash] normalized response
    def call
      response = client.responses.create(parameters: build_parameters)

      normalize_response(response)
    rescue Faraday::BadRequestError => e
      # Extract detailed error information from the response body
      error_body = JSON.parse(e.response[:body]) rescue {}
      error_message = error_body.dig("error", "message") || e.message
      error_type = error_body.dig("error", "type")
      error_code = error_body.dig("error", "code")
      error_param = error_body.dig("error", "param")

      # Build detailed error message
      detailed_error = "OpenAI Responses API error (#{e.response[:status]}): #{error_message}"
      detailed_error += "\nError Type: #{error_type}" if error_type
      detailed_error += "\nError Code: #{error_code}" if error_code
      detailed_error += "\nError Param: #{error_param}" if error_param
      detailed_error += "\n\nFull error body: #{error_body.inspect}"
      detailed_error += "\n\nRequest parameters: #{redact_sensitive_params(build_parameters).inspect}"

      raise ResponseApiError, detailed_error
    end

    private

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    def client
      @client ||= begin
        require "openai"
        api_key = PromptTracker.configuration.api_key_for(:openai)
        raise ResponseApiError, "OpenAI API key not configured" if api_key.blank?

        OpenAI::Client.new(access_token: api_key)
      end
    end

    # Build parameters for the API call using RequestBuilder
    #
    # @return [Hash] API parameters
    def build_parameters
      request_builder.build
    end

    # @return [Openai::Responses::RequestBuilder] request builder instance
    def request_builder
      @request_builder ||= Openai::Responses::RequestBuilder.new(
        model: model,
        input: input,
        instructions: instructions,
        previous_response_id: previous_response_id,
        tools: tools,
        tool_config: tool_config,
        temperature: temperature,
        max_tokens: max_tokens,
        **options
      )
    end

    # Normalize Response API response to NormalizedLlmResponse format
    #
    # @param response [Hash] raw API response
    # @return [NormalizedResponse] normalized response
    def normalize_response(response)
      LlmResponseNormalizers::Openai::Responses.normalize(response)
    end

    # Redact sensitive fields from parameters before logging
    #
    # This prevents leaking full prompts, tool definitions, and other sensitive
    # data into logs and error tracking systems.
    #
    # @param params [Hash] the request parameters
    # @return [Hash] redacted parameters safe for logging
    def redact_sensitive_params(params)
      redacted = params.dup

      # Truncate long text fields to prevent log bloat
      if redacted[:input].present?
        redacted[:input] = truncate_text(redacted[:input], max_length: 100)
      end

      if redacted[:instructions].present?
        redacted[:instructions] = truncate_text(redacted[:instructions], max_length: 100)
      end

      # Redact tool definitions (can be very large and contain sensitive logic)
      if redacted[:tools].present?
        redacted[:tools] = redacted[:tools].map do |tool|
          if tool.is_a?(Hash)
            # Keep tool type but redact function definitions
            if tool[:type] == "function" || tool["type"] == "function"
              { type: "function", name: tool[:name] || tool["name"], definition: "[REDACTED]" }
            else
              { type: tool[:type] || tool["type"] }
            end
          else
            tool # Keep simple symbols like :web_search
          end
        end
      end

      redacted
    end

    # Truncate text to a maximum length with ellipsis
    #
    # @param text [String] the text to truncate
    # @param max_length [Integer] maximum length before truncation
    # @return [String] truncated text
    def truncate_text(text, max_length: 100)
      return text if text.length <= max_length
      "#{text[0...max_length]}... [truncated, total length: #{text.length}]"
    end
  end
end
