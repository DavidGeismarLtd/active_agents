# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Searches for prompts by name or description.
      #
      # This is a query function (does not require confirmation).
      #
      # Arguments:
      # - query: (required) Search query string
      # - limit: (optional) Maximum number of results (default: 5, max: 20)
      #
      # Returns:
      # - List of matching prompts with their latest version
      # - Links to view each prompt
      #
      # @example
      #   function = SearchAgents.new({ query: "customer support" }, {})
      #   result = function.call
      #
      class SearchAgents < Base
        protected

        def execute
          query = arg(:query)
          raise ArgumentError, "query is required" if query.blank?

          limit = (arg(:limit) || 5).to_i.clamp(1, 20)

          prompts = search_prompts(query, limit)

          success(
            build_results_message(query, prompts),
            links: build_links(prompts),
            entities: {
              agent_ids: prompts.map(&:id),
              query: query
            }
          )
        end

        def validate_arguments!
          raise ArgumentError, "query is required" if arg(:query).blank?
        end

        private

        def search_prompts(query, limit)
          # Search in both name and description
          # Using ILIKE for case-insensitive search (PostgreSQL)
          Prompt
            .where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
            .order(updated_at: :desc)
            .limit(limit)
        end

        def build_results_message(query, prompts)
          if prompts.empty?
            return <<~MSG.strip
              🔍 **No prompts found** matching "#{query}"

              Would you like me to create a new prompt with that name?
            MSG
          end

          result_list = prompts.map.with_index do |prompt, idx|
            latest_version = prompt.agent_versions.order(created_at: :desc).first
            version_info = latest_version ? "v#{latest_version.name}" : "no versions"

            # Test info
            test_count = latest_version&.tests&.count || 0
            test_info = if test_count > 0
              passing = latest_version.tests.count { |t| t.last_run&.passed == true }
              failing = latest_version.tests.count { |t| t.last_run&.passed == false }
              " • #{test_count} tests (✅ #{passing}, ❌ #{failing})"
            else
              ""
            end

            <<~ITEM.strip
              #{idx + 1}. **#{prompt.name}** (#{version_info})
                 #{prompt.description.present? ? "   #{prompt.description.truncate(100)}" : "   No description"}#{test_info}
            ITEM
          end.join("\n\n")

          <<~MSG.strip
            🔍 **Found #{prompts.size} prompt#{prompts.size == 1 ? '' : 's'}** matching "#{query}":

            #{result_list}
          MSG
        end

          def build_links(prompts)
          links = []

            prompts.first(5).each do |prompt|
              latest_version = prompt.agent_versions.order(created_at: :desc).first
            if latest_version
                base_path = "#{engine_base_path}/testing/agents/#{prompt.id}/versions/#{latest_version.id}"
              links << link(prompt.name, base_path, icon: "file-text")
            else
                links << link(prompt.name, "#{engine_base_path}/testing/agents/#{prompt.id}", icon: "file-text")
            end
          end

          links
        end
      end
    end
  end
end
