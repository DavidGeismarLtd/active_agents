# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Gets a summary of tests for a AgentVersion.
      #
      # This is a query function (does not require confirmation).
      #
      # Arguments:
      # - agent_version_id: (required) ID of the agent version
      #
      # Returns:
      # - Test statistics (total, enabled, passing, failing)
      # - Recent test runs with pass/fail status
      # - Links to view all tests and individual test details
      #
      # @example
      #   function = GetTestsSummary.new({ agent_version_id: 123 }, {})
      #   result = function.call
      #
      class GetTestsSummary < Base
        protected

        def execute
          version = find_agent_version
          tests = version.tests.order(created_at: :desc)

          success(
            build_summary_message(version, tests),
            links: build_links(version, tests),
            entities: {
              agent_version_id: version.id,
              test_ids: tests.pluck(:id)
            }
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

        def build_summary_message(version, tests)
          if tests.empty?
              return "📋 **No tests found** for #{version.agent.name} (#{version.name})\n\nWould you like me to generate some tests?"
          end

          # Overall statistics
          total = tests.count
          enabled = tests.enabled.count
          disabled = tests.disabled.count

          # Pass/fail statistics from last runs
          passing = tests.count { |t| t.last_run&.passed == true }
          failing = tests.count { |t| t.last_run&.passed == false }
          not_run = tests.count { |t| t.last_run.nil? }

          # Recent test details
          test_details = tests.first(5).map do |test|
            last_run = test.last_run
            status_icon = if last_run.nil?
              "⚪"
            elsif last_run.passed?
              "✅"
            else
              "❌"
            end

            run_info = if last_run
              "#{status_icon} #{test.name} (#{last_run.status}, #{last_run.execution_time_ms}ms)"
            else
              "#{status_icon} #{test.name} (not run yet)"
            end

            "  • #{run_info}"
          end.join("\n")

          <<~MSG.strip
	            📋 **Test Summary** for #{version.agent.name} (#{version.name})

            **Overall Statistics:**
            • Total tests: #{total} (#{enabled} enabled, #{disabled} disabled)
            • Status: ✅ #{passing} passing, ❌ #{failing} failing, ⚪ #{not_run} not run

            **Recent Tests:**
            #{test_details}
            #{tests.size > 5 ? "  ... and #{tests.size - 5} more" : ""}

            #{build_recommendations(passing, failing, not_run)}
          MSG
        end

        def build_recommendations(passing, failing, not_run)
          recommendations = []

          if not_run > 0
            recommendations << "💡 You have #{not_run} test#{not_run == 1 ? '' : 's'} that haven't been run yet."
          end

          if failing > 0
            recommendations << "⚠️  You have #{failing} failing test#{failing == 1 ? '' : 's'}. Would you like to investigate?"
          end

          if passing > 0 && failing == 0 && not_run == 0
            recommendations << "🎉 All tests are passing!"
          end

          recommendations.empty? ? "" : "\n" + recommendations.join("\n")
        end

          def build_links(version, tests)
            base_path = "#{engine_base_path}/testing/agents/#{version.agent_id}/versions/#{version.id}"

          links = [
            link("View all tests", "#{base_path}#tests", icon: "list-check"),
            link("Run all tests", "#{base_path}#tests", icon: "play-circle")
          ]

          # Add links to failing tests (first 3)
          failing_tests = tests.select { |t| t.last_run&.passed == false }.first(3)
          failing_tests.each do |test|
            links << link("❌ #{test.name}", "#{base_path}#test-#{test.id}", icon: "x-circle")
          end

          links
        end
      end
    end
  end
end
