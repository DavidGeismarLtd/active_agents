# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_versions
#
#  archived_at      :datetime
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

    # Structural model config keys that force new version when changed in testing state
    STRUCTURAL_MODEL_CONFIG_KEYS = %w[provider api model tool_config].freeze

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

    validate :enforce_version_immutability, on: :update
    validate :variables_schema_must_be_array
    validate :model_config_must_be_hash
    validate :model_config_tool_config_structure
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

    # Returns only non-archived versions (default scope behavior)
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :not_archived, -> { where(archived_at: nil) }

    # Returns only archived versions
    # @return [ActiveRecord::Relation<PromptVersion>]
    scope :archived, -> { where.not(archived_at: nil) }

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

    # Archives this version (soft delete).
    # Does NOT delete remote entities (e.g., OpenAI Assistants).
    #
    # @return [Boolean] true if successful
    def archive!
      update!(archived_at: Time.current)
    end

    # Unarchives this version.
    #
    # @return [Boolean] true if successful
    def unarchive!
      update!(archived_at: nil)
    end

    # Checks if this version is archived.
    #
    # @return [Boolean] true if archived
    def archived?
      archived_at.present?
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

    # Checks if this version has any tests.
    #
    # @return [Boolean] true if tests exist
    def has_tests?
      tests.exists?
    end

    # Checks if this version has any datasets.
    #
    # @return [Boolean] true if datasets exist
    def has_datasets?
      datasets.exists?
    end

    # Version State Methods
    # =====================
    # A PromptVersion can be in one of three states based on its associations:
    # - Development: No tests, no datasets, no llm_responses → free editing of all fields
    # - Testing: Has tests OR datasets (no llm_responses) → structural changes force new version
    # - Production: Has llm_responses → all changes force new version (immutable)

    # Checks if this version is in development state.
    # In development state, all fields can be freely edited.
    #
    # @return [Boolean] true if no tests, datasets, or responses exist
    def development_state?
      !has_responses? && !has_tests? && !has_datasets?
    end

    # Checks if this version is in testing state.
    # In testing state, structural changes force new version creation.
    #
    # @return [Boolean] true if has tests or datasets but no responses
    def testing_state?
      !has_responses? && (has_tests? || has_datasets?)
    end

    # Checks if this version is in production state.
    # In production state, all changes force new version creation.
    #
    # @return [Boolean] true if has responses
    def production_state?
      has_responses?
    end

    # Returns the current version state as a symbol.
    #
    # @return [Symbol] :development, :testing, or :production
    def version_state
      if production_state?
        :production
      elsif testing_state?
        :testing
      else
        :development
      end
    end

    # Checks if structural fields have changed.
    # Structural fields are those that would break dataset compatibility or change API behavior.
    #
    # @return [Boolean] true if any structural field has changed
    def structural_fields_changed?
      return true if variables_schema_changed?
      return true if response_schema_changed?
      return true if structural_model_config_changed?

      false
    end

    # Checks if structural model_config keys have changed.
    # These are: provider, api, model, tool_config
    #
    # @return [Boolean] true if any structural model_config key has changed
    def structural_model_config_changed?
      return false unless model_config_changed?

      old_config = model_config_was || {}
      new_config = model_config || {}

      STRUCTURAL_MODEL_CONFIG_KEYS.any? do |key|
        old_config[key] != new_config[key]
      end
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

    # Returns the locals hash needed for rendering the test row partial
    #
    # @param test [Test] the test to render
    # @return [Hash] the locals hash with test, version, and prompt
    def test_row_locals(test)
      { test: test, version: self }
    end

    # Returns the API type for this prompt version based on model_config
    #
    # Converts the provider and api from model_config into a standardized API type symbol.
    #
    # @return [Symbol, nil] the API type constant from PromptTracker::ApiTypes
    #
    # @example OpenAI Chat Completions
    #   version.api_type # => :openai_chat_completions
    #
    # @example OpenAI Responses
    #   version.api_type # => :openai_responses
    #
    # @example Anthropic Messages
    #   version.api_type # => :anthropic_messages
    #
    def api_type
      return nil if model_config.blank?

      provider = model_config["provider"]&.to_sym
      api = model_config["api"]&.to_sym

      return nil unless provider && api

      ApiTypes.from_config(provider, api)
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

    # Enforces version immutability rules based on version state.
    #
    # Version states and allowed changes:
    # - Development (no tests/datasets/responses): All changes allowed
    # - Testing (has tests or datasets): Structural changes blocked
    # - Production (has responses): All significant changes blocked
    def enforce_version_immutability
      if production_state?
        # Production: no changes to any significant field
        if user_prompt_changed? || system_prompt_changed? ||
           model_config_changed? || variables_schema_changed? || response_schema_changed?
          errors.add(:base, "Cannot modify version with production responses. Create a new version instead.")
        end
      elsif testing_state?
        # Testing: only structural fields are blocked
        if structural_fields_changed?
          errors.add(:base, "Cannot modify structural fields (provider, api, model, tools, variables, response_schema) when tests or datasets exist. Create a new version instead.")
        end
      end
      # Development state: all changes allowed
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

    # Validates that model_config has proper tool_config structure when tools are present
    #
    # Ensures that:
    # 1. tool_config is a hash if present (can be empty for tools that don't need config)
    # 2. tool_config structure is valid (file_search has vector_store_ids array, etc.)
    #
    # Note: Not all tools require configuration (e.g., code_interpreter has no config),
    # so an empty tool_config hash is valid even when tools array is populated.
    def model_config_tool_config_structure
      return if model_config.blank?

      tool_config = model_config["tool_config"]

      # If tool_config is present, validate its structure
      if tool_config.present?
        unless tool_config.is_a?(Hash)
          errors.add(:model_config, "tool_config must be a hash")
          return
        end

        # Validate file_search configuration if present
        validate_file_search_config(tool_config["file_search"]) if tool_config["file_search"].present?

        # Validate functions configuration if present
        validate_functions_config(tool_config["functions"]) if tool_config["functions"].present?
      end
    end

    # Validates file_search configuration structure
    def validate_file_search_config(file_search_config)
      unless file_search_config.is_a?(Hash)
        errors.add(:model_config, "tool_config.file_search must be a hash")
        return
      end

      # vector_store_ids should be an array if present
      if file_search_config["vector_store_ids"].present?
        unless file_search_config["vector_store_ids"].is_a?(Array)
          errors.add(:model_config, "tool_config.file_search.vector_store_ids must be an array")
        end
      end
    end

    # Validates functions configuration structure
    def validate_functions_config(functions_config)
      unless functions_config.is_a?(Array)
        errors.add(:model_config, "tool_config.functions must be an array")
      end
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
