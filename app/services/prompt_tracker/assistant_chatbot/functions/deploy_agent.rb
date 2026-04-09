# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Deploys a AgentVersion as a conversational or task agent.
      #
      # Arguments (JSON plan collected by the deployment wizard):
      # - agent_version_id: (required) ID of the prompt version to deploy
      # - name: (optional) Agent name, defaults to "<agent name> Agent"
      # - agent_type: (required) "conversational" or "task"
      # - deployment_config: (optional) Hash for conversational agents
      # - task_config: (optional) Hash for task agents
      #
      # The shape of deployment_config and task_config mirrors
      # PromptTracker::DeployedAgent#deployment_config and #task_config.
      class DeployAgent < Base
        protected

        def execute
          version = find_agent_version
          type = normalized_agent_type
          name = arg(:name).presence || default_name_for(version)

          attributes = {
            agent_version: version,
            name: name,
            agent_type: type
          }

          if type == "conversational"
            attributes[:deployment_config] = normalized_deployment_config
          else
            attributes[:task_config] = normalized_task_config
          end

          agent = PromptTracker::DeployedAgent.new(attributes)

          if agent.save
            success(
              build_success_message(version, agent),
              links: build_links(agent),
              entities: { deployed_agent_id: agent.id, agent_version_id: version.id }
            )
          else
            failure(format_errors(agent))
          end
        end

        def validate_arguments!
          raise ArgumentError, "agent_version_id is required" if arg(:agent_version_id).blank?

          type = (arg(:agent_type).presence || "conversational").to_s
          unless %w[conversational task].include?(type)
            raise ArgumentError, "agent_type must be 'conversational' or 'task'"
          end

          return unless type == "task"

          cfg = arg(:task_config)
          cfg_hash = cfg.is_a?(Hash) ? cfg.deep_symbolize_keys : {}
          initial_prompt = cfg_hash[:initial_prompt]

          if initial_prompt.blank?
            raise ArgumentError, "task_config.initial_prompt is required for task agents"
          end
        end

        private

        def find_agent_version
          version_id = arg(:agent_version_id)
          version = AgentVersion.find_by(id: version_id)
          raise ArgumentError, "AgentVersion #{version_id} not found" unless version
          version
        end

        def normalized_agent_type
          (arg(:agent_type).presence || "conversational").to_s
        end

        def default_name_for(version)
            "#{version.agent.name} Agent"
        end

        def normalized_deployment_config
          raw = arg(:deployment_config)
          return {} unless raw.is_a?(Hash)

          raw.deep_symbolize_keys
        end

        def normalized_task_config
          raw = arg(:task_config)
          return {} unless raw.is_a?(Hash)

          cfg = raw.deep_symbolize_keys

          {
            initial_prompt: cfg[:initial_prompt],
            variables: cfg[:variables].is_a?(Hash) ? cfg[:variables] : {},
            execution: normalized_execution_config(cfg[:execution]),
            planning: normalized_planning_config(cfg[:planning]),
            completion_criteria: normalized_completion_config(cfg[:completion_criteria])
          }
        end

        def normalized_execution_config(raw)
          conf = raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}

          {
            max_iterations: (conf[:max_iterations] || 5).to_i,
            timeout_seconds: (conf[:timeout_seconds] || 3600).to_i,
            retry_on_failure: conf.key?(:retry_on_failure) ? !!conf[:retry_on_failure] : false,
            max_retries: (conf[:max_retries] || 3).to_i
          }
        end

        def normalized_planning_config(raw)
          conf = raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}

          {
            enabled: conf.key?(:enabled) ? !!conf[:enabled] : false,
            max_steps: (conf[:max_steps] || 20).to_i,
            allow_plan_modifications: conf.key?(:allow_plan_modifications) ? !!conf[:allow_plan_modifications] : true
          }
        end

        def normalized_completion_config(raw)
          conf = raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}

          {
            type: conf[:type].presence || "auto"
          }
        end

        def build_success_message(version, agent)
          <<~MSG.strip
            ✅ Deployed agent "#{agent.name}" for agent "#{version.agent.name}" (version #{version.name}).

            🤖 Agent type: #{agent.agent_type}
            🔗 Public URL: #{agent.public_url}
          MSG
        end

        def build_links(agent)
          [
            link("View agent", "#{engine_base_path}/agents/#{agent.slug}", icon: "robot")
          ]
        end

        def format_errors(agent)
          errors = agent.errors.full_messages
          "Failed to deploy agent: #{errors.join(', ')}"
        end
      end
    end
  end
end
