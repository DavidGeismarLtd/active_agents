# frozen_string_literal: true

module PromptTracker
  module Testing
    module Openai
      # Controller for managing datasets for OpenAI Assistants in the Testing section
      #
      # Datasets for assistants contain conversation scenarios with:
      # - interlocutor_simulation_prompt: A prompt that describes the persona, scenario, and behavior of the simulated user
      # - max_turns: Maximum conversation turns (optional)
      #
      # This controller inherits all CRUD logic from DatasetsControllerBase.
      # The schema is automatically set by the Dataset model's before_validation callback.
      #
      class AssistantDatasetsController < DatasetsControllerBase
        private

        # Set the testable (Assistant) and related instance variables
        def set_testable
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id])
          @testable = @assistant
        end
      end
    end
  end
end
