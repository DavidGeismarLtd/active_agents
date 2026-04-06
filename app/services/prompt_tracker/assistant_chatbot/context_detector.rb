# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    # Detects page context and generates relevant suggestions.
    #
    # @example Generate suggestions
    #   suggestions = ContextDetector.suggestions_for({
    #     page_type: :agent_version_detail,
    #     version_id: 123
    #   })
    #
    class ContextDetector
      def self.suggestions_for(context)
        new(context).suggestions
      end

      def initialize(context)
        @context = context
      end

      def suggestions
        case @context[:page_type]
        when :agent_version_detail
          agent_version_suggestions
        when :agent_detail
            agent_detail_suggestions
        when :agents_list
            agents_list_suggestions
        when :playground
          playground_suggestions
        when :monitoring
          monitoring_suggestions
        when :agents
          agents_suggestions
        else
          general_suggestions
        end
      end

      private

      def agent_version_suggestions
          suggestions = [
            "Create a dataset for this agent version",
            "Create tests for this agent version"
          ]

          if enabled_tests_exist_for_agent_version?
            suggestions << "Run tests for this agent version"
          end

          suggestions << "Deploy this agent version"

          suggestions
      end

        def enabled_tests_exist_for_agent_version?
          agent_version_id = @context[:agent_version_id]
          return false if agent_version_id.blank?

          PromptTracker::Test.enabled.exists?(testable_type: "PromptTracker::AgentVersion", testable_id: agent_version_id)
        end

        def agent_detail_suggestions
        [
          "Show me the latest version",
          "Create a new version",
          "How many tests are there?"
        ]
      end

        def agents_list_suggestions
        [
            "Create a new agent",
            "Show me agents with failing tests",
            "Find agents using gpt-4"
        ]
      end

      def playground_suggestions
        [
            "Save this as a new agent",
          "Generate tests for this configuration",
          "What's the token usage?"
        ]
      end

      def monitoring_suggestions
        [
          "Show me recent errors",
            "Which agents are being used most?",
          "Analyze test results"
        ]
      end

      def agents_suggestions
        [
          "Deploy a new agent",
          "Show me active agents",
          "Check agent performance"
        ]
      end

      def general_suggestions
        [
            "Create a new agent",
          "Show me my recent work",
          "Help me get started"
        ]
      end
    end
  end
end
