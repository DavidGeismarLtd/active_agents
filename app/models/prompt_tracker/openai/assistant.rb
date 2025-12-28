# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_openai_assistants
#
#  id            :bigint           not null, primary key
#  assistant_id  :string           not null
#  name          :string           not null
#  description   :text
#  category      :string
#  metadata      :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
module PromptTracker
  module Openai
    # Represents an OpenAI Assistant that can be tested through conversations.
    #
    # An Assistant:
    # - Is synced from OpenAI API (instructions, model, tools stored in metadata)
    # - Can have multiple tests with different evaluators
    # - Can have multiple datasets for testing different scenarios
    # - Runs conversations with LLM-simulated users
    #
    # @example Create an assistant
    #   assistant = PromptTracker::Openai::Assistant.create!(
    #     assistant_id: "asst_abc123",
    #     name: "Medical Support Assistant",
    #     description: "Provides medical advice and support"
    #   )
    #
    # @example Fetch details from OpenAI
    #   assistant.fetch_from_openai!
    #   # Updates metadata with instructions, model, tools, etc.
    #
    class Assistant < ApplicationRecord
      # Include Testable concern for polymorphic interface
      include Testable

      self.table_name = "prompt_tracker_openai_assistants"

      # Note: tests, datasets, and test_runs associations are provided by Testable concern

      # Additional associations specific to Assistant
      has_many :dataset_rows,
               through: :datasets,
               class_name: "PromptTracker::DatasetRow"

      # Validations
      validates :assistant_id, presence: true, uniqueness: true
      validates :name, presence: true

      # Allow skipping the fetch_from_openai callback (useful for seeding)
      attr_accessor :skip_fetch_from_openai

      # Callbacks
      after_initialize :set_default_metadata, if: :new_record?
      after_create :fetch_from_openai, unless: :skip_fetch_from_openai

      # Scopes
      scope :recent, -> { order(created_at: :desc) }

      # Accessor methods for metadata fields
      def instructions
        metadata["instructions"]
      end

      def model
        metadata["model"]
      end

      def tools
        metadata["tools"] || []
      end

      def file_ids
        metadata["file_ids"] || []
      end

      def last_synced_at
        metadata["last_synced_at"]
      end

      # Fetch assistant details from OpenAI API
      #
      # @return [Boolean] true if successful
      # @raise [StandardError] if API call fails
      def fetch_from_openai!
        client = ::OpenAI::Client.new(access_token: ENV["OPENAI_LOUNA_API_KEY"])
        response = client.assistants.retrieve(id: assistant_id)
        update!(
          name: response["name"] || name,
          description: response["description"] || description,
          metadata: metadata.merge(
            instructions: response["instructions"],
            model: response["model"],
            tools: response["tools"] || [],
            file_ids: response["file_ids"] || [],
            temperature: response["temperature"],
            top_p: response["top_p"],
            response_format: response["response_format"],
            tool_resources: response["tool_resources"] || {},
            last_synced_at: Time.current.iso8601
          )
        )
      end

      # Run a test with a dataset row
      #
      # @param test [Test] the test to run
      # @param dataset_row [DatasetRow] the dataset row with test scenario
      # @return [TestRun] the created test run
      def run_test(test:, dataset_row:)
        # This will be implemented by AssistantTestRunner service
        # For now, just create a pending test run
        test.test_runs.create!(
          dataset_id: dataset_row.dataset_id,
          dataset_row_id: dataset_row.id,
          status: "pending"
        )
      end

      # Get recent test runs
      #
      # @param limit [Integer] number of runs to return
      # @return [ActiveRecord::Relation<TestRun>]
      def recent_runs(limit = 10)
        test_runs.order(created_at: :desc).limit(limit)
      end

      # Calculate pass rate across all tests
      #
      # @param limit [Integer] number of recent runs to consider
      # @return [Float] pass rate as percentage (0-100)
      def pass_rate(limit: 30)
        runs = recent_runs(limit).where.not(passed: nil)
        return 0.0 if runs.empty?

        passed_count = runs.where(passed: true).count
        (passed_count.to_f / runs.count * 100).round(2)
      end

      # Get last test run across all tests
      #
      # @return [TestRun, nil]
      def last_run
        test_runs.order(created_at: :desc).first
      end

      # Display name for UI
      #
      # @return [String]
      def display_name
        name
      end

      # Returns the variables schema for assistant datasets
      #
      # Assistants have a fixed schema for conversation testing scenarios.
      # This schema is used when creating datasets for this assistant.
      #
      # @return [Array<Hash>] array of variable definitions
      def variables_schema
        [
          {
            "name" => "interlocutor_simulation_prompt",
            "type" => "text",
            "required" => true,
            "description" => "A detailed prompt that simulates the user/patient/customer in the conversation. Should describe their situation, emotional state, concerns, and how they should behave. Example: 'You are a patient experiencing a severe headache with sensitivity to light. You're worried it might be a migraine. Be concerned but cooperative.'"
          },
          {
            "name" => "max_turns",
            "type" => "integer",
            "required" => false,
            "description" => "Maximum number of conversation turns (back-and-forth exchanges) to simulate. Typically 2-5 turns. Leave blank to use default."
          }
        ]
      end

      # Returns the column headers for the tests table
      #
      # Defines which columns to display in the tests table for this testable type.
      # Assistants don't have a "Template" column like PromptVersions do.
      #
      # @return [Array<Hash>] array of column definitions
      def test_table_headers
        [
          { key: "name", label: "Test Name", width: "30%" },
          { key: "evaluator_configs", label: "Evaluator Configs", width: "25%" },
          { key: "status", label: "Last Status", width: "10%" },
          { key: "last_run", label: "Last Run", width: "12%" },
          { key: "total_runs", label: "Total Runs", width: "10%", align: "end" },
          { key: "actions", label: "Actions", width: "13%" }
        ]
      end

      # Returns the column headers for the test runs table
      #
      # Defines which columns to display in the test runs accordion for this testable type.
      # Assistants show conversation data instead of rendered prompts.
      #
      # @return [Array<Hash>] array of column definitions
      def test_run_table_headers
        [
          { key: "run_status", label: "Status", width: "10%" },
          { key: "run_time", label: "Run Time", width: "12%" },
          { key: "response_time", label: "Response Time", width: "10%" },
          { key: "run_cost", label: "Cost", width: "8%" },
          { key: "conversation", label: "Conversation", width: "30%" },
          { key: "run_evaluations", label: "Evaluations", width: "10%" },
          { key: "human_evaluations", label: "Human Evaluations", width: "10%" },
          { key: "actions", label: "Actions", width: "5%" }
        ]
      end

      # Returns the locals hash needed for rendering the test row partial
      #
      # @param test [Test] the test to render
      # @return [Hash] the locals hash with test and assistant
      def test_row_locals(test)
        { test: test, assistant: self }
      end

      private

      # Set default metadata for new records
      def set_default_metadata
        self.metadata ||= {}
      end

      # Callback to fetch from OpenAI after creation
      def fetch_from_openai
        fetch_from_openai!
      end
    end
  end
end
