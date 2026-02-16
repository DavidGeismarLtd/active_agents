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

    # Build a placeholder example for mock_function_outputs based on testable's functions
    #
    # This method generates a JSON placeholder showing the expected structure for
    # mock function outputs. It's used in forms to help users understand the format.
    #
    # @return [String] JSON placeholder example
    def mock_function_outputs_placeholder
      return "{}" unless respond_to?(:model_config)

      config = model_config&.with_indifferent_access
      return "{}" unless config

      functions = config.dig(:tool_config, :functions) || config.dig("tool_config", "functions")
      return "{}" unless functions.present?

      # Build example mock outputs for each function
      examples = {}
      functions.first(2).each do |func| # Show max 2 examples to keep placeholder concise
        function_name = func["name"] || func[:name]
        examples[function_name] = {
          "success" => true,
          "result" => "Example mock result for #{function_name}",
          "data" => {}
        }
      end

      JSON.pretty_generate(examples)
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
    #
    # Note: Test row partials are automatically resolved by convention from the class name.
    # The view layer derives the partial path as:
    #   "prompt_tracker/testing/tests/#{class_name.gsub('PromptTracker::', '').underscore.gsub('/', '_').pluralize}/test_row"
    #
    # Examples:
    #   PromptTracker::PromptVersion -> prompt_tracker/testing/tests/prompt_versions/test_row

    # Returns the partial path segment for this testable type
    # This is the single source of truth for deriving partial paths
    #
    # @return [String] the partial path segment (e.g., "prompt_versions")
    #
    # @example PromptVersion
    #   testable.partial_path_segment # => "prompt_versions"
    #
    def partial_path_segment
      # Remove PromptTracker:: prefix, convert to underscore, replace / with _, pluralize
      # PromptTracker::PromptVersion -> "prompt_versions"
      self.class.name.gsub("PromptTracker::", "").underscore.gsub("/", "_").pluralize
    end

    # Returns the full partial path for test run rows
    #
    # Uses the unified row partial that works for all testable types.
    # The unified partial reads from output_data which has a consistent structure.
    #
    # @return [String] the full partial path
    def test_run_row_partial
      "prompt_tracker/testing/test_runs/row"
    end


    def test_form_partial
      "prompt_tracker/testing/tests/#{partial_path_segment}/form"
    end

    # Returns the full partial path for test rows
    #
    # @return [String] the full partial path
    #
    # @example PromptVersion
    #   testable.test_row_partial # => "prompt_tracker/testing/tests/prompt_versions/test_row"
    #
    # @example Assistant
    #   testable.test_row_partial # => "prompt_tracker/testing/tests/openai_assistants/test_row"
    #
    def test_row_partial
      "prompt_tracker/testing/tests/#{partial_path_segment}/test_row"
    end

    # Returns the Turbo Stream name for this testable instance
    # This is used for broadcasting updates to the testable's show page
    #
    # @return [String] the stream name
    #
    # @example PromptVersion
    #   version.testable_stream_name # => "prompt_version_123"
    #
    # @example Assistant
    #   assistant.testable_stream_name # => "openai_assistant_456"
    #
    def testable_stream_name
      "#{partial_path_segment.singularize}_#{id}"
    end

    # Returns the locals hash needed for rendering the test row partial
    # This is used when broadcasting test row updates
    #
    # @param test [Test] the test to render
    # @return [Hash] the locals hash
    #
    # @example PromptVersion
    #   version.test_row_locals(test) # => { test: test, version: version, prompt: prompt }
    #
    # @example Assistant
    #   assistant.test_row_locals(test) # => { test: test, assistant: assistant }
    #
    def test_row_locals(test)
      raise NotImplementedError, "#{self.class.name} must implement #test_row_locals"
    end

    # Returns the API type for this testable.
    #
    # This determines which evaluators are compatible with this testable
    # and how the response data should be normalized before evaluation.
    #
    # Including classes must implement this method.
    #
    # @return [Symbol] the API type constant from PromptTracker::ApiTypes
    #
    # @example PromptVersion (determined by model_config provider and api)
    #   version.api_type # => :openai_chat_completions or :openai_responses
    #
    # @example Assistant
    #   assistant.api_type # => :openai_assistants
    #
    def api_type
      raise NotImplementedError, "#{self.class.name} must implement #api_type"
    end

    # Returns the column headers for the test runs table
    #
    # Defines which columns to display in the test runs accordion for this testable type.
    # Uses unified output_data structure for all test types.
    #
    # This is a default implementation that works for all testable types since they
    # all use the same unified output_data structure. Testable models can override
    # this method if they need custom columns.
    #
    # @return [Array<Hash>] array of column definitions
    #
    # @example Default columns
    #   testable.test_run_table_headers
    #   # => [
    #   #   { key: "run_status", label: "Status", width: "10%" },
    #   #   { key: "run_time", label: "Run Time", width: "12%" },
    #   #   ...
    #   # ]
    #
    def test_run_table_headers
      [
        { key: "run_status", label: "Status", width: "10%" },
        { key: "run_time", label: "Run Time", width: "12%" },
        { key: "response_time", label: "Response Time", width: "10%" },
        { key: "run_cost", label: "Cost", width: "8%" },
        { key: "rendered_prompt", label: "Rendered Prompt", width: "15%" },
        { key: "output_messages", label: "Output", width: "25%" },
        { key: "run_evaluations", label: "Evaluations", width: "10%" },
        { key: "human_evaluations", label: "Human Evaluations", width: "10%" },
        { key: "actions", label: "Actions", width: "5%" }
      ]
    end
  end
end
