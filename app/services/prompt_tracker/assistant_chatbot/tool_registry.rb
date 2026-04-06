# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    # Central registry for assistant "function tool" JSON schemas.
    #
    # This keeps AssistantChatbotService readable while allowing each wizard
    # to expose only a safe subset of read-only tools.
    class ToolRegistry
      def tool_definitions
        [
          {
            name: "create_prompt",
            description: "Create a new agent from raw user inputs. The backend will enhance the description and system prompt concept with AI.",
            parameters: {
              type: "object",
              properties: {
                name: { type: "string", description: "Name of the agent (e.g., 'Customer Support Agent')" },
                description: { type: "string", description: "Short description of the agent's purpose (optional - will be enhanced with AI)." },
                system_prompt_concept: { type: "string", description: "Brief concept of what the AI assistant should do. The backend will expand it into a detailed system prompt." },
                model: { type: "string", description: "Model to use (optional, default: gpt-4o)" },
                temperature: { type: "number", description: "Temperature (optional, 0.0 to 2.0, default: 0.7)" }
              },
              required: [ "name", "system_prompt_concept" ]
            }
          },
          {
            name: "create_dataset",
            description: "Create a new dataset for an agent version and optionally generate dataset rows with AI.",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version this dataset belongs to" },
                name: { type: "string", description: "Short raw name for the dataset (optional - will be enhanced with AI)." },
                description: { type: "string", description: "Short description / purpose for the dataset (optional - will be enhanced with AI)." },
                dataset_type: { type: "string", description: "Type of dataset: 'single_turn' or 'conversational' (default: 'single_turn').", enum: [ "single_turn", "conversational" ] },
                count: { type: "integer", description: "Number of rows to generate with AI after creating the dataset (optional, 1-100)." },
                instructions: { type: "string", description: "Extra instructions for how the AI should generate dataset rows (optional)." },
                model: { type: "string", description: "Optional model override for dataset row generation." }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "generate_tests",
            description: "Generate AI-powered tests for an agent version",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version to generate tests for" },
                count: { type: "integer", description: "Number of tests to generate (1-10, default: 5)" },
                instructions: { type: "string", description: "Custom instructions for test generation (optional)" }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "run_tests",
            description: "Run tests for an agent version using either datasets or custom variables.",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version" },
                test_ids: { type: "array", items: { type: "integer" }, description: "Specific test IDs to run (optional, runs all if omitted)" },
                run_mode: { type: "string", description: "How to run the tests: 'dataset' or 'custom'.", enum: [ "dataset", "custom" ] },
                dataset_id: { type: "integer", description: "Dataset to run tests against (required when run_mode is 'dataset')." },
                execution_mode: { type: "string", description: "Execution mode for custom runs: 'single' or 'conversation' (default: 'single').", enum: [ "single", "conversation" ] },
                custom_variables: { type: "object", description: "Custom variables for a single run when not using a dataset." }
              },
              required: [ "agent_version_id", "run_mode" ]
            }
          },
          {
            name: "deploy_agent",
            description: "Deploy an agent version as a conversational or task agent.",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version to deploy" },
                name: { type: "string", description: "Optional name for the deployed agent" },
                agent_type: { type: "string", description: "'conversational' or 'task'", enum: [ "conversational", "task" ] },
                deployment_config: { type: "object", description: "Configuration for conversational agents." },
                task_config: { type: "object", description: "Configuration for task agents." }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "get_agent_version_info",
            description: "Get detailed information about an agent version including model config, status, and test statistics",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version" }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "get_tests_summary",
            description: "Get a summary of all tests for an agent version, including pass/fail statistics and recent runs",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version" }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "available_tests_for_agent_version",
            description: "List enabled tests for an agent version to help choose which tests to run.",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version" }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "available_datasets_for_agent_version",
            description: "List datasets for an agent version to help choose between dataset runs and custom variables.",
            parameters: {
              type: "object",
              properties: {
                agent_version_id: { type: "integer", description: "ID of the agent version" }
              },
              required: [ "agent_version_id" ]
            }
          },
          {
            name: "search_prompts",
            description: "Search for agents by name or description",
            parameters: {
              type: "object",
              properties: {
                query: { type: "string", description: "Search query string" },
                limit: { type: "integer", description: "Maximum number of results (default: 5, max: 20)" }
              },
              required: [ "query" ]
            }
          },
          {
            name: "list_recently_released_models",
              description: "List the most recently released chat models per enabled provider (default model first).",
            parameters: {
              type: "object",
              properties: {
                  per_provider_limit: { type: "integer", description: "Number of recent models to return per provider (default: 5, max: 10)" }
              }
            }
          }
        ]
      end

      def tool_definitions_for(allowed_tool_names)
        return tool_definitions if allowed_tool_names.nil?

        allowed = allowed_tool_names.map(&:to_s)
        tool_definitions.select { |tool| allowed.include?(tool[:name].to_s) }
      end
    end
  end
end
