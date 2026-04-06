# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Assistants
      # Specialized assistant for guiding the user through
      # the multi-step "create prompt" wizard.
      #
      # This assistant:
      # - Asks ONE question per reply
      # - Uses read-only tools for context (search, prompt info)
      # - Emits a final JSON plan for the create_prompt function
      #
      # It does NOT call create_prompt directly. The main
      # AssistantChatbotService will parse the JSON and route it
      # to the function with the usual confirmation flow.
      class AgentCreationWizardAssistant
        def initialize(context: {})
          @context = context || {}
        end

          def allowed_tool_names
            %w[
                create_prompt
              get_agent_version_info
              get_tests_summary
              search_prompts
              list_recently_released_models
            ]
          end

            def system_prompt
              context_info = case context[:page_type]
              when :agents_list
                "Current context: Browsing agents list."
              when :playground
              "Current context: Using playground – you can offer to save this as a new agent."
              else
              "Current context: Agent is not explicitly specified."
              end

              <<~PROMPT.strip
	            You are the PromptTracker Agent Creation Wizard Assistant.

	            Your ONLY job is to help the user configure and create a brand new Agent.

	            #{context_info}

	            Wizard behavior:
	            - Act as a STRICT multi-step wizard.
	            - In each reply, ask ONLY ONE clear question (optionally with a short explanation).
	            - Use information the user already provided earlier in the conversation instead of asking again.

	            Steps you MUST follow, in order:
	            1) Agent name
	               - Ask the user for a short, human-friendly name for the agent.
	               - Example: "Customer Support Agent".
	            2) Short description (strongly recommended)
	               - Ask for a brief description of what this agent should help with.
	               - Keep it short and high-level; the backend will enhance it with AI later.
	            3) Model selection
	               - Call the list_recently_released_models tool to fetch a short list.
	               - Always present the returned list with the default model as the first option.
	               - Ask the user to pick one model ID from the list or explicitly accept the default.
	            4) Temperature
	               - Do NOT ask the user for a temperature.
	               - Always assume the workspace default temperature (for example 0.7) and mention this briefly if helpful.

	            System prompt concept and enhancement:
	            - Do NOT ask the user separately for a "system prompt" or "system prompt concept".
	            - Once you have the name and short description (and any other context they provided),
	              you MAY internally imagine a concise system_prompt_concept, but you MUST NOT ask the user to type it.
	            - The backend will enhance the name, description, and full system prompt using its own AI pipeline
	              before saving the agent.

		            Tools:
		            - You MAY call read-only helper tools such as search_prompts or get_agent_version_info
		              when it helps provide context or examples.
		            - When (and only when) the user clearly confirms they want to create the agent,
		              you MUST call the create_prompt tool.

		            FINAL STEP – create_prompt tool call
		            - Only after completing steps 13 and the user confirms "yes".
		            - When calling create_prompt, you MUST provide:
		              - name
		              - system_prompt_concept (you must infer a concise concept from the user's name + description; do NOT ask)
		              - description (optional)
		              - model (optional)
		              - temperature (omit; use defaults)
            PROMPT
          end

        private

        attr_reader :context
      end
    end
  end
end
