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
  # Also supports OpenAI Assistants API:
  # - When provider is "openai_assistants", routes to OpenaiAssistantService
  # - Assistant IDs start with "asst_"
  #
  # @example Call any LLM
  #   response = LlmClientService.call(
  #     provider: "openai",
  #     model: "gpt-4",
  #     prompt: "Hello, world!",
  #     temperature: 0.7
  #   )
  #   response[:text]  # => "Hello! How can I help you today?"
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
    # @param provider [String] the LLM provider (used to detect OpenAI Assistants)
    # @param model [String] the model name or assistant ID
    # @param prompt [String] the prompt text
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer] maximum tokens to generate
    # @param response_schema [Hash, nil] optional JSON Schema for structured output
    # @param options [Hash] additional provider-specific options
    # @return [Hash] response with :text, :usage, :model, :raw keys
    # @raise [ApiError] if API call fails
    def self.call(provider:, model:, prompt:, temperature: 0.7, max_tokens: nil, response_schema: nil, **options)
      # Route to OpenAI Assistants API if provider is openai_assistants
      if provider.to_s == "openai_assistants" || model.to_s.start_with?("asst_")
        return OpenaiAssistantService.call(
          assistant_id: model,
          prompt: prompt,
          timeout: options[:timeout] || 60
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
    # @param model [String] the model name
    # @param prompt [String] the prompt text
    # @param schema [Class] a RubyLLM::Schema subclass
    # @param temperature [Float] the temperature (0.0-2.0)
    # @param max_tokens [Integer] maximum tokens to generate
    # @param options [Hash] additional provider-specific options
    # @return [Hash] response with :text (JSON string), :usage, :model, :raw keys
    # @raise [ApiError] if API call fails
    def self.call_with_schema(provider:, model:, prompt:, schema:, temperature: 0.7, max_tokens: nil, **options)
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

    # Normalize RubyLLM response to our standard format
    #
    # @param response [RubyLLM::Message] the RubyLLM message object
    # @return [Hash] normalized response
    def normalize_response(response)
      {
        text: response.content,
        usage: extract_usage(response),
        model: response.model_id,
        raw: response
      }
    end

    # Normalize RubyLLM schema response to our standard format
    #
    # @param response [RubyLLM::Message] the RubyLLM message object with structured content
    # @return [Hash] normalized response with JSON text
    def normalize_schema_response(response)
      {
        text: response.content.to_json,  # Convert structured hash to JSON string
        usage: extract_usage(response),
        model: response.model_id,
        raw: response
      }
    end

    # Extract usage information from RubyLLM response
    #
    # @param response [RubyLLM::Message] the RubyLLM message object
    # @return [Hash] usage hash with token counts
    def extract_usage(response)
      {
        prompt_tokens: response.input_tokens || 0,
        completion_tokens: response.output_tokens || 0,
        total_tokens: (response.input_tokens || 0) + (response.output_tokens || 0)
      }
    end
  end
end
