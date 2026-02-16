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
  # @example Single-turn call
  #   response = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     user_prompt: "What's the weather in Berlin?",
  #     system_prompt: "You are a helpful assistant."
  #   )
  #   response[:text]  # => "I don't have access to real-time weather..."
  #
  # @example With web search tool
  #   response = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     user_prompt: "What's the latest news about Ruby on Rails?",
  #     tools: [:web_search]
  #   )
  #
  # @example Multi-turn conversation
  #   response1 = OpenaiResponseService.call(
  #     model: "gpt-4o",
  #     user_prompt: "My name is Alice"
  #   )
  #   response2 = OpenaiResponseService.call_with_context(
  #     model: "gpt-4o",
  #     user_prompt: "What's my name?",
  #     previous_response_id: response1[:response_id]
  #   )
  #
  class OpenaiResponseService
    class ResponseApiError < StandardError; end

    # Make a single-turn Response API call
    #
    # @param model [String] the model ID (e.g., "gpt-4o")
    # @param user_prompt [String] the user message content
    # @param system_prompt [String, nil] optional system instructions
    # @param tools [Array<Symbol>] Response API tools (:web_search, :file_search, :code_interpreter, :functions)
    # @param tool_config [Hash] configuration for tools (e.g., file_search vector_store_ids, function definitions)
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer, nil] maximum output tokens
    # @param options [Hash] additional API parameters
    # @return [Hash] response with :text, :response_id, :usage, :model, :tool_calls, :raw keys
    def self.call(model:, user_prompt:, system_prompt: nil, tools: [], tool_config: {}, temperature: 0.7, max_tokens: nil, **options)
      new(
        model: model,
        user_prompt: user_prompt,
        system_prompt: system_prompt,
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
    # @param user_prompt [String] the user message content
    # @param previous_response_id [String] the ID from a previous response
    # @param tools [Array<Symbol>] Response API tools
    # @param tool_config [Hash] configuration for tools
    # @param options [Hash] additional API parameters
    # @return [Hash] response with :text, :response_id, :usage, :model, :tool_calls, :raw keys
    def self.call_with_context(model:, user_prompt:, previous_response_id:, tools: [], tool_config: {}, **options)
      new(
        model: model,
        user_prompt: user_prompt,
        previous_response_id: previous_response_id,
        tools: tools,
        tool_config: tool_config,
        **options
      ).call
    end

    attr_reader :model, :user_prompt, :system_prompt, :previous_response_id,
                :tools, :tool_config, :temperature, :max_tokens, :options

    def initialize(model:, user_prompt:, system_prompt: nil, previous_response_id: nil,
                   tools: [], tool_config: {}, temperature: 0.7, max_tokens: nil, **options)
      @model = model
      @user_prompt = user_prompt
      @system_prompt = system_prompt
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

    # Build parameters for the API call
    #
    # @return [Hash] API parameters
    def build_parameters
      params = {
        model: model,
        input: user_prompt
      }

      # When using previous_response_id for multi-turn conversations:
      # - Temperature and other sampling parameters are inherited (don't pass again)
      # - Instructions can be passed to override the previous instructions
      # - Tools MUST be passed on every request (not inherited)
      if previous_response_id.present?
        params[:previous_response_id] = previous_response_id
        # Only add instructions if explicitly provided (to override previous instructions)
        params[:instructions] = system_prompt if system_prompt.present?
        # Tools must be passed on all requests, not just the first one
        params[:tools] = format_tools(tools) if tools.any?
      else
        # First call: include all parameters
        params[:instructions] = system_prompt if system_prompt.present?
        params[:temperature] = temperature if temperature
        params[:max_output_tokens] = max_tokens if max_tokens
        params[:tools] = format_tools(tools) if tools.any?
      end

      # Include web search sources if web search tool is enabled
      # This adds action.sources to web_search_call items in the response
      if has_web_search_tool? && previous_response_id.nil?
        params[:include] = [ "web_search_call.action.sources" ]
      end

      # Merge any additional options, combining include arrays to prevent overwriting
      if options[:include].present?
        params[:include] = (params[:include] || []) + Array(options[:include])
        params[:include].uniq!
      end
      params.merge!(options.except(:timeout, :include))

      params
    end

    # Check if web search tool is enabled
    #
    # Tools are always passed as symbols (e.g., :web_search) or hashes with symbol keys
    # (e.g., { type: "web_search_preview" }). Callers convert from database strings to symbols.
    #
    # @return [Boolean] true if web search tool is present
    def has_web_search_tool?
      tools.any? do |tool|
        tool.is_a?(Symbol) && [ :web_search, :web_search_preview ].include?(tool) ||
        tool.is_a?(Hash) && [ "web_search", "web_search_preview" ].include?(tool[:type])
      end
    end

    # Format tool symbols into API format
    #
    # @param tools [Array<Symbol, Hash>] tool symbols or custom tool hashes
    # @return [Array<Hash>] formatted tools
    def format_tools(tools)
      formatted = []

      tools.each do |tool|
        # Allow passing custom tool hashes directly
        if tool.is_a?(Hash)
          formatted << tool
          next
        end

        case tool.to_sym
        when :web_search
          formatted << { type: "web_search_preview" }
        when :file_search
          formatted << format_file_search_tool
        when :code_interpreter
          formatted << { type: "code_interpreter" }
        when :functions
          # Functions are added separately, not as a single tool
          formatted.concat(format_function_tools)
        else
          formatted << { type: tool.to_s }
        end
      end

      formatted
    end

    # Format file_search tool with optional vector_store_ids
    #
    # tool_config comes from database JSONB and always uses string keys
    #
    # @return [Hash] formatted file_search tool
    def format_file_search_tool
      file_search_config = tool_config["file_search"] || {}
      vector_store_ids = file_search_config["vector_store_ids"] || []

      # OpenAI Responses API has a hard limit of 2 vector stores
      # Enforce this limit as a fallback for backward compatibility
      vector_store_ids = vector_store_ids.first(2) if vector_store_ids.length > 2

      tool_hash = { type: "file_search" }
      tool_hash[:vector_store_ids] = vector_store_ids if vector_store_ids.any?
      tool_hash
    end

    # Format custom function definitions into API format
    #
    # tool_config and function hashes come from database JSONB and always use string keys
    #
    # @return [Array<Hash>] formatted function tools
    def format_function_tools
      functions = tool_config["functions"] || []

      functions.map do |func|
        tool_hash = {
          type: "function",
          name: func["name"],
          description: func["description"] || "",
          parameters: func["parameters"] || {}
        }

        # Handle strict mode:
        # - If strict is explicitly true, include it (requires additionalProperties: false in schema)
        # - If strict is explicitly false, include it to opt out of auto-normalization
        # - If strict is nil/omitted, don't include it (Responses API will auto-normalize to strict mode)
        if func["strict"] == true || func["strict"] == false
          tool_hash[:strict] = func["strict"]
        end

        tool_hash
      end
    end

    # Normalize Response API response to NormalizedResponse format
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
