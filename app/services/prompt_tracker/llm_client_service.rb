# frozen_string_literal: true

module PromptTracker
  # Service for making LLM API calls to various providers using RubyLLM.
  #
  # This is a thin wrapper around RubyLLM that provides a consistent interface
  # for the PromptTracker application.
  #
  # Supports all RubyLLM providers:
  # - OpenAI (GPT-4, GPT-3.5, etc.)
  # - Anthropic (Claude models)
  # - Google (Gemini models)
  # - AWS Bedrock
  # - OpenRouter
  # - DeepSeek
  # - Ollama (local models)
  # - And many more...
  #
  # Also supports specialized OpenAI APIs:
  # - OpenAI Responses API: provider="openai", api="responses"
  # - OpenAI Assistants API: provider="openai", api="assistants"
  #
  # @example Call standard chat completion
  #   response = LlmClientService.call(
  #     provider: "openai",
  #     api: "chat_completions",
  #     model: "gpt-4",
  #     prompt: "Hello, world!",
  #     temperature: 0.7
  #   )
  #   response[:text]  # => "Hello! How can I help you today?"
  #
  # @example Call OpenAI Responses API
  #   response = LlmClientService.call(
  #     provider: "openai",
  #     api: "responses",
  #     model: "gpt-4o",
  #     prompt: "Search the web for latest news",
  #     tools: [:web_search]
  #   )
  #
  # @example Call OpenAI Assistants API
  #   response = LlmClientService.call(
  #     provider: "openai",
  #     api: "assistants",
  #     model: "gpt-4o",
  #     prompt: "What's the weather?",
  #     assistant_id: "asst_abc123"
  #   )
  #
  # @example Call with structured output
  #   schema = LlmJudgeSchema.for_criteria(criteria: ["clarity"], score_min: 0, score_max: 100)
  #   response = LlmClientService.call_with_schema(
  #     provider: "openai",
  #     model: "gpt-4o",
  #     prompt: "Evaluate this response",
  #     schema: schema
  #   )
  #
  class LlmClientService
    # Custom error classes
    class UnsupportedProviderError < StandardError; end
    class MissingApiKeyError < StandardError; end
    class ApiError < StandardError; end
    class UnsupportedModelError < StandardError; end

    # Call an LLM API
    #
    # @param provider [String] the LLM provider (e.g., "openai", "anthropic")
    # @param api [String, nil] the API type (e.g., "chat_completions", "responses", "assistants")
    # @param model [String] the model name
    # @param prompt [String] the prompt text
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer] maximum tokens to generate
    # @param response_schema [Hash, nil] optional JSON Schema for structured output
    # @param options [Hash] additional provider-specific options (e.g., assistant_id for Assistants API)
    # @return [Hash] response with :text, :usage, :model, :raw keys
    # @raise [ApiError] if API call fails
    def self.call(provider:, api:, model:, prompt:, temperature: 0.7, max_tokens: nil, response_schema: nil, **options)
      # Determine the API type using ApiTypes module
      api_type = ApiTypes.from_config(provider, api)

      # Route to specialized services for OpenAI Responses/Assistants APIs
      if api_type == :openai_responses || api_type == :openai_assistants
        return route_to_specialized_service(
          api_type: api_type,
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: max_tokens,
          **options
        )
      end

      # If response_schema is provided, convert to RubyLLM::Schema and use structured output
      if response_schema.present?
        ruby_llm_schema = JsonSchemaAdapter.to_ruby_llm_schema(response_schema)
        return new(
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: max_tokens,
          schema: ruby_llm_schema,
          **options
        ).call_with_schema
      end

      # Standard chat completion via RubyLLM
      new(model: model, prompt: prompt, temperature: temperature, max_tokens: max_tokens, **options).call
    end

    # Call an LLM API with structured output using RubyLLM::Schema
    #
    # @param provider [String] the LLM provider (ignored - RubyLLM auto-detects from model name)
    # @param api [String, nil] the API type (optional, ignored for structured output)
    # @param model [String] the model name
    # @param prompt [String] the prompt text
    # @param schema [Class] a RubyLLM::Schema subclass
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer] maximum tokens to generate
    # @param options [Hash] additional provider-specific options
    # @return [Hash] response with :text (JSON string), :usage, :model, :raw keys
    # @raise [ApiError] if API call fails
    def self.call_with_schema(provider:, api: nil, model:, prompt:, schema:, temperature: 0.7, max_tokens: nil, **options)
      new(
        model: model,
        prompt: prompt,
        temperature: temperature,
        max_tokens: max_tokens,
        schema: schema,
        **options
      ).call_with_schema
    end

    attr_reader :model, :prompt, :temperature, :max_tokens, :schema, :options

    def initialize(model:, prompt:, temperature: 0.7, max_tokens: nil, schema: nil, **options)
      @model = model
      @prompt = prompt
      @temperature = temperature
      @max_tokens = max_tokens
      @schema = schema
      @options = options
    end

    # Execute the API call using RubyLLM
    #
    # @return [Hash] response with :text, :usage, :model, :raw keys
    def call
      chat = build_chat
      response = chat.ask(prompt)

      normalize_response(response)
    end

    # Execute the API call with structured output using RubyLLM::Schema
    #
    # @return [Hash] response with :text (JSON string), :usage, :model, :raw keys
    def call_with_schema
      raise ArgumentError, "Schema is required for call_with_schema" unless schema

      chat = build_chat.with_schema(schema)
      response = chat.ask(prompt)

      normalize_schema_response(response)
    end

    private

    # Route to specialized OpenAI services (Responses API or Assistants API)
    #
    # @param api_type [Symbol] the API type (:openai_responses or :openai_assistants)
    # @param model [String] the model name
    # @param prompt [String] the prompt text
    # @param temperature [Float] the temperature
    # @param max_tokens [Integer] maximum tokens to generate
    # @param options [Hash] additional options
    # @return [Hash] response from specialized service
    def self.route_to_specialized_service(api_type:, model:, prompt:, temperature:, max_tokens:, **options)
      case api_type
      when :openai_responses
        OpenaiResponseService.call(
          model: model,
          user_prompt: prompt,
          system_prompt: options[:system_prompt],
          tools: options[:tools] || [],
          temperature: temperature,
          max_tokens: max_tokens,
          **options.except(:system_prompt, :tools)
        )
      when :openai_assistants
        OpenaiAssistantService.call(
          assistant_id: options[:assistant_id],
          user_message: prompt,
          timeout: options[:timeout] || 60
        )
      end
    end

    # Build a RubyLLM chat instance with configured parameters
    #
    # @return [RubyLLM::Chat] configured chat instance
    def build_chat
      chat = RubyLLM.chat(model: model)

      # Apply temperature if specified
      chat = chat.with_temperature(temperature) if temperature

      # Apply max_tokens and other options via with_params
      if max_tokens || options.any?
        chat = chat.with_params do |p|
          p[:max_tokens] = max_tokens if max_tokens
          options.each { |k, v| p[k] = v } if options.any?
        end
      end

      chat
    end

    # Normalize RubyLLM response to NormalizedResponse format
    #
    # @param response [RubyLLM::Message] the RubyLLM message object
    # @return [NormalizedResponse] normalized response
    def normalize_response(response)
      LlmResponseNormalizers::Openai::ChatCompletions.normalize(response)
    end

    # Normalize RubyLLM schema response to NormalizedResponse format
    #
    # @param response [RubyLLM::Message] the RubyLLM message object with structured content
    # @return [NormalizedResponse] normalized response with JSON text
    def normalize_schema_response(response)
      NormalizedResponse.new(
        text: response.content.to_json,  # Convert structured hash to JSON string
        usage: {
          prompt_tokens: response.input_tokens || 0,
          completion_tokens: response.output_tokens || 0,
          total_tokens: (response.input_tokens || 0) + (response.output_tokens || 0)
        },
        model: response.model_id,
        tool_calls: [],
        file_search_results: [],
        web_search_results: [],
        code_interpreter_results: [],
        api_metadata: {},
        raw_response: response
      )
    end
  end
end
