# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Functions
      # Creates a new Dataset for a AgentVersion and optionally kicks off
      # AI-powered row generation.
      #
      # Arguments (raw values collected by the wizard):
      # - agent_version_id: (required) ID of the agent version this dataset belongs to
      # - name: (optional) Raw dataset name from the user
      # - description: (optional) Short description / purpose from the user
      # - dataset_type: (optional) "single_turn" (default) or "conversational"
      # - count: (optional) Number of rows to generate with AI after creation
      # - instructions: (optional) Extra instructions for row generation
      # - model: (optional) Model name to use for row generation
      #
      # The function will:
      # - Enhance the name and description using DatasetEnhancers
      # - Copy schema from the AgentVersion (including conversational fields)
      # - Create the dataset
      # - Optionally enqueue GenerateDatasetRowsJob
      class CreateDataset < Base
        protected

        def execute
          version = find_agent_version
          dataset_type = normalized_dataset_type

          enhanced_name_result = PromptTracker::DatasetEnhancers::NameEnhancer.enhance(
            raw_name: arg(:name),
            testable_name: version.agent.name,
            dataset_type: dataset_type,
            purpose: arg(:description)
          )
          name = enhanced_name_result[:name]

          enhanced_description_result = PromptTracker::DatasetEnhancers::DescriptionEnhancer.enhance(
            name: name,
            raw_description: arg(:description),
            dataset_type: dataset_type,
            testable_name: version.agent.name
          )
          description = enhanced_description_result[:description]

          dataset = version.datasets.build(
            name: name,
            description: description,
            dataset_type: dataset_type,
            created_by: "assistant_chatbot",
            metadata: { "created_via" => "assistant_chatbot" }
          )

          if dataset.save
            enqueue_row_generation_if_requested(dataset)

            success(
              build_success_message(version, dataset),
              links: build_links(version, dataset),
              entities: { dataset_id: dataset.id, agent_version_id: version.id }
            )
          else
            failure(format_errors(dataset))
          end
        end

        def validate_arguments!
          raise ArgumentError, "agent_version_id is required" if arg(:agent_version_id).blank?

          if arg(:dataset_type).present?
            type = arg(:dataset_type).to_s
            unless %w[single_turn conversational].include?(type)
              raise ArgumentError, "dataset_type must be 'single_turn' or 'conversational'"
            end
          end

          if arg(:count).present? && arg(:count).to_i <= 0
            raise ArgumentError, "count must be a positive integer"
          end
        end

        private

        def find_agent_version
          version_id = arg(:agent_version_id)
          version = AgentVersion.find_by(id: version_id)
          raise ArgumentError, "AgentVersion #{version_id} not found" unless version
          version
        end

        def normalized_dataset_type
          (arg(:dataset_type).presence || "single_turn").to_s
        end

        def enqueue_row_generation_if_requested(dataset)
          count = arg(:count).to_i
          return if count <= 0

          GenerateDatasetRowsJob.perform_later(
            dataset.id,
            count: count,
            instructions: arg(:instructions),
            model: arg(:model)
          )
        end

        def build_success_message(version, dataset)
          base = <<~MSG
            ✅ Created dataset "#{dataset.name}" for agent "#{version.agent.name}" (version #{version.name}).

            🔢 Dataset type: #{dataset.dataset_type}
            📊 Variables: #{dataset.variable_names.join(", ")}
          MSG

          if arg(:count).to_i.positive?
            rows = arg(:count).to_i
            base + <<~EXTRA

              🚀 Row generation: Queued job to generate #{rows} row#{rows == 1 ? "" : "s"} with AI.
            EXTRA
          else
            base
          end.strip
        end

        def build_links(version, dataset)
          base_path = "#{engine_base_path}/testing/agents/#{version.agent_id}/versions/#{version.id}"
          datasets_path = "#{base_path}/datasets"

          [
            link("View dataset", "#{datasets_path}/#{dataset.id}", icon: "table"),
            link("View all datasets", datasets_path, icon: "collection"),
            link("Back to agent version", base_path, icon: "arrow-left-circle")
          ]
        end

        def format_errors(dataset)
          errors = dataset.errors.full_messages
          "Failed to create dataset: #{errors.join(', ')}"
        end
      end
    end
  end
end
