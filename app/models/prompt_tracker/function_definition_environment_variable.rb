# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_function_definition_environment_variables
#
#  created_at              :datetime         not null
#  environment_variable_id :bigint           not null
#  function_definition_id  :bigint           not null
#  id                      :bigint           not null, primary key
#  updated_at              :datetime         not null
#
module PromptTracker
  # Join model for the many-to-many relationship between FunctionDefinitions and EnvironmentVariables.
  #
  # This allows functions to share environment variables (API keys, secrets) while
  # maintaining the flexibility to have function-specific variables as well.
  #
  class FunctionDefinitionEnvironmentVariable < ApplicationRecord
    # Associations
    belongs_to :function_definition,
               class_name: "PromptTracker::FunctionDefinition",
               inverse_of: :function_definition_environment_variables

    belongs_to :environment_variable,
               class_name: "PromptTracker::EnvironmentVariable",
               inverse_of: :function_definition_environment_variables

    # Validations
    validates :function_definition_id, uniqueness: { scope: :environment_variable_id }
  end
end
