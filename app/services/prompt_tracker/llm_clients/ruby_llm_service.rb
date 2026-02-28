# frozen_string_literal: true

module PromptTracker
  module LlmClients
    # Unified service for all RubyLLM-compatible LLM providers.
    #
    # This service uses RubyLLM's native tool handling for automatic tool execution.
    # It supports OpenAI Chat Completions, Anthropic Claude, Google Gemini, DeepSeek,
    # OpenRouter, Ollama, and any other RubyLLM-supported provider.
    #
    # @example Basic call
    #   response = LlmClients::RubyLlmService.call(
    #     model: "gpt-4o",
    #     prompt: "Hello!",
    #     system: "You are a helpful assistant."
    #   )
    #   response.text  # => "Hello! How can I help you today?"
    #
    # @example With tools (automatic execution)
    #   response = LlmClients::RubyLlmService.call(
    #     model: "claude-3-5-sonnet-20241022",
    #     prompt: "What's the weather in Berlin?",
    #     tools: [:functions],
    #     tool_config: { "functions" => [{ "name" => "get_weather", ... }] },
    #     mock_function_outputs: { "get_weather" => { "temp" => 72 } }
    #   )
    #   # RubyLLM automatically: calls tool → executes → sends result → returns final response
    #
    class RubyLlmService
      DEFAULT_MAX_TOKENS = 4096

      # Make a single-turn LLM call with optional tools
      #
      # @param model [String] Model ID (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")
      # @param prompt [String] User message
      # @param system [String, nil] System prompt
      # @param tools [Array<Symbol>] Tools to enable (e.g., [:functions])
      # @param tool_config [Hash] Tool configuration with functions array
      # @param mock_function_outputs [Hash, nil] Mock outputs for tool execution
      # @param temperature [Float, nil] Temperature (0.0-2.0)
      # @param max_tokens [Integer, nil] Maximum output tokens
      # @return [NormalizedLlmResponse] Normalized response
      def self.call(model:, prompt:, system: nil, tools: [], tool_config: {},
                    mock_function_outputs: nil, temperature: nil, max_tokens: nil, **options)
        new(
          model: model,
          prompt: prompt,
          system: system,
          tools: tools,
          tool_config: tool_config,
          mock_function_outputs: mock_function_outputs,
          temperature: temperature,
          max_tokens: max_tokens,
          **options
        ).call
      end

      # Build a configured RubyLLM::Chat instance without making a call
      #
      # Use this when you need the chat instance for multi-turn conversations
      # or want to control when/how the LLM is called.
      #
      # @param model [String] Model ID (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")
      # @param system [String, nil] System prompt
      # @param tools [Array<Symbol>] Tools to enable (e.g., [:functions])
      # @param tool_config [Hash] Tool configuration with functions array
      # @param mock_function_outputs [Hash, nil] Mock outputs for tool execution
      # @param temperature [Float, nil] Temperature (0.0-2.0)
      # @param max_tokens [Integer, nil] Maximum output tokens
      # @return [RubyLLM::Chat] Configured chat instance
      def self.build_chat(model:, system: nil, tools: [], tool_config: {},
                          mock_function_outputs: nil, temperature: nil, max_tokens: nil)
        new(
          model: model,
          prompt: "", # Not used for chat building
          system: system,
          tools: tools,
          tool_config: tool_config,
          mock_function_outputs: mock_function_outputs,
          temperature: temperature,
          max_tokens: max_tokens
        ).build_chat
      end

      attr_reader :model, :prompt, :system, :tools, :tool_config,
                  :mock_function_outputs, :temperature, :max_tokens, :options

      def initialize(model:, prompt:, system: nil, tools: [], tool_config: {},
                     mock_function_outputs: nil, temperature: nil, max_tokens: nil, **options)
        @model = model
        @prompt = prompt
        @system = system
        @tools = tools || []
        @tool_config = tool_config || {}
        @mock_function_outputs = mock_function_outputs
        @temperature = temperature
        @max_tokens = max_tokens
        @options = options
        @tool_calls_log = []
      end

      # Execute the LLM call
      #
      # @return [NormalizedLlmResponse] Normalized response
      def call
        log_request

        with_dynamic_config do
          chat = build_chat_instance
          response = chat.ask(prompt)

          log_response(response)
          LlmResponseNormalizers::RubyLlm.normalize(response)
        end
      end

      # Build a RubyLLM chat instance with all configurations.
      # When called externally, wraps in dynamic config.
      # When called from #call, dynamic config is already applied.
      #
      # @return [RubyLLM::Chat] Configured chat instance
      def build_chat
        with_dynamic_config { build_chat_instance }
      end

      private

      # Build the actual chat instance (internal, without config wrapper)
      #
      # @return [RubyLLM::Chat] Configured chat instance
      def build_chat_instance
        chat = RubyLLM.chat(model: model)
        chat = chat.with_instructions(system) if system.present?
        chat = chat.with_temperature(temperature) if temperature
        chat = apply_params(chat)
        chat = apply_tools(chat)
        chat = apply_callbacks(chat)
        chat
      end

      # Execute block with dynamic RubyLLM configuration if configuration_provider is set.
      # Uses RubyLLM.with_config to apply per-request API keys.
      # If already inside a with_config block, just yields to avoid nesting.
      #
      # @yield Block to execute with dynamic config
      # @return [Object] Result of the block
      def with_dynamic_config(&block)
        config = PromptTracker.configuration

        if config.dynamic_configuration?
          RubyLLM.with_config(**config.ruby_llm_config, &block)
        else
          yield
        end
      end

      # Apply additional parameters (max_tokens)
      #
      # @param chat [RubyLLM::Chat] Chat instance
      # @return [RubyLLM::Chat] Chat with params applied
      def apply_params(chat)
        return chat unless max_tokens

        chat.with_params { |p| p[:max_tokens] = max_tokens }
      end

      # Apply tools using RubyLLM's native tool handling
      #
      # @param chat [RubyLLM::Chat] Chat instance
      # @return [RubyLLM::Chat] Chat with tools applied
      def apply_tools(chat)
        return chat unless tools.include?(:functions) && tool_config["functions"].present?

        # Build dynamic RubyLLM::Tool classes from JSON config
        tool_classes = RubyLlm::DynamicToolBuilder.build(
          tool_config: tool_config,
          mock_function_outputs: mock_function_outputs
        )

        # Register each tool with the chat
        tool_classes.each do |tool_class|
          chat = chat.with_tool(tool_class.new)
        end
        chat
      end

      # Apply event callbacks for logging
      #
      # @param chat [RubyLLM::Chat] Chat instance
      # @return [RubyLLM::Chat] Chat with callbacks applied
      def apply_callbacks(chat)
        chat
          .on_tool_call { |tc| log_tool_call(tc) }
          .on_tool_result { |result| log_tool_result(result) }
      end

      def log_request
        tools_count = tool_config["functions"]&.length || 0
        Rails.logger.info "[LlmClients::RubyLlmService] Request: model=#{model}, " \
                          "system=#{system.present?}, tools=#{tools_count}, " \
                          "temperature=#{temperature}, max_tokens=#{max_tokens}"
      end

      def log_response(response)
        tool_calls_count = response.tool_calls&.length || 0
        Rails.logger.info "[LlmClients::RubyLlmService] Response: model=#{response.model_id}, " \
                          "input_tokens=#{response.input_tokens}, output_tokens=#{response.output_tokens}, " \
                          "tool_calls=#{tool_calls_count}"
      end

      def log_tool_call(tool_call)
        @tool_calls_log << tool_call
        Rails.logger.info "[LlmClients::RubyLlmService] Tool call: #{tool_call.name} with #{tool_call.arguments}"
      end

      def log_tool_result(result)
        Rails.logger.info "[LlmClients::RubyLlmService] Tool result: #{result.to_s.truncate(200)}"
      end
    end
  end
end
