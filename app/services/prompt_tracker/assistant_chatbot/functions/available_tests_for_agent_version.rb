# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Read-only helper that lists enabled tests for a AgentVersion.
      #
      # Used by the assistant as a discovery step before deciding which
      # tests to run in the run_tests wizard.
      #
      # Arguments:
      # - agent_version_id: (required) ID of the prompt version
      #
      # The result message is a human-readable summary that includes test
      # IDs and names so the model can ask the user to pick specific tests
      # or run them all.
      class AvailableTestsForAgentVersion < Base
        protected

        def execute
          version = find_agent_version
          tests = version.tests.enabled.order(created_at: :desc)

          if tests.empty?
            return success(
              <<~MSG.strip,
              ℹ️ There are currently no enabled tests for AgentVersion ##{version.id}.

              You can ask me to generate tests for this prompt version, or create them manually from the Testing tab.
              MSG
              links: build_links(version)
            )
          end

          list_lines = tests.map do |test|
            "- ID #{test.id}: #{test.name}"
          end.join("\n")

          message = <<~MSG.strip
            ✅ Here are the enabled tests for AgentVersion ##{version.id}:

            #{list_lines}

            Use these IDs when deciding whether to run all tests or only a subset.
          MSG

          success(message, links: build_links(version))
        end

        def validate_arguments!
          raise ArgumentError, "agent_version_id is required" if arg(:agent_version_id).blank?
        end

        private

        def find_agent_version
          version_id = arg(:agent_version_id)
          version = AgentVersion.find_by(id: version_id)
          raise ArgumentError, "AgentVersion #{version_id} not found" unless version

          version
        end

          def build_links(version)
            base_path = "#{engine_base_path}/testing/agents/#{version.agent_id}/versions/#{version.id}"

          [
            link("Open tests tab", "#{base_path}#tests", icon: "list-check")
          ]
        end
      end
    end
  end
end
