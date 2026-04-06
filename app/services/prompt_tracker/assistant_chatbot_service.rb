# frozen_string_literal: true

module PromptTracker
  # Service for the global assistant chatbot.
  #
  # Handles message processing, LLM interaction, and function execution.
  # Reuses the AgentConversation model for conversation storage but with
  # a virtual "assistant" deployed agent scope.
  #
  # @example Process a user message
  #   result = AssistantChatbotService.call(
  #     message: "Create a prompt called Test",
  #     session_id: "session_123",
  #     context: { page_type: :agents_list }
  #   )
  #
  class AssistantChatbotService
    Result = Struct.new(:success?, :response, :links, :suggestions, :pending_action, :error, keyword_init: true)

    def self.call(message:, session_id:, context: {})
      new(message, session_id, context).call
    end

      def self.execute_function(session_id:, function_name:, arguments:, context: {})
      Rails.logger.info "[AssistantChatbot] Class method execute_function called: #{function_name}"
        new(nil, session_id, context || {}).execute_function(function_name, arguments)
    end

    def self.generate_suggestions(context)
      Rails.logger.debug "[AssistantChatbot] Class method generate_suggestions called"
      new(nil, nil, context).generate_suggestions
    end

    def initialize(message, session_id, context)
      @message = message
      @session_id = session_id
      @context = context
      @config = PromptTracker.configuration.assistant_chatbot
        @assistant_mode = nil
    end

    def call
      Rails.logger.info "[AssistantChatbot] ═══ NEW REQUEST ═══"
      Rails.logger.info "[AssistantChatbot] Session ID: #{@session_id}"
      Rails.logger.info "[AssistantChatbot] User message: #{@message.inspect}"
      Rails.logger.info "[AssistantChatbot] Context: #{@context.inspect}"

          # 1. Load conversation history
          conversation_history = load_conversation_history
        Rails.logger.info "[AssistantChatbot] Loaded #{conversation_history.length} messages from history"
        Rails.logger.debug "[AssistantChatbot] History preview: #{conversation_history.first(3).inspect}..." if conversation_history.any?

          # 2. Determine assistant mode using router + state
          @assistant_mode = determine_assistant_mode(conversation_history)
        Rails.logger.info "[AssistantChatbot] Assistant mode: #{assistant_mode.inspect}"

          # 3. If we could not route to a specialized assistant, return
          #    a focused apology instead of falling back to a generic
          #    Q&A mode. The assistant is intentionally scoped to
          #    specific workflows.
          if assistant_mode == :default
            Rails.logger.info "[AssistantChatbot] No specialized assistant matched – returning apology"

            save_to_conversation(role: "user", content: @message)

            apology = <<~MSG.strip
	            I’m designed to help you create agents, create datasets, create tests, run tests, and deploy agents.
	            I couldn’t match your request to any of these workflows, so I don’t know how to answer it.
            MSG

            save_to_conversation(role: "assistant", content: apology)

            return Result.new(
              success?: true,
              response: apology,
              links: [],
              suggestions: generate_suggestions,
              pending_action: nil
            )
          end

          # 4. Build system prompt with context / wizard
          system_prompt = build_system_prompt
        Rails.logger.debug "[AssistantChatbot] System prompt length: #{system_prompt.length} chars"

      # 5. Call LLM with conversation history + current message
      Rails.logger.info "[AssistantChatbot] Calling LLM..."
        llm_response = call_llm(system_prompt, conversation_history, @message)
      Rails.logger.info "[AssistantChatbot] LLM response type: #{llm_response.keys.inspect}"

      # 5. Check if LLM wants to execute a function
      if llm_response[:function_call]
        # Function call detected - determine if it needs confirmation
        function_name = llm_response[:function_call][:name]
        arguments = llm_response[:function_call][:arguments]

        Rails.logger.info "[AssistantChatbot] 🔧 Function call detected: #{function_name}"
        Rails.logger.info "[AssistantChatbot] Arguments: #{arguments.inspect}"

          # Always record the user's request
          save_to_conversation(role: "user", content: @message)

        if requires_confirmation?(function_name)
          Rails.logger.info "[AssistantChatbot] ⚠️  Function requires confirmation - returning pending_action"

            # Return pending action for confirmation
            confirmation_message = build_confirmation_message(function_name, arguments)
            save_to_conversation(role: "assistant", content: confirmation_message)

          Rails.logger.info "[AssistantChatbot] Saved user + assistant confirmation to history"

          Result.new(
            success?: true,
              response: confirmation_message,
            links: [],
            suggestions: [],
            pending_action: {
              function_name: function_name,
              arguments: arguments,
                confirmation_message: confirmation_message
            }
          )
        else
          Rails.logger.info "[AssistantChatbot] ✅ Function does NOT require confirmation - executing immediately"
          # Execute query function immediately
          execution_result = execute_function(function_name, arguments)
          execution_result
        end
      else
        Rails.logger.info "[AssistantChatbot] 💬 Normal text response (no function call)"
        Rails.logger.debug "[AssistantChatbot] Response text: #{llm_response[:text].inspect}"

          # Normal text response
          save_to_conversation(role: "user", content: @message)
          save_to_conversation(role: "assistant", content: llm_response[:text])

        Rails.logger.info "[AssistantChatbot] Saved user + assistant messages to history"

        Result.new(
          success?: true,
          response: llm_response[:text],
          links: [],
          suggestions: generate_suggestions,
          pending_action: nil
        )
      end
    end

    def execute_function(function_name, arguments)
      Rails.logger.info "[AssistantChatbot] ═══ EXECUTING FUNCTION ═══"
      Rails.logger.info "[AssistantChatbot] Function: #{function_name}"
      Rails.logger.info "[AssistantChatbot] Arguments: #{arguments.inspect}"

      # Execute the function via function executor
      executor_result = AssistantChatbot::FunctionExecutor.call(
        function_name: function_name,
        arguments: arguments,
        context: @context
      )

      Rails.logger.info "[AssistantChatbot] Executor result success?: #{executor_result.success?}"

      if executor_result.success?
        Rails.logger.info "[AssistantChatbot] ✅ Function executed successfully"
        Rails.logger.debug "[AssistantChatbot] Result message: #{executor_result.message.inspect}"
        Rails.logger.debug "[AssistantChatbot] Links: #{executor_result.links.inspect}"

        # Save to conversation
        save_to_conversation(role: "function", content: "Executed #{function_name}")
        save_to_conversation(role: "assistant", content: executor_result.message)

        # Update conversation context with created entities
        update_conversation_context(function_name, executor_result.entities_created || {})

        Result.new(
          success?: true,
          response: executor_result.message,
          links: executor_result.links || [],
          suggestions: generate_suggestions,
          pending_action: nil
        )
      else
        Rails.logger.error "[AssistantChatbot] ❌ Function execution failed: #{executor_result.error}"

        Result.new(
          success?: false,
          response: nil,
          links: [],
          suggestions: [],
          pending_action: nil,
          error: executor_result.error
        )
      end
    end

    def generate_suggestions
      Rails.logger.debug "[AssistantChatbot] Generating suggestions for context: #{@context.inspect}"

      # Generate context-aware suggestions based on current page
      suggestions = AssistantChatbot::ContextDetector.suggestions_for(@context)

        Rails.logger.debug "[AssistantChatbot] Generated #{suggestions&.length || 0} suggestions"
        Rails.logger.debug "[AssistantChatbot] Suggestions: #{suggestions.inspect}"

        suggestions
    end

    private

    def load_conversation_history
        return [] if @session_id.blank?

        key = conversation_cache_key
      Rails.logger.debug "[AssistantChatbot] Loading conversation from cache key: #{key}"

        messages = Rails.cache.read(key)

      if messages.nil?
        Rails.logger.debug "[AssistantChatbot] No cached conversation found - starting fresh"
        return []
      end

      Rails.logger.debug "[AssistantChatbot] Found #{messages.length} cached messages"

        Array(messages).map do |msg|
          {
            role: (msg[:role] || msg["role"]),
            content: (msg[:content] || msg["content"])
          }
        end
    end

    def save_to_conversation(role:, content:)
        return if @session_id.blank? || content.blank?

      Rails.logger.debug "[AssistantChatbot] Saving message to conversation: role=#{role}, content_length=#{content.length}"

        conversation_settings = @config[:conversation] || {}
        max_messages = conversation_settings[:max_messages] || 50
        ttl = conversation_settings[:ttl] || 24.hours

        key = conversation_cache_key
        messages = Rails.cache.read(key) || []

      previous_count = messages.length

        messages << {
          role: role,
          content: content,
          timestamp: Time.current.iso8601
        }
        messages = messages.last(max_messages)

      Rails.logger.debug "[AssistantChatbot] Conversation now has #{messages.length} messages (was #{previous_count}, max: #{max_messages})"
      Rails.logger.debug "[AssistantChatbot] Writing to cache with TTL: #{ttl}"

        Rails.cache.write(key, messages, expires_in: ttl)
    end

    def update_conversation_context(action, entities)
      # Update conversation metadata with created entities
      # TODO: Implement context tracking
    end

    def conversation_cache_key
      self.class.conversation_cache_key_for(@session_id)
    end

    def self.conversation_cache_key_for(session_id)
      "assistant_chatbot_conversation:#{session_id}"
      end

      def assistant_state_cache_key
      return nil if @session_id.blank?
      "assistant_chatbot_state:#{@session_id}"
    end

    def load_assistant_state
      key = assistant_state_cache_key
      return {} if key.nil?

      state = Rails.cache.read(key)
      state.is_a?(Hash) ? state.symbolize_keys : {}
    end

    def save_assistant_state(state)
      key = assistant_state_cache_key
      return if key.nil?

      ttl = (@config.dig(:conversation, :ttl) || 24.hours)
      Rails.cache.write(key, state, expires_in: ttl)
    end

    def build_router_conversation_summary(history, max_messages: 4)
      recent = Array(history).last(max_messages)
      return nil if recent.empty?

      recent.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        "#{role.to_s.capitalize}: #{content}"
      end.join("\n")
    end

    def determine_assistant_mode(conversation_history)
      state = load_assistant_state

      router_context = (@context || {}).merge(
        conversation_summary: build_router_conversation_summary(conversation_history),
        active_assistant: state[:active_assistant]
      )

      mode = AssistantChatbot::Router.assistant_for(message: @message.to_s, context: router_context)

      chosen_mode =
        if mode == :default && state[:active_assistant]
          Rails.logger.info "[AssistantChatbot] Router returned :default but active assistant #{state[:active_assistant].inspect} present \\u2013 continuing existing wizard"
          state[:active_assistant]
        else
          mode
        end

      if chosen_mode && chosen_mode != :default
        state[:active_assistant] = chosen_mode
        save_assistant_state(state)
      end

      chosen_mode || :default
    end

    def build_system_prompt
      case assistant_mode
      when :test_runner_wizard
        Rails.logger.debug("[AssistantChatbot] Using TestRunnerWizardAssistant system prompt")
        test_runner_wizard_assistant.system_prompt
      when :test_creator_wizard
        Rails.logger.debug("[AssistantChatbot] Using TestCreatorWizardAssistant system prompt")
        test_creator_wizard_assistant.system_prompt
      when :dataset_wizard
        Rails.logger.debug("[AssistantChatbot] Using DatasetWizardAssistant system prompt")
        dataset_wizard_assistant.system_prompt
      when :deployment_wizard
        Rails.logger.debug("[AssistantChatbot] Using DeploymentWizardAssistant system prompt")
        deployment_wizard_assistant.system_prompt
      when :agent_creation_wizard
        Rails.logger.debug("[AssistantChatbot] Using AgentCreationWizardAssistant system prompt")
        agent_creation_wizard_assistant.system_prompt
      else
        # Generic system prompt is no longer used in normal flows. When no
        # specialized wizard applies, the service returns an apology.
        "You are the PromptTracker Assistant."
      end
    end

    def call_llm(system_prompt, history, message)
      Rails.logger.debug "[AssistantChatbot] ═══ CALL_LLM ═══"

      model_config = PromptTracker.configuration.assistant_chatbot_model
      provider = model_config[:provider]
      api = model_config[:api]
      model = model_config[:model]
      temperature = model_config[:temperature]

      Rails.logger.debug "[AssistantChatbot] Provider: #{provider}, API: #{api}, Model: #{model}, Temperature: #{temperature}"

      history_lines = Array(history).filter_map do |msg|
        role = msg[:role]
        content = msg[:content].to_s.strip
        next if content.empty?

        case role
        when "user"
          "User: #{content}"
        when "assistant"
          "Assistant: #{content}"
        end
      end

      Rails.logger.debug "[AssistantChatbot] Built #{history_lines.length} history lines from #{history.length} history messages"

      prompt = if history_lines.any?
        <<~PROMPT.strip
          Here is the recent conversation between the user and the assistant:

          #{history_lines.join("\n\n")}

          Now the user says:
          User: #{message}
        PROMPT
      else
        message
      end

      Rails.logger.debug "[AssistantChatbot] Final prompt length: #{prompt.length} chars"
      Rails.logger.debug "[AssistantChatbot] Final prompt preview: #{prompt[0..200]}..." if prompt.length > 200

      registry = AssistantChatbot::ToolRegistry.new
      allowed_tool_names = current_wizard_assistant&.allowed_tool_names
      raw_tool_defs = registry.tool_definitions_for(allowed_tool_names)

      tool_defs = raw_tool_defs.map(&:deep_stringify_keys)
      Rails.logger.info "[AssistantChatbot] Built #{tool_defs.length} tool definitions: #{tool_defs.map { |t| t['name'] }.inspect}"

      tool_config = { "functions" => tool_defs }
      tools = tool_defs.any? ? [ :functions ] : []

      Rails.logger.info "[AssistantChatbot] Calling LlmClientService with tools: #{tools.inspect}"

      normalized = LlmClientService.call(
        provider: provider,
        api: api,
        model: model,
        prompt: prompt,
        temperature: temperature,
        response_schema: nil,
        system_prompt: system_prompt,
        tools: tools,
        tool_config: tool_config
      )

      Rails.logger.info "[AssistantChatbot] LlmClientService returned successfully"
      Rails.logger.info "[AssistantChatbot] Normalized response - text length: #{normalized.text&.length || 0}, tool_calls: #{normalized.tool_calls.length}"

        if normalized.tool_calls.present?
          Rails.logger.info "[AssistantChatbot] Found #{normalized.tool_calls.length} tool call(s), using last one"

          tool_call = normalized.tool_calls.last
          Rails.logger.debug "[AssistantChatbot] Tool call details: #{tool_call.inspect}"

          args = (tool_call[:arguments] || {}).with_indifferent_access

          Rails.logger.info "[AssistantChatbot] Returning function_call: #{tool_call[:function_name]}"

          return (
            {
              function_call: {
                name: tool_call[:function_name],
                arguments: args
              }
            }
          )
        end

        if test_runner_wizard_mode? || test_creator_wizard_mode? || dataset_wizard_mode? || deployment_wizard_mode? || agent_creation_wizard_mode?
        function_call =
          if test_runner_wizard_mode?
            extract_run_tests_function_call_from_text(normalized.text)
          elsif test_creator_wizard_mode?
            extract_generate_tests_function_call_from_text(normalized.text)
          elsif dataset_wizard_mode?
            extract_create_dataset_function_call_from_text(normalized.text)
          elsif deployment_wizard_mode?
            extract_deploy_agent_function_call_from_text(normalized.text)
          elsif agent_creation_wizard_mode?
            extract_create_prompt_function_call_from_text(normalized.text)
          end

        return function_call if function_call

        Rails.logger.info "[AssistantChatbot] Wizard response without JSON plan - returning text"
        return ({ text: normalized.text })
        end

      Rails.logger.info "[AssistantChatbot] No tool calls - returning text response"
      { text: normalized.text }
    end

        def build_tool_definitions
          AssistantChatbot::ToolRegistry.new.tool_definitions
        end

  def requires_confirmation?(function_name)
          # Action functions require confirmation
          action_functions = %w[create_prompt create_dataset generate_tests run_tests deploy_agent]
      requires = action_functions.include?(function_name)

      Rails.logger.debug "[AssistantChatbot] requires_confirmation?(#{function_name}) => #{requires}"

      requires
    end

      def build_confirmation_message(function_name, arguments)
      Rails.logger.debug "[AssistantChatbot] Building confirmation message for: #{function_name}"

        "🔧 I'll #{function_name.humanize.downcase} with these parameters:\n" \
          "#{arguments.inspect}\n\n" \
          "Do you want me to proceed?"
      end

        def current_wizard_assistant
          case assistant_mode
          when :test_runner_wizard
            test_runner_wizard_assistant
          when :test_creator_wizard
            test_creator_wizard_assistant
          when :dataset_wizard
            dataset_wizard_assistant
          when :deployment_wizard
            deployment_wizard_assistant
          when :agent_creation_wizard
            agent_creation_wizard_assistant
          end
        end

          def assistant_mode
            @assistant_mode || :default
          end

          def test_runner_wizard_mode?
            assistant_mode == :test_runner_wizard
          end

          def test_creator_wizard_mode?
            assistant_mode == :test_creator_wizard
          end

          def dataset_wizard_mode?
            assistant_mode == :dataset_wizard
          end

          def deployment_wizard_mode?
            assistant_mode == :deployment_wizard
          end

            def agent_creation_wizard_mode?
              assistant_mode == :agent_creation_wizard
          end

          def test_runner_wizard_assistant
            @test_runner_wizard_assistant ||= AssistantChatbot::Assistants::TestRunnerWizardAssistant.new(context: @context)
          end

          def test_creator_wizard_assistant
            @test_creator_wizard_assistant ||= AssistantChatbot::Assistants::TestCreatorWizardAssistant.new(context: @context)
          end

          def dataset_wizard_assistant
            @dataset_wizard_assistant ||= AssistantChatbot::Assistants::DatasetWizardAssistant.new(context: @context)
          end

          def deployment_wizard_assistant
            @deployment_wizard_assistant ||= AssistantChatbot::Assistants::DeploymentWizardAssistant.new(context: @context)
          end

            def agent_creation_wizard_assistant
              @agent_creation_wizard_assistant ||= AssistantChatbot::Assistants::AgentCreationWizardAssistant.new(context: @context)
            end

          def extract_run_tests_function_call_from_text(text)
          return nil if text.blank?

          stripped = text.strip

          begin
            data = JSON.parse(stripped)
          rescue JSON::ParserError
            Rails.logger.debug "[AssistantChatbot] Test wizard response not valid JSON plan"
            return nil
          end

          unless data.is_a?(Hash)
            Rails.logger.debug "[AssistantChatbot] JSON plan is not an object"
            return nil
          end

          # Require at least the core run_tests arguments
          unless data.key?("agent_version_id") && data.key?("run_mode")
            Rails.logger.debug "[AssistantChatbot] JSON plan missing required keys"
            return nil
          end

          args = data.deep_symbolize_keys.with_indifferent_access

          Rails.logger.info "[AssistantChatbot] Parsed run_tests JSON plan: #{args.inspect}"

          {
            function_call: {
              name: "run_tests",
              arguments: args
            }
          }
        end

          def extract_generate_tests_function_call_from_text(text)
            return nil if text.blank?

            stripped = text.strip

            begin
              data = JSON.parse(stripped)
            rescue JSON::ParserError
              Rails.logger.debug "[AssistantChatbot] Test creator wizard response not valid JSON plan"
              return nil
            end

            unless data.is_a?(Hash)
              Rails.logger.debug "[AssistantChatbot] Test creator JSON plan is not an object"
              return nil
            end

            unless data.key?("agent_version_id")
              Rails.logger.debug "[AssistantChatbot] Test creator JSON plan missing agent_version_id"
              return nil
            end

            args = data.deep_symbolize_keys.with_indifferent_access

            Rails.logger.info "[AssistantChatbot] Parsed generate_tests JSON plan: #{args.inspect}"

            {
              function_call: {
                name: "generate_tests",
                arguments: args
              }
            }
          end

          def extract_create_dataset_function_call_from_text(text)
            return nil if text.blank?

            stripped = text.strip

            begin
              data = JSON.parse(stripped)
            rescue JSON::ParserError
              Rails.logger.debug "[AssistantChatbot] Dataset wizard response not valid JSON plan"
              return nil
            end

            unless data.is_a?(Hash)
              Rails.logger.debug "[AssistantChatbot] Dataset wizard JSON plan is not an object"
              return nil
            end

            unless data.key?("agent_version_id")
              Rails.logger.debug "[AssistantChatbot] Dataset JSON plan missing agent_version_id"
              return nil
            end

            args = data.deep_symbolize_keys.with_indifferent_access

            Rails.logger.info "[AssistantChatbot] Parsed create_dataset JSON plan: #{args.inspect}"

            {
              function_call: {
                name: "create_dataset",
                arguments: args
              }
            }
          end

          def extract_deploy_agent_function_call_from_text(text)
            return nil if text.blank?

            stripped = text.strip

            begin
              data = JSON.parse(stripped)
            rescue JSON::ParserError
              Rails.logger.debug "[AssistantChatbot] Deployment wizard response not valid JSON plan"
              return nil
            end

            unless data.is_a?(Hash)
              Rails.logger.debug "[AssistantChatbot] Deployment wizard JSON plan is not an object"
              return nil
            end

            unless data.key?("agent_version_id") && data.key?("agent_type")
              Rails.logger.debug "[AssistantChatbot] Deployment JSON plan missing required keys"
              return nil
            end

            args = data.deep_symbolize_keys.with_indifferent_access

            Rails.logger.info "[AssistantChatbot] Parsed deploy_agent JSON plan: #{args.inspect}"

            {
              function_call: {
                name: "deploy_agent",
                arguments: args
              }
            }
          end

          def extract_create_prompt_function_call_from_text(text)
            return nil if text.blank?

            stripped = text.strip

            begin
              data = JSON.parse(stripped)
            rescue JSON::ParserError
              Rails.logger.debug "[AssistantChatbot] Prompt creation wizard response not valid JSON plan"
              return nil
            end

            unless data.is_a?(Hash)
              Rails.logger.debug "[AssistantChatbot] Prompt creation JSON plan is not an object"
              return nil
            end

            unless data.key?("name") && data.key?("system_prompt_concept")
              Rails.logger.debug "[AssistantChatbot] Prompt creation JSON plan missing required keys"
              return nil
            end

            args = data.deep_symbolize_keys.with_indifferent_access

            Rails.logger.info "[AssistantChatbot] Parsed create_prompt JSON plan: #{args.inspect}"

            {
              function_call: {
                name: "create_prompt",
                arguments: args
              }
            }
              end
  end
end
