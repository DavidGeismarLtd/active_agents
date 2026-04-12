# frozen_string_literal: true

module PromptTracker
  module LlmClients
    class RubyLlmService
      DEFAULT_MAX_TOKENS = 4096

      def self.call(model:, prompt:, system: nil, tools: [], tool_config: {},
                    mock_function_outputs: nil, function_executor: nil, temperature: nil, max_tokens: nil, **options)
        new(
          model: model, prompt: prompt, system: system, tools: tools, tool_config: tool_config,
          mock_function_outputs: mock_function_outputs, function_executor: function_executor,
          temperature: temperature, max_tokens: max_tokens, **options
        ).call
      end

      def self.build_chat(model:, system: nil, tools: [], tool_config: {},
                          mock_function_outputs: nil, function_executor: nil, temperature: nil, max_tokens: nil)
        new(
          model: model, prompt: "", system: system, tools: tools, tool_config: tool_config,
          mock_function_outputs: mock_function_outputs, function_executor: function_executor,
          temperature: temperature, max_tokens: max_tokens
        ).build_chat
      end

      # Execute block with dynamic RubyLLM configuration.
      # Temporarily sets the global RubyLLM config with per-tenant API keys,
      # then restores the original values after the block completes.
      # This ensures providers properly pick up the API keys during HTTP calls.
      #
      # @yield [RubyLLM] The RubyLLM module with config applied
      # @return [Object] Result of the block
      def self.with_dynamic_config(&block)
        config = PromptTracker.configuration

        if config.dynamic_configuration?
          llm_config = config.ruby_llm_config
          original = {}
          llm_config.each { |key, _| original[key] = RubyLLM.config.public_send(key) }
          llm_config.each { |key, value| RubyLLM.config.public_send("#{key}=", value) }
          begin
            yield(RubyLLM)
          ensure
            original.each { |key, value| RubyLLM.config.public_send("#{key}=", value) }
          end
        else
          yield(RubyLLM)
        end
      end

      attr_reader :model, :prompt, :system, :tools, :tool_config,
                  :mock_function_outputs, :function_executor, :temperature, :max_tokens, :options

      def initialize(model:, prompt:, system: nil, tools: [], tool_config: {},
                     mock_function_outputs: nil, function_executor: nil, temperature: nil, max_tokens: nil, **options)
        @model = model
        @prompt = prompt
        @system = system
        @tools = tools || []
        @tool_config = tool_config || {}
        @mock_function_outputs = mock_function_outputs
        @function_executor = function_executor
        @temperature = temperature
        @max_tokens = max_tokens
        @options = options
        @tool_calls_log = []
      end

      def call
        log_request
        with_dynamic_config do |llm|
          chat = build_chat_instance(llm)
          response = chat.ask(prompt)
          log_response(response)
          LlmResponseNormalizers::RubyLlm.normalize(response, chat_messages: chat.messages)
        end
      end

      def build_chat
        with_dynamic_config { |llm| build_chat_instance(llm) }
      end

      private

      def build_chat_instance(llm)
        chat = llm.chat(model: model)
        chat = chat.with_instructions(system) if system.present?
        chat = chat.with_temperature(temperature) if temperature
        chat = apply_params(chat)
        chat = apply_tools(chat)
        chat = apply_callbacks(chat)
        chat
      end

      def with_dynamic_config(&block)
        self.class.with_dynamic_config(&block)
      end

      def apply_params(chat)
        return chat unless max_tokens
        chat.with_params { |p| p[:max_tokens] = max_tokens }
      end

      def apply_tools(chat)
        return chat unless tools.include?(:functions) && tool_config["functions"].present?
        tool_classes = RubyLlm::DynamicToolBuilder.build(
          tool_config: tool_config,
          mock_function_outputs: mock_function_outputs,
          executor: function_executor
        )
        tool_classes.each { |tc| chat = chat.with_tool(tc.new) }
        chat
      end

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
