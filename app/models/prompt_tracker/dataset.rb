# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_datasets
#
#  id                 :bigint           not null, primary key
#  name               :string           not null
#  description        :text
#  schema             :jsonb            not null
#  created_by         :string
#  metadata           :jsonb            not null
#  dataset_type       :integer          default(0), not null  # 0=single_turn, 1=conversational
#  testable_type      :string
#  testable_id        :bigint
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
module PromptTracker
  # Represents a reusable collection of test data for any testable (PromptVersion or Assistant).
  #
  # A Dataset stores multiple rows of test scenario data that can be used
  # to run tests at scale. Each dataset is tied to a specific testable
  # and validates that its schema matches the testable's variables_schema.
  #
  # The schema is automatically copied from testable.variables_schema on creation.
  # All testables must implement the variables_schema method (via Testable concern).
  #
  # @example Create a dataset for a PromptVersion
  #   dataset = Dataset.create!(
  #     testable: prompt_version,
  #     name: "customer_scenarios",
  #     description: "Common customer support scenarios"
  #     # schema is automatically set from prompt_version.variables_schema
  #   )
  #
  # @example Create a dataset for an Assistant
  #   dataset = Dataset.create!(
  #     testable: assistant,
  #     name: "headache_scenarios",
  #     description: "Different headache complaint scenarios"
  #     # schema is automatically set from assistant.variables_schema
  #   )
  #
  # @example Add rows to dataset
  #   dataset.dataset_rows.create!(
  #     row_data: { interlocutor_simulation_prompt: "You are a patient with a severe headache...", max_turns: 10 },
  #     source: "manual"
  #   )
  #
  class Dataset < ApplicationRecord
    # Dataset type enum: determines what kind of test data this contains
    enum :dataset_type, { single_turn: 0, conversational: 1 }, default: :single_turn

    # Additional fields required for conversational datasets
    CONVERSATIONAL_FIELDS = [
      { "name" => "interlocutor_simulation_prompt", "type" => "text", "required" => true },
      { "name" => "max_turns", "type" => "integer", "required" => false, "default" => 5 }
    ].freeze

    # Polymorphic association - can belong to PromptVersion or Assistant
    belongs_to :testable, polymorphic: true

    has_many :dataset_rows,
             class_name: "PromptTracker::DatasetRow",
             dependent: :destroy,
             inverse_of: :dataset

    has_many :test_runs,
             class_name: "PromptTracker::TestRun",
             dependent: :nullify,
             inverse_of: :dataset

    # Backward compatibility
    has_many :prompt_test_runs,
             class_name: "PromptTracker::TestRun",
             foreign_key: :dataset_id,
             dependent: :nullify

    # Validations
    validates :name, presence: true, uniqueness: { scope: [ :testable_type, :testable_id ] }
    validates :testable, presence: true
    validates :schema, presence: true

    validate :schema_must_be_array
    validate :schema_matches_testable

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :by_name, -> { order(:name) }
    scope :for_prompt_versions, -> { where(testable_type: "PromptTracker::PromptVersion") }
    scope :for_assistants, -> { where(testable_type: "PromptTracker::Openai::Assistant") }
    scope :single_turn_datasets, -> { where(dataset_type: :single_turn) }
    scope :conversational_datasets, -> { where(dataset_type: :conversational) }

    # Callbacks
    before_validation :copy_schema_from_testable, on: :create, if: -> { schema.blank? }

    # Get row count
    #
    # @return [Integer] number of rows in dataset
    def row_count
      dataset_rows.count
    end

    # Check if dataset schema is still valid for its testable
    #
    # @return [Boolean] true if schema matches current testable schema
    def schema_valid?
      return false unless testable

      # For conversational datasets, required_schema includes CONVERSATIONAL_FIELDS
      # even if testable.variables_schema is empty, so we compare against required_schema
      expected_schema = required_schema

      # A dataset is valid if it has a schema matching the expected schema
      # (empty schema for single-turn testables with no variables is also valid)
      return true if schema.blank? && expected_schema.blank?

      # Schema is valid if it matches the expected schema (excluding description field)
      normalize_schema(schema) == normalize_schema(expected_schema)
    end

    # Get the required schema for this dataset type
    # Conversational datasets need additional fields for interlocutor simulation
    #
    # @return [Array<Hash>] the required schema fields
    def required_schema
      base_schema = testable&.variables_schema || []

      return base_schema if single_turn?

      # Conversational datasets need additional fields
      base_schema + CONVERSATIONAL_FIELDS
    end

    # Get variable names from schema
    #
    # @return [Array<String>] list of variable names
    def variable_names
      schema.map { |var| var["name"] }.compact
    end

    private

    # Copy schema from testable on creation
    # Uses required_schema which includes conversational fields if dataset_type is conversational
    def copy_schema_from_testable
      return unless testable

      self.schema = required_schema
    end

    # Validate that schema is an array
    def schema_must_be_array
      return if schema.nil? || schema.is_a?(Array)

      errors.add(:schema, "must be an array")
    end

    # Validate that schema matches testable's expected schema
    def schema_matches_testable
      return unless testable
      return unless schema.is_a?(Array) # Skip if schema is not an array (handled by schema_must_be_array)

      unless schema_valid?
        errors.add(:schema, "does not match testable's expected schema. Dataset is invalid.")
      end
    end

    # Normalize schema for comparison (sort by name, exclude description)
    def normalize_schema(schema_array)
      return [] if schema_array.blank?
      return [] unless schema_array.is_a?(Array)

      # Extract only name, type, and required fields for comparison (ignore description)
      schema_array.map do |var|
        {
          "name" => var["name"],
          "type" => var["type"],
          "required" => var["required"]
        }
      end.sort_by { |var| var["name"] }
    end
  end
end
