# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Gets detailed information about a AgentVersion.
      #
      # This is a query function (does not require confirmation).
      #
      # Arguments:
      # - agent_version_id: (required) ID of the agent version
      #
      # Returns:
      # - Model configuration (provider, API, model, temperature)
      # - Status and version details
      # - Links to view, playground, and testing
      #
      # @example
      #   function = GetAgentVersionInfo.new({ agent_version_id: 123 }, {})
      #   result = function.call
      #
      class GetAgentVersionInfo < Base
        protected

        def execute
          version = find_agent_version

          success(
            build_info_message(version),
            links: build_links(version),
            entities: { agent_version_id: version.id, agent_id: version.agent_id }
          )
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

        def build_info_message(version)
          model_config = version.model_config || {}
          provider = model_config["provider"] || model_config[:provider] || "openai"
          api = model_config["api"] || model_config[:api] || "chat_completions"
          model = model_config["model"] || model_config[:model] || "gpt-4o"
          temperature = model_config["temperature"] || model_config[:temperature] || 0.7

          # Test statistics
          total_tests = version.tests.count
          enabled_tests = version.tests.enabled.count

          # Recent test run stats
          recent_runs = version.tests.flat_map { |t| t.recent_runs(5) }
          passed_runs = recent_runs.count { |r| r.passed == true }
          failed_runs = recent_runs.count { |r| r.passed == false }

          <<~MSG.strip
	            📊 **Agent Version Information**

            **Basic Details:**
	            • Agent: #{version.agent.name}
            • Version: #{version.name}
            • Status: #{version.status&.titleize || 'Active'}

            **Model Configuration:**
            • Provider: #{provider.titleize}
            • API: #{api.titleize.gsub('_', ' ')}
            • Model: #{model}
            • Temperature: #{temperature}

            **Testing Overview:**
            • Total tests: #{total_tests} (#{enabled_tests} enabled)
            • Recent runs: #{recent_runs.size} (✅ #{passed_runs} passed, ❌ #{failed_runs} failed)

            **Features:**
            #{version.variables_schema.present? ? "• Variables: #{version.variables_schema.size} defined" : "• No variables"}
            #{model_config["tools"].present? ? "• Tools: #{model_config['tools'].size} enabled" : ""}
            #{version.response_schema.present? ? "• Structured output: Enabled" : ""}
          MSG
        end

            def build_links(version)
              base_path = "#{engine_base_path}/testing/agents/#{version.agent_id}/versions/#{version.id}"

          [
              link("View agent version", base_path, icon: "eye"),
            link("Open in playground", "#{base_path}/playground", icon: "play-circle"),
            link("View tests", "#{base_path}#tests", icon: "list-check"),
              link("Version history", "#{engine_base_path}/testing/agents/#{version.agent_id}#versions", icon: "clock-history")
          ]
        end
      end
    end
  end
end
