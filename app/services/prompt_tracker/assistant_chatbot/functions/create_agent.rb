# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Creates a new Agent and initial AgentVersion.
      #
      # Arguments (raw values collected by the wizard):
      # - name: (required) Raw agent name from the user
      # - description: (optional) Short, rough description from the user
      # - system_prompt_concept: (required) Brief concept of what the AI should do
      # - user_prompt: (optional) User prompt template. If omitted, the
      #   AgentVersion will have no user_prompt (system-prompt-only flow).
      # - model: (optional) Model name (e.g., "gpt-4o")
      # - provider: (optional) Provider name (e.g., "openai")
      # - temperature: (optional) Temperature setting
      #
      # @example
      #   function = CreateAgent.new(
      #     { name: "Customer Support Bot", description: "A helpful bot" },
      #     {}
      #   )
      #   result = function.call
      #
      class CreateAgent < Base
        protected

        def execute
            enhanced_name_result = PromptTracker::PromptEnhancers::NameEnhancer.enhance(
              raw_name: arg(:name),
              description: arg(:description),
              system_prompt_concept: arg(:system_prompt_concept)
            )

            enhanced_name = enhanced_name_result[:name]

            enhanced_description_result = PromptTracker::PromptEnhancers::DescriptionEnhancer.enhance(
              name: enhanced_name,
              raw_description: arg(:description),
              system_prompt_concept: arg(:system_prompt_concept)
            )

            enhanced_description = enhanced_description_result[:description]

            system_result = PromptTracker::PromptEnhancers::SystemPromptEnhancer.enhance(
              system_prompt_concept: arg(:system_prompt_concept),
              description: enhanced_description
            )

            system_prompt = system_result[:system_prompt]
            variables = system_result[:variables] || []
            explanation = system_result[:explanation]

              user_prompt = arg(:user_prompt).presence

              agent = Agent.new(
              name: enhanced_name,
              description: enhanced_description,
              created_by: "assistant_chatbot"
            )

            version_attributes = {
              system_prompt: system_prompt,
              user_prompt: user_prompt,
              status: "draft",
              model_config: build_model_config,
              notes: [ "Created by Assistant Chatbot", explanation ].compact.join(" - ")
            }
            version_attributes[:variables_schema] = build_variables_schema(variables) if variables.any?

              version = agent.agent_versions.build(version_attributes)

              if agent.save
              success(
                  build_success_message(agent, version),
                  links: build_links(agent, version),
                  entities: { agent_id: agent.id, version_id: version.id }
              )
              else
                failure(format_errors(agent, version))
              end
        end

        def validate_arguments!
            raise ArgumentError, "name is required" if arg(:name).blank?
            raise ArgumentError, "system_prompt_concept is required" if arg(:system_prompt_concept).blank?
        end

        private

          def build_variables_schema(variable_names)
            Array(variable_names).map do |name|
              {
                "name" => name.to_s,
                "type" => "string",
                "required" => false
              }
            end
          end

        def build_model_config
          config = {}

          # Add provider if specified
          config["provider"] = arg(:provider) if arg(:provider).present?

          # Add model if specified
          config["model"] = arg(:model) if arg(:model).present?

          # Add temperature if specified
          config["temperature"] = arg(:temperature).to_f if arg(:temperature).present?

          # Defaults
          config["provider"] ||= "openai"
          config["api"] ||= "chat_completions"
          config["model"] ||= "gpt-4o"
          config["temperature"] ||= 0.7

          config
        end

          def build_success_message(agent, version)
          <<~MSG.strip
	            ✅ Created agent "#{agent.name}" successfully!

	            📝 Agent ID: #{agent.id}
            🆔 Version ID: #{version.id}
            🤖 Model: #{version.model_config['model']}
            🌡️ Temperature: #{version.model_config['temperature']}
	            📦 Variables: #{Array(version.variables_schema).map { |v| v['name'] }.join(', ').presence || 'none'}

            What would you like to do next?
          MSG
        end

          def build_links(agent, version)
            base_path = "#{engine_base_path}/testing/agents"

          [
                # Link to version detail page (primary action)
                link("View version details", "#{base_path}/#{agent.id}/versions/#{version.id}", icon: "eye"),
              link("Open in playground", "#{base_path}/#{agent.id}/playground", icon: "play-circle"),
              link("View all versions", "#{base_path}/#{agent.id}#versions", icon: "list-ul"),
              link("Testing section", "#{base_path}/#{agent.id}/versions/#{version.id}#tests", icon: "check-circle")
          ]
        end

          def format_errors(agent, version)
          errors = []
            errors += agent.errors.full_messages if agent.errors.any?
          errors += version.errors.full_messages if version.errors.any?

            "Failed to create agent: #{errors.join(', ')}"
        end
      end
    end
  end
end
