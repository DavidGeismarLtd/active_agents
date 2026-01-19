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

      params[:instructions] = system_prompt if system_prompt.present?
      params[:previous_response_id] = previous_response_id if previous_response_id.present?
      params[:temperature] = temperature if temperature
      params[:max_output_tokens] = max_tokens if max_tokens
      params[:tools] = format_tools(tools) if tools.any?

      # Merge any additional options
      params.merge!(options.except(:timeout))

      params
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
    # @return [Hash] formatted file_search tool
    def format_file_search_tool
      file_search_config = tool_config.dig("file_search") || tool_config.dig(:file_search) || {}
      vector_store_ids = file_search_config["vector_store_ids"] || file_search_config[:vector_store_ids] || []

      tool_hash = { type: "file_search" }
      tool_hash[:vector_store_ids] = vector_store_ids if vector_store_ids.any?
      tool_hash
    end

    # Format custom function definitions into API format
    #
    # @return [Array<Hash>] formatted function tools
    def format_function_tools
      functions = tool_config.dig("functions") || tool_config.dig(:functions) || []

      functions.map do |func|
        {
          type: "function",
          name: func["name"] || func[:name],
          description: func["description"] || func[:description] || "",
          parameters: func["parameters"] || func[:parameters] || {},
          strict: func["strict"] || func[:strict] || false
        }
      end
    end

    # Normalize Response API response to standard format
    #
    # @param response [Hash] raw API response
    # @return [Hash] normalized response
    def normalize_response(response)
      {
        text: extract_text(response),
        response_id: response["id"],
        usage: extract_usage(response),
        model: response["model"],
        tool_calls: extract_tool_calls(response),
        raw: response
      }
    end

    # Extract text content from response output
    #
    # @param response [Hash] raw API response
    # @return [String] extracted text
    def extract_text(response)
      output = response["output"] || []

      # Find message output items and extract text content
      text_parts = output.flat_map do |item|
        next [] unless item["type"] == "message"

        content = item["content"] || []
        content.filter_map do |content_item|
          content_item.dig("text") if content_item["type"] == "output_text"
        end
      end

      text_parts.join("\n")
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

    # Extract tool calls from response output
    #
    # @param response [Hash] raw API response
    # @return [Array<Hash>] tool calls
    def extract_tool_calls(response)
      output = response["output"] || []

      output.select do |item|
        %w[function_call web_search_call file_search_call code_interpreter_call].include?(item["type"])
      end
    end
  end
end
