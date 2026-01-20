# frozen_string_literal: true

module PromptTracker
  # Service for executing playground prompts with Response API support.
  #
  # Handles:
  # - Single-turn and multi-turn conversations
  # - Response API tool usage (web_search, file_search, code_interpreter)
  # - Conversation state management
  #
  # For OpenAI Responses API:
  # - `instructions` = system_prompt + rendered user_prompt_template (combined prompt instructions)
  # - `input` = content (the user's live message in the playground)
  #
  # @example Execute a single message
  #   result = PlaygroundExecuteService.call(
  #     content: "What's the weather in Berlin?",
  #     system_prompt: "You are a helpful assistant.",
  #     user_prompt_template: "Answer this question: {{question}}",
  #     model_config: { provider: "openai", api: "responses", model: "gpt-4o" }
  #   )
  #
  class PlaygroundExecuteService
    class ExecuteError < StandardError; end

    Result = Struct.new(:success?, :content, :tools_used, :usage, :conversation_state, :error, keyword_init: true)

    # Execute a playground prompt
    #
    # @param content [String] the user message content (sent as `input` to Response API)
    # @param system_prompt [String, nil] optional system instructions
    # @param user_prompt_template [String, nil] optional user prompt template (combined with system_prompt for `instructions`)
    # @param model_config [Hash] model configuration (provider, model, tools, temperature)
    # @param conversation_state [Hash] current conversation state from session
    # @param variables [Hash] template variables (for rendering prompts)
    # @return [Result] execution result
    def self.call(content:, system_prompt: nil, user_prompt_template: nil, model_config: {}, conversation_state: {}, variables: {})
      new(
        content: content,
        system_prompt: system_prompt,
        user_prompt_template: user_prompt_template,
        model_config: model_config,
        conversation_state: conversation_state,
        variables: variables
      ).call
    end

    attr_reader :content, :system_prompt, :user_prompt_template, :model_config, :conversation_state, :variables

    def initialize(content:, system_prompt: nil, user_prompt_template: nil, model_config: {}, conversation_state: {}, variables: {})
      @content = content
      @system_prompt = system_prompt
      @user_prompt_template = user_prompt_template
      @model_config = model_config.with_indifferent_access
      @conversation_state = conversation_state.with_indifferent_access
      @variables = variables
    end

    def call
      validate_input!

      response = execute_api_call
      new_state = build_new_conversation_state(response)

      Result.new(
        success?: true,
        content: response[:text],
        tools_used: extract_tools_used(response),
        usage: response[:usage],
        conversation_state: new_state
      )
    rescue ExecuteError => e
      Result.new(success?: false, error: e.message)
    end

    private

    def validate_input!
      raise ExecuteError, "Message content is required" if content.blank?
    end

    def execute_api_call
      api = model_config[:api]

      # Route based on API
      case api.to_s
      when "responses"
        execute_response_api
      when "assistants"
        execute_assistant_api
      else
        execute_chat_completion
      end
    end

    def execute_response_api
      previous_response_id = conversation_state[:previous_response_id]
      tools = parse_tools(model_config[:tools])
      tool_config = model_config[:tool_config]

      if previous_response_id.present?
        OpenaiResponseService.call_with_context(
          model: model_config[:model],
          user_prompt: content,
          previous_response_id: previous_response_id,
          tools: tools,
          tool_config: tool_config,
          temperature: model_config[:temperature]
        )
      else
        # For first turn: combine system_prompt + user_prompt_template into instructions
        # The content (user's live message) goes to input
        OpenaiResponseService.call(
          model: model_config[:model],
          user_prompt: content,
          system_prompt: combined_instructions,
          tools: tools,
          tool_config: tool_config,
          temperature: model_config[:temperature]
        )
      end
    end

    def execute_assistant_api
      OpenaiAssistantService.call(
        assistant_id: model_config[:model],
        prompt: content
      )
    end

    def execute_chat_completion
      LlmClientService.call(
        provider: model_config[:provider],
        api: model_config[:api],
        model: model_config[:model],
        prompt: build_chat_prompt,
        temperature: model_config[:temperature]
      )
    end

    # Combines system_prompt and user_prompt_template into a single instructions string
    # for the OpenAI Responses API.
    #
    # @return [String, nil] the combined instructions
    def combined_instructions
      parts = []
      parts << rendered_system_prompt if rendered_system_prompt.present?
      parts << rendered_user_prompt_template if rendered_user_prompt_template.present?

      parts.empty? ? nil : parts.join("\n\n")
    end

    def rendered_system_prompt
      return nil if system_prompt.blank?
      return system_prompt if variables.blank?

      TemplateRenderer.new(system_prompt).render(variables)
    end

    def rendered_user_prompt_template
      return nil if user_prompt_template.blank?
      return user_prompt_template if variables.blank?

      TemplateRenderer.new(user_prompt_template).render(variables)
    end

    def build_chat_prompt
      # For chat completion, combine system and user prompts
      parts = []
      parts << "System: #{rendered_system_prompt}" if rendered_system_prompt.present?
      parts << rendered_user_prompt_template if rendered_user_prompt_template.present?
      parts << content
      parts.join("\n\n")
    end

    def parse_tools(tools_config)
      return [] if tools_config.blank?

      Array(tools_config).map(&:to_sym)
    end

    def extract_tools_used(response)
      return [] unless response[:tool_calls].present?

      response[:tool_calls].map do |tool_call|
        { type: tool_call[:type] }
      end
    end

    def build_new_conversation_state(response)
      messages = conversation_state[:messages] || []

      # Add user message
      messages << {
        role: "user",
        content: content,
        created_at: Time.current.iso8601
      }

      # Add assistant message
      messages << {
        role: "assistant",
        content: response[:text],
        tools_used: extract_tools_used(response),
        created_at: Time.current.iso8601
      }

      {
        messages: messages,
        previous_response_id: response[:response_id],
        started_at: conversation_state[:started_at] || Time.current.iso8601
      }
    end
  end
end
