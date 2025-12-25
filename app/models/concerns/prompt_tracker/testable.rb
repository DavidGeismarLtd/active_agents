# frozen_string_literal: true

module PromptTracker
  # Shared interface for all testable models (PromptVersion, Assistant, etc.)
  #
  # This concern defines the common behavior and associations that all testable
  # models must implement. It ensures a consistent polymorphic interface across
  # different testable types.
  #
  # Required methods that including classes must implement:
  # - variables_schema: Returns the schema definition for dataset variables
  # - name: Returns a human-readable name for the testable
  #
  # @example Include in a model
  #   class PromptVersion < ApplicationRecord
  #     include Testable
  #
  #     # variables_schema is already a database column, so it's automatically available
  #   end
  #
  # @example Include in Assistant
  #   class Assistant < ApplicationRecord
  #     include Testable
  #
  #     def variables_schema
  #       [
  #         { "name" => "interlocutor_simulation_prompt", "type" => "text", "required" => true },
  #         { "name" => "max_turns", "type" => "integer", "required" => false }
  #       ]
  #     end
  #   end
  #
  module Testable
    extend ActiveSupport::Concern

    included do
      # Polymorphic associations
      has_many :tests,
               as: :testable,
               class_name: "PromptTracker::Test",
               dependent: :destroy

      has_many :datasets,
               as: :testable,
               class_name: "PromptTracker::Dataset",
               dependent: :destroy

      has_many :test_runs,
               through: :tests,
               class_name: "PromptTracker::TestRun"
    end

    # Interface documentation for methods that all testables must implement
    #
    # Including classes must provide these methods:
    #
    # 1. variables_schema
    #    Returns the variables schema for this testable.
    #    The schema defines what variables/fields are expected in dataset rows.
    #    Each schema entry should have: name, type, required
    #
    #    @return [Array<Hash>] array of variable definitions
    #
    #    @example PromptVersion schema (from database column)
    #      [
    #        { "name" => "customer_name", "type" => "string", "required" => true },
    #        { "name" => "issue", "type" => "text", "required" => false }
    #      ]
    #
    #    @example Assistant schema (implemented as method)
    #      [
    #        { "name" => "interlocutor_simulation_prompt", "type" => "text", "required" => true },
    #        { "name" => "max_turns", "type" => "integer", "required" => false }
    #      ]
    #
    # 2. name
    #    Returns a human-readable name for this testable
    #
    #    @return [String] the name
    #
    #    @example PromptVersion
    #      "v1" or "v2 (draft)"
    #
    #    @example Assistant
    #      "Medical Support Assistant"
  end
end
