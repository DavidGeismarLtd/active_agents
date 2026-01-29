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
      # Extract error details from the response body
      error_body = JSON.parse(e.response[:body]) rescue {}
      error_message = error_body.dig("error", "message") || e.message

      raise ResponseApiError, "OpenAI Responses API error: #{error_message}\nRequest parameters: #{build_parameters.inspect}"
    end

    private

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    def client
      @client ||= begin
        require "openai"
        api_key = PromptTracker.configuration.api_key_for(:openai) || ENV["OPENAI_API_KEY"]
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
      # - Tools are inherited from the first call (don't pass again)
      # - Temperature and other sampling parameters are inherited (don't pass again)
      # - Instructions can be passed to override the previous instructions
      if previous_response_id.present?
        params[:previous_response_id] = previous_response_id
        # Only add instructions if explicitly provided (to override previous instructions)
        params[:instructions] = system_prompt if system_prompt.present?
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
        {
          type: "function",
          name: func["name"],
          description: func["description"] || "",
          parameters: func["parameters"] || {},
          strict: func["strict"] || false
        }
      end
    end

    # Normalize Response API response to standard format using ResponseApiNormalizer
    #
    # This delegates to ResponseApiNormalizer to ensure consistent normalization
    # across the application and proper extraction of tool results (web_search_results,
    # code_interpreter_results, file_search_results).
    #
    # @param response [Hash] raw API response
    # @return [Hash] normalized response with:
    #   - :text [String] extracted text content
    #   - :response_id [String] the response ID for conversation continuity
    #   - :usage [Hash] token usage information
    #   - :model [String] the model used
    #   - :tool_calls [Array<Hash>] all tool calls (mixed types)
    #   - :web_search_results [Array<Hash>] web search tool calls
    #   - :code_interpreter_results [Array<Hash>] code interpreter tool calls
    #   - :file_search_results [Array<Hash>] file search tool calls
    #   - :raw [Hash] the original API response
    def normalize_response(response)
      # Use ResponseApiNormalizer to extract tool results properly
      normalizer = Evaluators::Normalizers::ResponseApiNormalizer.new
      normalized = normalizer.normalize_single_response(response)

      # Extract usage information (not handled by normalizer)
      usage = extract_usage(response)

      # Combine normalizer output with additional fields needed by executors
      {
        text: normalized[:text],
        response_id: response["id"],
        usage: usage,
        model: response["model"],
        tool_calls: normalized[:tool_calls],
        web_search_results: extract_web_search_results(response),
        code_interpreter_results: extract_code_interpreter_results(response),
        file_search_results: extract_file_search_results(response),
        raw: response
      }
    end

    # Extract usage information
    #
    # @param response [Hash] raw API response
    # @return [Hash] usage hash with token counts
    def extract_usage(response)
      usage = response["usage"] || {}
      {
        prompt_tokens: usage["input_tokens"] || 0,
        completion_tokens: usage["output_tokens"] || 0,
        total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
      }
    end

    # Extract web search results from response output
    #
    # @param response [Hash] raw API response
    # @return [Array<Hash>] web search results
    def extract_web_search_results(response)
      normalizer = Evaluators::Normalizers::ResponseApiNormalizer.new
      normalizer.send(:extract_web_search_results, response["output"] || [])
    end

    # Extract code interpreter results from response output
    #
    # @param response [Hash] raw API response
    # @return [Array<Hash>] code interpreter results
    def extract_code_interpreter_results(response)
      normalizer = Evaluators::Normalizers::ResponseApiNormalizer.new
      normalizer.send(:extract_code_interpreter_results, response["output"] || [])
    end

    # Extract file search results from response output
    #
    # @param response [Hash] raw API response
    # @return [Array<Hash>] file search results
    def extract_file_search_results(response)
      normalizer = Evaluators::Normalizers::ResponseApiNormalizer.new
      normalizer.send(:extract_file_search_results, response["output"] || [])
    end
  end
end
