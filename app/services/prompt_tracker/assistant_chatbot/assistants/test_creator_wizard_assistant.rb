# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Assistants
      # Specialized assistant for guiding the user through
      # the multi-step "generate tests" wizard.
      #
      # This assistant is responsible only for:
      # - Asking the right sequence of questions to configure test generation
      # - Producing a final tool call to generate_tests (which the backend will confirm)
      #
      # It does NOT generate tests directly. Instead, once the
      # user has confirmed the configuration, it must emit a
      # single JSON object. The main AssistantChatbotService
      # will parse this JSON and route it to the generate_tests
      # function with the usual confirmation flow.
      class TestCreatorWizardAssistant
        def initialize(context: {})
          @context = context || {}
        end

            def allowed_tool_names
              %w[
                generate_tests
              ]
            end

        # Build a focused system prompt for the test creator wizard.
        def system_prompt
          context_info = if context[:agent_version_id]
            "Current context: Viewing AgentVersion ##{context[:agent_version_id]}"
          else
            "Current context: AgentVersion is not explicitly specified."
          end

          <<~PROMPT.strip
            You are the PromptTracker Test Creator Wizard Assistant.

            Your ONLY job is to help the user generate (create) tests for a single AgentVersion using AI.

            #{context_info}

            Wizard behavior for generating tests:
            - Act as a STRICT multi-step wizard.
            - In each reply, ask ONLY ONE clear question (optionally with 1–2 sentences of explanation).
            - Always make sure you know which AgentVersion to use:
              * If the current page context includes agent_version_id, you MUST use that value.
              * Otherwise, ask the user which prompt/version to use or help them find it.

            Steps:
	            1) Ask how many tests to generate
               - Default is 5, maximum is 10.
               - Example: "How many tests would you like me to generate? (default: 5, max: 10)"

	            2) Ask for optional custom instructions
               - Ask if the user has any specific focus areas or instructions for test generation.
               - Examples: "Focus on edge cases", "Test error handling", "Emphasize multi-language support".
               - Make it clear this is optional — they can skip this step.

	            3) Call the generate_tests tool
	               - After you have agent_version_id + count + (optional) instructions, you MUST call the generate_tests tool.
	               - Do NOT call generate_tests until you have asked the two questions above.
	               - The backend will require confirmation before actually generating tests.

	            When calling generate_tests, use these arguments:
	              - agent_version_id: integer (required)
	              - count: integer (1-10, default: 5)
	              - instructions: string (optional; omit if blank)
          PROMPT
        end

        private

        attr_reader :context
      end
    end
  end
end
