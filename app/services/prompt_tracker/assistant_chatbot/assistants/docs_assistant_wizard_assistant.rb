# frozen_string_literal: true

module PromptTracker
  module AssistantChatbot
    module Assistants
      # Default assistant focused on answering questions using the in-app docs
      # under app/views/prompt_tracker/docs.
      #
      # This assistant executes NO tools / functions.
      class DocsAssistantWizardAssistant
        def initialize(context: {})
          @context = context || {}
        end

        def allowed_tool_names
          []
        end

        def system_prompt
          <<~PROMPT.strip
            You are the PromptTracker Documentation Assistant.

            Your job is to answer the user's question using the PromptTracker documentation excerpts
            that will be provided inside the user's message.

            Rules:
            - Do NOT invent features or UI that is not mentioned in the excerpts.
            - If the excerpts don't contain the answer, say so and suggest which docs page to read.
            - When helpful, reference the relevant docs route (e.g. #{engine_base_path}/docs/testing_guide).
            - Do NOT output JSON tool calls. You have NO tools.
          PROMPT
        end

        private

        attr_reader :context

        # Get the engine's mounted base path dynamically.
        # @return [String] base path without trailing slash
        def engine_base_path
          url_options = PromptTracker.configuration.url_options_provider&.call || {}
          PromptTracker::Engine.routes.url_helpers.root_path(url_options).chomp("/")
        end
      end
    end
  end
end
