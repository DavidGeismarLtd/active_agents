# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_versions
#
#  created_at       :datetime         not null
#  created_by       :string
#  id               :bigint           not null, primary key
#  model_config     :jsonb
#  notes            :text
#  prompt_id        :bigint           not null
#  status           :string           default("draft"), not null
#  system_prompt    :text
#  user_prompt      :text             not null
#  updated_at       :datetime         not null
#  variables_schema :jsonb
#  version_number   :integer          not null
#
module PromptTracker
  # Represents a specific version of a prompt.
  #
  # PromptVersions are immutable once they have LLM responses. This ensures
  # historical accuracy and reproducibility of results.
  #
  # Each version has:
  # - system_prompt: Optional instructions that set the AI's role and behavior
  # - user_prompt: The main prompt template with variables (required)
  #
  # @example Creating a new version
  #   version = prompt.prompt_versions.create!(
  #     system_prompt: "You are a helpful customer support agent.",
  #     user_prompt: "Hello {{name}}, how can I help?",
  #     version_number: 1,
  #     status: "active",
  #     variables_schema: [
  #       { "name" => "name", "type" => "string", "required" => true }
  #     ]
  #   )
  #
  # @example Rendering the user prompt
  #   rendered = version.render(name: "John")
  #   # => "Hello John, how can I help?"
  #
  # @example Activating a version
  #   version.activate!
  #   # Marks this version as active and deprecates others
  #
  class PromptVersion < ApplicationRecord
    # Constants
    STATUSES = %w[active deprecated draft].freeze

    # Associations
    belongs_to :prompt,
               class_name: "PromptTracker::Prompt",
               inverse_of: :prompt_versions

    has_many :llm_responses,
             class_name: "PromptTracker::LlmResponse",
             dependent: :restrict_with_error,
             inverse_of: :prompt_version

    has_many :evaluations,
             through: :llm_responses,
             class_name: "PromptTracker::Evaluation"

    has_many :prompt_tests,
             class_name: "PromptTracker::PromptTest",
             dependent: :destroy,
             inverse_of: :prompt_version

    has_many :evaluator_configs,
             as: :configurable,
             class_name: "PromptTracker::EvaluatorConfig",
             dependent: :destroy

    has_many :datasets,
             class_name: "PromptTracker::Dataset",
             dependent: :destroy,
             inverse_of: :prompt_version

    # Validations
    validates :user_prompt, presence: true
    validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :status, presence: true, inclusion: { in: STATUSES }

    validates :version_number,
              uniqueness: { scope: :prompt_id, message: "already exists for this prompt" }

    validate :user_prompt_immutable_if_responses_exist, on: :update
    validate :variables_schema_must_be_array
    validate :model_config_must_be_hash

    # Callbacks
    before_validation :set_next_version_number, on: :create, if: -> { version_number.nil? }
    before_validation :extract_variables_schema, if: :should_extract_variables?

    # Scopes

    # Returns only active versions
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :active, -> { where(status: "active") }

    # Returns only deprecated versions
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :deprecated, -> { where(status: "deprecated") }

    # Returns only draft versions
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :draft, -> { where(status: "draft") }

    # Returns versions ordered by version number (newest first)
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :by_version, -> { order(version_number: :desc) }

    # Instance Methods

    # Renders the user prompt with the provided variables using Liquid template engine.
    #
    # @param variables [Hash] the variables to substitute
    # @return [String] the rendered user prompt
    # @raise [ArgumentError] if required variables are missing
    # @raise [Liquid::SyntaxError] if Liquid template has syntax errors
    #
    # @example Render user prompt
    #   version.render(name: "John", issue: "billing")
    #   # => "Hello John, how can I help with billing?"
    #
    # @example Render with Liquid filters
    #   version.render({ name: "john" })
    #   # => "Hello JOHN!" (if user_prompt uses {{ name | upcase }})
    def render(variables = {})
      variables = variables.with_indifferent_access
      validate_required_variables!(variables)

      renderer = TemplateRenderer.new(user_prompt)
      renderer.render(variables)
    end

    # Activates this version and deprecates all other versions of the same prompt.
    #
    # @return [Boolean] true if successful
    # @raise [ActiveRecord::RecordInvalid] if validation fails
    def activate!
      transaction do
        # Deprecate all other versions
        prompt.prompt_versions.where.not(id: id).update_all(status: "deprecated")

        # Activate this version
        update!(status: "active")
      end
      true
    end

    # Marks this version as deprecated.
    #
    # @return [Boolean] true if successful
    def deprecate!
      update!(status: "deprecated")
    end

    # Checks if this version is active.
    #
    # @return [Boolean] true if status is "active"
    def active?
      status == "active"
    end

    # Checks if this version is deprecated.
    #
    # @return [Boolean] true if status is "deprecated"
    def deprecated?
      status == "deprecated"
    end

    # Checks if this version is a draft.
    #
    # @return [Boolean] true if status is "draft"
    def draft?
      status == "draft"
    end

    # Returns a display name for this version.
    #
    # @return [String] formatted version name
    #
    # @example
    #   version.display_name  # => "v1 (active)"
    def display_name
      name = "v#{version_number}"
      name += " (#{status})" if status != "active"
      name
    end

    # Checks if this version has any LLM responses.
    #
    # @return [Boolean] true if responses exist
    def has_responses?
      llm_responses.exists?
    end

    # Returns the average response time for this version.
    #
    # @return [Float, nil] average response time in milliseconds
    def average_response_time_ms
      llm_responses.average(:response_time_ms)&.to_f
    end

    # Returns the total cost for this version.
    #
    # @return [Float] total cost in USD
    def total_cost_usd
      llm_responses.sum(:cost_usd) || 0.0
    end

    # Returns the total number of LLM calls for this version.
    #
    # @return [Integer] total count
    def total_llm_calls
      llm_responses.count
    end

    # Exports this version to YAML format.
    #
    # @return [Hash] YAML-compatible hash
    def to_yaml_export
      {
        "name" => prompt.name,
        "description" => prompt.description,
        "category" => prompt.category,
        "system_prompt" => system_prompt,
        "user_prompt" => user_prompt,
        "variables" => variables_schema,
        "model_config" => model_config,
        "notes" => notes
      }
    end

    # Checks if this version has monitoring enabled
    #
    # @return [Boolean] true if any evaluator configs exist
    def has_monitoring_enabled?
      evaluator_configs.enabled.exists?
    end

    private

    # Sets the next version number based on existing versions
    def set_next_version_number
      max_version = prompt.prompt_versions.maximum(:version_number) || 0
      self.version_number = max_version + 1
    end

    # Validates that required variables are provided
    def validate_required_variables!(variables)
      return if variables_schema.blank?

      required_vars = variables_schema.select { |v| v["required"] == true }.map { |v| v["name"] }
      missing_vars = required_vars - variables.keys.map(&:to_s)

      return if missing_vars.empty?

      raise ArgumentError, "Missing required variables: #{missing_vars.join(', ')}"
    end

    # Prevents user_prompt changes if responses exist
    def user_prompt_immutable_if_responses_exist
      return unless user_prompt_changed? && has_responses?

      errors.add(:user_prompt, "cannot be changed after responses exist")
    end

    # Validates that variables_schema is an array
    def variables_schema_must_be_array
      return if variables_schema.nil? || variables_schema.is_a?(Array)

      errors.add(:variables_schema, "must be an array")
    end

    # Validates that model_config is a hash
    def model_config_must_be_hash
      return if model_config.nil? || model_config.is_a?(Hash)

      errors.add(:model_config, "must be a hash")
    end

    # Determines if variables should be extracted from user_prompt
    def should_extract_variables?
      # Only extract if:
      # 1. User prompt has changed (or is new)
      # 2. Variables schema is blank (not explicitly set)
      user_prompt.present? && (user_prompt_changed? || new_record?) && variables_schema.blank?
    end

    # Extracts variables from user_prompt and populates variables_schema
    def extract_variables_schema
      return if user_prompt.blank?

      variable_names = extract_variable_names_from_template(user_prompt)
      return if variable_names.empty?

      # Build schema with default type and required settings
      self.variables_schema = variable_names.map do |var_name|
        {
          "name" => var_name,
          "type" => "string",
          "required" => false
        }
      end
    end

    # Extract variable names from user_prompt
    # Supports both {{variable}} and {{ variable }} syntax
    def extract_variable_names_from_template(template_string)
      return [] if template_string.blank?

      variables = []

      # Extract Mustache-style variables: {{variable}}
      variables += template_string.scan(/\{\{\s*(\w+)\s*\}\}/).flatten

      # Extract Liquid variables with filters: {{ variable | filter }}
      variables += template_string.scan(/\{\{\s*(\w+)\s*\|/).flatten

      # Extract Liquid object notation: {{ object.property }}
      variables += template_string.scan(/\{\{\s*(\w+)\./).flatten

      # Extract from conditionals: {% if variable %}
      variables += template_string.scan(/\{%\s*if\s+(\w+)/).flatten

      # Extract from loops: {% for item in items %}
      variables += template_string.scan(/\{%\s*for\s+\w+\s+in\s+(\w+)/).flatten

      variables.uniq.sort
    end
  end
end
