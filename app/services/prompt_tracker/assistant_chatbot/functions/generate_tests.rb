# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Generates tests for a AgentVersion using AI.
      #
      # Arguments:
      # - agent_version_id: (required) ID of the prompt version
      # - count: (optional) Number of tests to generate (default: 5)
      # - instructions: (optional) Custom instructions for test generation
      #
      # @example
      #   function = GenerateTests.new(
      #     { agent_version_id: 123, count: 5, instructions: "Focus on edge cases" },
      #     {}
      #   )
      #   result = function.call
      #
      class GenerateTests < Base
        protected

        def execute
          version = find_agent_version
          count = arg(:count) || 5
          instructions = arg(:instructions)

          # Call TestGeneratorService
          result = TestGeneratorService.generate(
            agent_version: version,
            instructions: instructions,
            count: count.to_i.clamp(1, 10)
          )

          success(
            build_success_message(version, result),
            links: build_links(version, result[:tests]),
            entities: { test_ids: result[:tests].map(&:id) }
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

        def build_success_message(version, result)
          tests = result[:tests]
          test_list = tests.first(5).map.with_index do |test, idx|
            "#{idx + 1}. \"#{test.name}\" - #{test.description}"
          end.join("\n")

          <<~MSG.strip
            ✅ Generated #{result[:count]} test#{result[:count] == 1 ? '' : 's'} successfully!

            📊 Test Summary:
            #{test_list}
            #{"... and #{tests.size - 5} more" if tests.size > 5}

            💭 Reasoning: #{result[:overall_reasoning]}

            Would you like to run all tests now?
          MSG
        end

          def build_links(version, tests)
            base_path = "/prompt_tracker/testing/agents/#{version.agent_id}/versions/#{version.id}"

            [
              link("View all tests", "#{base_path}#tests", icon: "list-check")
            ]
        end
      end
    end
  end
end
