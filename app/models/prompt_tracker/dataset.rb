# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_datasets
#
#  created_at        :datetime         not null
#  created_by        :string
#  description       :text
#  id                :bigint           not null, primary key
#  metadata          :jsonb            not null
#  name              :string           not null
#  prompt_version_id :bigint           not null
#  schema            :jsonb            not null
#  updated_at        :datetime         not null
#
module PromptTracker
  # Represents a reusable collection of test data for a prompt version.
  #
  # A Dataset stores multiple rows of variable values that can be used
  # to run tests at scale. Each dataset is tied to a specific prompt version
  # and validates that its schema matches the version's variables_schema.
  #
  # @example Create a dataset
  #   dataset = Dataset.create!(
  #     prompt_version: version,
  #     name: "customer_scenarios",
  #     description: "Common customer support scenarios",
  #     schema: version.variables_schema
  #   )
  #
  # @example Add rows to dataset
  #   dataset.dataset_rows.create!(
  #     row_data: { customer_name: "Alice", issue: "billing" },
  #     source: "manual"
  #   )
  #
  class Dataset < ApplicationRecord
    # Associations
    belongs_to :prompt_version,
               class_name: "PromptTracker::PromptVersion",
               inverse_of: :datasets

    has_many :dataset_rows,
             class_name: "PromptTracker::DatasetRow",
             dependent: :destroy,
             inverse_of: :dataset

    has_many :prompt_test_runs,
             class_name: "PromptTracker::PromptTestRun",
             dependent: :nullify,
             inverse_of: :dataset

    # Delegate to get the prompt through prompt_version
    has_one :prompt, through: :prompt_version

    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { scope: :prompt_version_id }
    validates :schema, presence: true

    validate :schema_must_be_array
    validate :schema_matches_prompt_version

    # Scopes
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :copy_schema_from_version, on: :create, if: -> { schema.blank? }

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :by_name, -> { order(:name) }

    # Get row count
    #
    # @return [Integer] number of rows in dataset
    def row_count
      dataset_rows.count
    end

    # Check if dataset schema is still valid for its prompt version
    #
    # @return [Boolean] true if schema matches current version schema
    def schema_valid?
      return false if prompt_version.variables_schema.blank?

      # Schema is valid if it matches the current version's schema
      normalize_schema(schema) == normalize_schema(prompt_version.variables_schema)
    end

    # Get variable names from schema
    #
    # @return [Array<String>] list of variable names
    def variable_names
      schema.map { |var| var["name"] }.compact
    end

    private

    # Copy schema from prompt version on creation
    def copy_schema_from_version
      self.schema = prompt_version.variables_schema if prompt_version
    end

    # Validate that schema is an array
    def schema_must_be_array
      return if schema.nil? || schema.is_a?(Array)

      errors.add(:schema, "must be an array")
    end

    # Validate that schema matches prompt version's variables_schema
    def schema_matches_prompt_version
      return if prompt_version.blank?
      return if prompt_version.variables_schema.blank?
      return unless schema.is_a?(Array) # Skip if schema is not an array (handled by schema_must_be_array)

      unless schema_valid?
        errors.add(:schema, "does not match prompt version's variables schema. Dataset is invalid.")
      end
    end

    # Normalize schema for comparison (sort by name)
    def normalize_schema(schema_array)
      return [] if schema_array.blank?
      return [] unless schema_array.is_a?(Array)

      schema_array.sort_by { |var| var["name"] }
    end
  end
end
