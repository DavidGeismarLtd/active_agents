# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    # Routes assistant chatbot function calls to appropriate function classes.
    #
    # Each function class should:
    # - Inherit from Functions::Base
    # - Implement #call method
    # - Return a Result struct
    #
    # @example Execute a function
    #   result = FunctionExecutor.call(
    #     function_name: "create_prompt",
    #     arguments: { name: "Test", description: "Test prompt" },
    #     context: {}
    #   )
    #
    class FunctionExecutor
      Result = Struct.new(:success?, :message, :links, :entities_created, :error, keyword_init: true)

      def self.call(function_name:, arguments:, context:)
        new(function_name, arguments, context).call
      end

      def initialize(function_name, arguments, context)
        @function_name = function_name
        @arguments = arguments
        @context = context
      end

      def call
        function_class = find_function_class(@function_name)

        unless function_class
          return Result.new(
            success?: false,
            message: nil,
            links: [],
            entities_created: {},
            error: "Unknown function: #{@function_name}"
          )
        end

        # Execute the function
        function_result = function_class.new(@arguments, @context).call

        # Convert function result to executor result
        Result.new(
          success?: function_result.success?,
          message: function_result.message,
          links: function_result.links,
          entities_created: function_result.entities_created,
            error: function_result.error
          )
        end

      private

      def find_function_class(name)
        # Map function names to classes
        function_map = {
          "create_prompt" => Functions::CreateAgent,
          "create_dataset" => Functions::CreateDataset,
          "generate_tests" => Functions::GenerateTests,
          "run_tests" => Functions::RunTests,
            "deploy_agent" => Functions::DeployAgent,
            "list_recently_released_models" => Functions::ListRecentlyReleasedModels,
          "get_agent_version_info" => Functions::GetAgentVersionInfo,
          "get_tests_summary" => Functions::GetTestsSummary,
          "search_prompts" => Functions::SearchAgents,
          "available_tests_for_agent_version" => Functions::AvailableTestsForAgentVersion,
          "available_datasets_for_agent_version" => Functions::AvailableDatasetsForAgentVersion
        }

        function_map[name]
      end
    end
  end
end
