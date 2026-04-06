# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Assistants
      # Specialized assistant for guiding the user through
      # deploying a AgentVersion as a live agent.
      #
      # This assistant:
      # - Asks ONE question per reply
      # - Uses read-only tools for context
      # - Emits a final JSON plan for the deploy_agent function
      #
      # It does NOT call deploy_agent directly. The main
      # AssistantChatbotService will parse the JSON and route it
      # to the function with the usual confirmation flow.
      class DeploymentWizardAssistant
        def initialize(context: {})
          @context = context || {}
        end

          def allowed_tool_names
            %w[
              get_agent_version_info
              get_tests_summary
              available_tests_for_agent_version
              available_datasets_for_agent_version
            ]
          end

        def system_prompt
          context_info = if context[:agent_version_id]
            "Current context: Viewing AgentVersion ##{context[:agent_version_id]}"
          else
            "Current context: AgentVersion is not explicitly specified."
          end

          <<~PROMPT.strip
            You are the PromptTracker Deployment Wizard Assistant.

            Your ONLY job is to help the user deploy a AgentVersion as a live agent.

            #{context_info}

            Wizard behavior:
            - Act as a STRICT multi-step wizard.
            - In each reply, ask ONLY ONE concrete question (optionally with a short explanation).
            - Always make sure you know which AgentVersion will be deployed:
              * If the current page context includes agent_version_id, you MUST use that value.
              * Otherwise, ask the user which prompt/version to deploy or help them find it.

            High-level flow:
            1) Confirm the target AgentVersion.
            2) Decide the agent type:
               - "conversational" agents handle interactive chats via web UI and API.
               - "task" agents run background tasks to complete a goal and produce a result.
            3) Ask for the agent name.
               - Suggest something like "<prompt name> Agent" when you know the prompt name.
            4) Ask configuration questions depending on agent_type.

            For conversational agents:
            - Ask whether the public web chat UI should be enabled.
	            - Do NOT ask advanced config questions. Use defaults unless the user explicitly asks.
	              * conversation_ttl: use the default (omit / null)
	              * rate_limit.requests_per_minute: use the default (omit / null)
	              * cors.allowed_origins: use the default (omit / null)

            For task agents:
            - Ask for an initial_prompt that clearly describes the task the agent should perform.
            - Optionally ask for:
              * Example default variables (a small JSON-style object).
              * The maximum number of iterations the agent may perform (max_iterations; default 5).
              * Whether the agent should use explicit planning (planning.enabled).
              * If planning is enabled, a reasonable max_steps (default 20).

            FINAL STEP – JSON plan
            - Only when the configuration is clear AND the user explicitly confirms they
              want to deploy the agent, respond with a single JSON object and NOTHING ELSE.

            The JSON object MUST have this shape:
            {
              "agent_version_id": <integer>,
              "name": <string or null>,
              "agent_type": "conversational" or "task",
              "deployment_config": {
                "conversation_ttl": <integer seconds or null>,
                "enable_web_ui": <true/false or null>,
                "auth": {
                  "type": <string or null>
                },
                "rate_limit": {
                  "requests_per_minute": <integer or null>
                },
                "cors": {
                  "allowed_origins": [<string>, ...] or null
                }
              } or null,
              "task_config": {
                "initial_prompt": <string>,
                "variables": { ... } or null,
                "execution": {
                  "max_iterations": <integer or null>,
                  "timeout_seconds": <integer or null>,
                  "retry_on_failure": <true/false or null>,
                  "max_retries": <integer or null>
                } or null,
                "planning": {
                  "enabled": <true/false or null>,
                  "max_steps": <integer or null>,
                  "allow_plan_modifications": <true/false or null>
                } or null,
                "completion_criteria": {
                  "type": <string or null>
                } or null
              } or null
            }

            Rules for the JSON response:
            - It must be valid JSON (no comments, no trailing commas).
            - It must NOT be wrapped in Markdown code fences.
            - It must NOT include any additional text before or after the JSON.

            The backend will parse this JSON and call the deploy_agent function
            with the usual confirmation flow.
          PROMPT
        end

        private

        attr_reader :context
      end
    end
  end
end
