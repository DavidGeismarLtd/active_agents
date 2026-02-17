# frozen_string_literal: true

module PromptTracker
  # Service for running a conversation turn in the playground.
  # Delegates all LLM API calls to LlmClientService.
  #
  # Usage:
  #   result = RunPlaygroundConversationService.call(
  #     content: "What's the weather in Berlin?",
  #     system_prompt: "You are a helpful assistant.",
  #     user_prompt_template: "Answer: {{question}}",
  #     model_config: { provider: "openai", api: "responses", model: "gpt-4o" },
  #     conversation_state: { messages: [], previous_response_id: nil },
  #     variables: { question: "How are you?" }
  #   )
  #
  class RunPlaygroundConversationService
    class ConversationError < StandardError; end

    Result = Struct.new(:success?, :content, :tools_used, :usage, :conversation_state, :error, keyword_init: true)

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
      @conversation_state = (conversation_state || {}).with_indifferent_access
      @variables = variables || {}
    end

    def call
      validate_input!

      response = execute_via_llm_client
      new_state = build_new_state(response)

      Result.new(
        success?: true,
        content: response[:text],
        tools_used: extract_tools_used(response),
        usage: response[:usage],
        conversation_state: new_state
      )
    rescue ConversationError => e
      Result.new(success?: false, error: e.message)
    end

    private

    def validate_input!
      raise ConversationError, "Message content is required" if content.blank?
      raise ConversationError, "Model configuration is required" if model_config.blank?
      raise ConversationError, "Provider is required" if model_config[:provider].blank?
      raise ConversationError, "API is required" if model_config[:api].blank?
    end

    def execute_via_llm_client
      api_type = ApiTypes.from_config(model_config[:provider], model_config[:api])

      case api_type
      when :openai_responses
        execute_responses_api
      when :openai_assistants
        execute_assistants_api
      when :anthropic_messages
        execute_anthropic_messages
      else
        execute_chat_completion
      end
    end

    def execute_responses_api
      previous_response_id = conversation_state[:previous_response_id]

      if previous_response_id.present?
        # Follow-up turn: use previous_response_id for context
        OpenaiResponseService.call_with_context(
          model: model_config[:model],
          input: content,
          previous_response_id: previous_response_id,
          tools: parse_tools,
          tool_config: model_config[:tool_config],
          temperature: model_config[:temperature]
        )
      else
        # First turn: pass instructions and user message
        OpenaiResponseService.call(
          model: model_config[:model],
          input: content,
          instructions: rendered_system_prompt,
          tools: parse_tools,
          tool_config: model_config[:tool_config],
          temperature: model_config[:temperature]
        )
      end
    end

    def execute_assistants_api
      OpenaiAssistantService.call(
        assistant_id: model_config[:assistant_id],
        user_message: content
      )
    end

    def execute_anthropic_messages
      # Build messages array with conversation history
      messages = build_anthropic_messages
      AnthropicMessagesService.call(
        model: model_config[:model],
        messages: messages,
        system: rendered_system_prompt,
        tools: parse_tools,
        tool_config: model_config[:tool_config],
        temperature: model_config[:temperature]
      )
    end

    def execute_chat_completion
      # For chat completion APIs, build the full prompt with conversation history
      LlmClientService.call(
        provider: model_config[:provider],
        api: model_config[:api],
        model: model_config[:model],
        prompt: build_chat_prompt,
        temperature: model_config[:temperature],
        system_prompt: rendered_system_prompt
      )
    end

    def rendered_system_prompt
      return nil if system_prompt.blank?
      return system_prompt if variables.blank?

      TemplateRenderer.new(system_prompt).render(variables)
    end

    def build_chat_prompt
      parts = []
      parts << rendered_user_prompt_template if rendered_user_prompt_template.present?
      parts << content
      parts.join("\n\n")
    end

    # Build messages array for Anthropic Messages API
    #
    # Anthropic is stateless, so we must include the full conversation history.
    # The messages array alternates between user and assistant roles.
    #
    # @return [Array<Hash>] messages array for Anthropic API
    def build_anthropic_messages
      messages = []

      # Add previous conversation history from state
      previous_messages = conversation_state[:messages] || []
      previous_messages.each do |msg|
        messages << { role: msg["role"] || msg[:role], content: msg["content"] || msg[:content] }
      end

      # Add current user message
      messages << { role: "user", content: content }

      messages
    end

    def rendered_user_prompt_template
      return nil if user_prompt_template.blank?
      return user_prompt_template if variables.blank?

      TemplateRenderer.new(user_prompt_template).render(variables)
    end

    def parse_tools
      tools_config = model_config[:tools]
      return [] if tools_config.blank?

      Array(tools_config).map(&:to_sym)
    end

    def extract_tools_used(response)
      return [] unless response[:tool_calls].present?

      response[:tool_calls].map { |tool_call| { type: tool_call[:type] } }
    end

    def build_new_state(response)
      ConversationStateBuilder.call(
        previous_state: conversation_state,
        user_message: content,
        response: response
      )
    end
  end
end
