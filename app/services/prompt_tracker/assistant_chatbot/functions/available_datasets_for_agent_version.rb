# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Read-only helper that lists datasets for a AgentVersion.
      #
      # Used by the assistant as a discovery step in the run_tests wizard
      # when deciding between running tests against a dataset or with
      # custom variables.
      #
      # Arguments:
      # - agent_version_id: (required) ID of the agent version
      #
      # The result message is a human-readable summary that includes
      # dataset IDs, names, types, and row counts so the model can ask
      # the user which dataset to use.
      class AvailableDatasetsForAgentVersion < Base
        protected

        def execute
          version = find_agent_version
          datasets = version.datasets.order(created_at: :desc)

          if datasets.empty?
            return success(
              <<~MSG.strip,
	              ℹ️ This agent version does not have any datasets yet.

	              You can run tests once with custom variables, or ask me to create a dataset for this agent version.
              MSG
              links: build_links(version)
            )
          end

          list_lines = datasets.map do |dataset|
            type_label = dataset.dataset_type
            "- ID #{dataset.id}: \"#{dataset.name}\" (#{type_label}, rows: #{dataset.row_count})"
          end.join("\n")

          message = <<~MSG.strip
            ✅ Here are the datasets for AgentVersion ##{version.id}:

            #{list_lines}

            Reply with a dataset ID from this list to use it, or say "custom" if you prefer to run once with custom variables instead of a dataset.
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
            link("Open datasets tab", "#{base_path}#datasets", icon: "table")
          ]
        end
      end
    end
  end
end
