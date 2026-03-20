# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_environment_variables
#
#  created_at  :datetime         not null
#  description :text
#  id          :bigint           not null, primary key
#  key         :string           not null
#  name        :string           not null
#  updated_at  :datetime         not null
#  value       :text             not null
#
module PromptTracker
  # Represents a shared environment variable (API key, secret) that can be reused across functions.
  #
  # Environment variables are encrypted at rest and can be associated with multiple
  # FunctionDefinitions through a many-to-many relationship.
  #
  # @example Creating a shared API key
  #   env_var = EnvironmentVariable.create!(
  #     name: "OpenWeather API Key",
  #     key: "OPENWEATHER_API_KEY",
  #     value: "sk_abc123",
  #     description: "API key for OpenWeatherMap service"
  #   )
  #
  # @example Using in a function
  #   function.environment_variables << env_var
  #   function.merged_environment_variables
  #   # => { "OPENWEATHER_API_KEY" => "sk_abc123", ... }
  #
  class EnvironmentVariable < ApplicationRecord
    # Associations
    has_many :function_definition_environment_variables,
             class_name: "PromptTracker::FunctionDefinitionEnvironmentVariable",
             dependent: :destroy,
             inverse_of: :environment_variable

    has_many :function_definitions,
             through: :function_definition_environment_variables,
             class_name: "PromptTracker::FunctionDefinition"

    # Validations
    validates :name, presence: true
    validates :key, presence: true,
                    uniqueness: true,
                    format: {
                      with: /\A[A-Z_][A-Z0-9_]*\z/,
                      message: "must be uppercase with underscores (e.g., API_KEY)"
                    }
    validates :value, presence: true

    # Encrypted attributes
    encrypts :value

    # Scopes
    scope :ordered_by_name, -> { order(:name) }
    scope :search, lambda { |query|
      where("name ILIKE ? OR key ILIKE ? OR description ILIKE ?",
            "%#{query}%", "%#{query}%", "%#{query}%")
    }

    # Display name with key for dropdowns
    # @return [String] formatted name with key
    def display_name
      "#{name} (#{key})"
    end

    # Check if this variable is used by any functions
    # @return [Boolean]
    def in_use?
      function_definitions.exists?
    end

    # Get count of functions using this variable
    # @return [Integer]
    def usage_count
      function_definitions.count
    end
  end
end
