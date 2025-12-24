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
  # and validates that its schema matches the testable's expected schema.
  #
  # For PromptVersions: schema matches variables_schema
  # For Assistants: schema includes user_prompt, max_turns, etc.
  #
  # @example Create a dataset for a PromptVersion
  #   dataset = Dataset.create!(
  #     testable: prompt_version,
  #     name: "customer_scenarios",
  #     description: "Common customer support scenarios",
  #     schema: prompt_version.variables_schema
  #   )
  #
  # @example Create a dataset for an Assistant
  #   dataset = Dataset.create!(
  #     testable: assistant,
  #     name: "headache_scenarios",
  #     description: "Different headache complaint scenarios",
  #     schema: [
  #       { "name" => "user_prompt", "type" => "string", "required" => true },
  #       { "name" => "max_turns", "type" => "integer", "required" => false }
  #     ]
  #   )
  #
  # @example Add rows to dataset
  #   dataset.dataset_rows.create!(
  #     row_data: { user_prompt: "I have a severe headache...", max_turns: 10 },
  #     source: "manual"
  #   )
  #
  class Dataset < ApplicationRecord
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
    validates :name, presence: true
    validates :testable, presence: true
    validates :schema, presence: true

    validate :schema_must_be_array
    validate :schema_matches_testable

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :by_name, -> { order(:name) }
    scope :for_prompt_versions, -> { where(testable_type: "PromptTracker::PromptVersion") }
    scope :for_assistants, -> { where(testable_type: "PromptTracker::Openai::Assistant") }

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

      expected_schema = case testable
      when PromptVersion
        testable.variables_schema
      when Openai::Assistant
        # Assistants have a fixed schema for conversation scenarios
        [
          { "name" => "user_prompt", "type" => "string", "required" => true },
          { "name" => "max_turns", "type" => "integer", "required" => false }
        ]
      else
        []
      end

      return false if expected_schema.blank?

      # Schema is valid if it matches the expected schema
      normalize_schema(schema) == normalize_schema(expected_schema)
    end

    # Get variable names from schema
    #
    # @return [Array<String>] list of variable names
    def variable_names
      schema.map { |var| var["name"] }.compact
    end

    private

    # Copy schema from testable on creation
    def copy_schema_from_testable
      return unless testable

      self.schema = case testable
      when PromptVersion
        testable.variables_schema
      when Openai::Assistant
        [
          { "name" => "user_prompt", "type" => "string", "required" => true },
          { "name" => "max_turns", "type" => "integer", "required" => false }
        ]
      else
        []
      end
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

    # Normalize schema for comparison (sort by name)
    def normalize_schema(schema_array)
      return [] if schema_array.blank?
      return [] unless schema_array.is_a?(Array)

      schema_array.sort_by { |var| var["name"] }
    end
  end
end
