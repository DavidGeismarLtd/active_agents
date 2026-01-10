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
#  response_schema  :jsonb            JSON Schema for structured output
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
    # Include Testable concern for polymorphic interface
    include Testable

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

    # Note: tests, datasets, and test_runs associations are provided by Testable concern

    has_many :evaluator_configs,
             as: :configurable,
             class_name: "PromptTracker::EvaluatorConfig",
             dependent: :destroy

    # Validations
    validates :user_prompt, presence: true
    validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :status, presence: true, inclusion: { in: STATUSES }

    validates :version_number,
              uniqueness: { scope: :prompt_id, message: "already exists for this prompt" }

    validate :user_prompt_immutable_if_responses_exist, on: :update
    validate :variables_schema_must_be_array
    validate :model_config_must_be_hash
    validate :response_schema_must_be_valid_json_schema

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

    # Returns a human-readable name for this version.
    # This provides a consistent interface with Assistant.name
    #
    # @return [String] formatted version name
    #
    # @example
    #   version.name  # => "v1 (active)"
    def name
      display_name = "v#{version_number}"
      display_name += " (#{status})" if status != "active"
      display_name
    end

    # Alias for backwards compatibility
    alias_method :display_name, :name

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
        "response_schema" => response_schema,
        "notes" => notes
      }
    end

    # Checks if this version has monitoring enabled
    #
    # @return [Boolean] true if any evaluator configs exist
    def has_monitoring_enabled?
      evaluator_configs.enabled.exists?
    end

    # Checks if this version has a response schema defined.
    #
    # @return [Boolean] true if response_schema is present
    def has_response_schema?
      response_schema.present?
    end

    # Checks if structured output is enabled and supported.
    #
    # Structured output requires:
    # 1. A response_schema to be defined
    # 2. A model that supports structured outputs (OpenAI gpt-4o family)
    #
    # @return [Boolean] true if structured output can be used
    def structured_output_enabled?
      has_response_schema? && model_supports_structured_output?
    end

    # Returns the list of required properties from the response schema.
    #
    # @return [Array<String>] list of required property names
    def response_schema_required_properties
      return [] unless has_response_schema?

      response_schema["required"] || []
    end

    # Returns the properties defined in the response schema.
    #
    # @return [Hash] the properties hash from the schema
    def response_schema_properties
      return {} unless has_response_schema?

      response_schema["properties"] || {}
    end

    # Run a test with a dataset row (for polymorphic testable interface)
    #
    # @param test [Test] the test to run
    # @param dataset_row [DatasetRow] the dataset row with test variables
    # @return [TestRun] the created test run
    def run_test(test:, dataset_row:)
      # This will be implemented by PromptTestRunner service
      # For now, just create a pending test run
      test.test_runs.create!(
        dataset_id: dataset_row.dataset_id,
        dataset_row_id: dataset_row.id,
        status: "pending"
      )
    end

    # Returns the column headers for the tests table
    #
    # Defines which columns to display in the tests table for this testable type.
    # PromptVersions include a "Template" column to show the user_prompt preview.
    #
    # @return [Array<Hash>] array of column definitions
    def test_table_headers
      [
        { key: "name", label: "Test Name", width: "25%" },
        { key: "template", label: "Template", width: "20%" },
        { key: "evaluator_configs", label: "Evaluator Configs", width: "20%" },
        { key: "status", label: "Last Status", width: "8%" },
        { key: "last_run", label: "Last Run", width: "10%" },
        { key: "total_runs", label: "Total Runs", width: "8%", align: "end" },
        { key: "actions", label: "Actions", width: "9%" }
      ]
    end

    # Returns the column headers for the test runs table
    #
    # Defines which columns to display in the test runs accordion for this testable type.
    # PromptVersions show rendered prompt and response instead of conversation data.
    #
    # @return [Array<Hash>] array of column definitions
    def test_run_table_headers
      [
        { key: "run_status", label: "Status", width: "10%" },
        { key: "run_time", label: "Run Time", width: "12%" },
        { key: "response_time", label: "Response Time", width: "10%" },
        { key: "run_cost", label: "Cost", width: "8%" },
        { key: "rendered_prompt", label: "Rendered Prompt", width: "20%" },
        { key: "run_response", label: "Response", width: "20%" },
        { key: "run_evaluations", label: "Evaluations", width: "10%" },
        { key: "human_evaluations", label: "Human Evaluations", width: "10%" },
        { key: "actions", label: "Actions", width: "5%" }
      ]
    end

    # Returns the locals hash needed for rendering the test row partial
    #
    # @param test [Test] the test to render
    # @return [Hash] the locals hash with test, version, and prompt
    def test_row_locals(test)
      { test: test, version: self }
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

    # Validates that response_schema is a valid JSON Schema structure.
    #
    # A valid JSON Schema must:
    # 1. Be a Hash
    # 2. Have a "type" property (typically "object" for structured outputs)
    # 3. Have "properties" when type is "object"
    def response_schema_must_be_valid_json_schema
      return if response_schema.blank?

      unless response_schema.is_a?(Hash)
        errors.add(:response_schema, "must be a valid JSON Schema (Hash)")
        return
      end

      unless response_schema["type"].present?
        errors.add(:response_schema, "must have a 'type' property")
        return
      end

      if response_schema["type"] == "object" && response_schema["properties"].blank?
        errors.add(:response_schema, "must have 'properties' when type is 'object'")
      end
    end

    # Checks if the configured model supports structured outputs.
    #
    # Currently, structured outputs are supported by:
    # - OpenAI: gpt-4o, gpt-4o-mini, gpt-4o-2024-08-06 and newer
    # - Anthropic: claude-3-5-sonnet (via tool use)
    #
    # @return [Boolean] true if the model supports structured outputs
    def model_supports_structured_output?
      return false if model_config.blank?

      provider = model_config["provider"]&.to_s
      model = model_config["model"]&.to_s

      case provider
      when "openai"
        # gpt-4o family supports structured outputs
        model&.start_with?("gpt-4o") || model&.start_with?("gpt-4-turbo")
      when "anthropic"
        # Claude 3.5 supports structured outputs via tool use
        model&.include?("claude-3")
      else
        false
      end
    end

    # Returns the API type for this PromptVersion based on the model_config provider.
    #
    # The API type determines:
    # - Which evaluators are compatible with this PromptVersion
    # - How response data should be normalized before evaluation
    #
    # @return [Symbol] the API type constant from PromptTracker::ApiTypes
    #
    # @example OpenAI Chat Completion provider
    #   version.api_type # => :openai_chat_completion
    #
    # @example OpenAI Responses provider
    #   version.api_type # => :openai_response_api
    #
    # @example Anthropic provider
    #   version.api_type # => :anthropic_messages
    #
    def api_type
      return ApiTypes::OPENAI_CHAT_COMPLETION if model_config.blank?

      provider = model_config["provider"]&.to_s

      case provider
      when "openai"
        ApiTypes::OPENAI_CHAT_COMPLETION
      when "openai_responses"
        ApiTypes::OPENAI_RESPONSE_API
      when "anthropic"
        ApiTypes::ANTHROPIC_MESSAGES
      else
        # Unknown provider - assume Chat Completion style
        ApiTypes::OPENAI_CHAT_COMPLETION
      end
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
