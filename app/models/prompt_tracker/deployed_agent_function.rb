# frozen_string_literal: true

module PromptTracker
  # Join model for the many-to-many relationship between DeployedAgents and FunctionDefinitions.
  #
  # This tracks which functions are available to each deployed agent.
  #
  class DeployedAgentFunction < ApplicationRecord
    # Associations
    belongs_to :deployed_agent,
               class_name: "PromptTracker::DeployedAgent",
               inverse_of: :deployed_agent_functions

    belongs_to :function_definition,
               class_name: "PromptTracker::FunctionDefinition",
               inverse_of: :deployed_agent_functions

    # Validations
    validates :deployed_agent_id, uniqueness: { scope: :function_definition_id }
  end
end
