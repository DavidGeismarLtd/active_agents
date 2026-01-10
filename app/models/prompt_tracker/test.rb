# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_tests
#
#  id                 :bigint           not null, primary key
#  name               :string           not null
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  tags               :jsonb            not null
#  metadata           :jsonb            not null
#  test_mode          :integer          default(0), not null  # 0=single_turn, 1=conversational
#  testable_type      :string
#  testable_id        :bigint
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
module PromptTracker
  # Represents a test case for any testable (PromptVersion or Assistant).
  #
  # A Test defines:
  # - Evaluators to run (both binary and scored modes)
  # - Test runs are executed against datasets (DatasetRow provides variables)
  # - For PromptVersions: uses the prompt_version's model_config for LLM calls
  # - For Assistants: runs multi-turn conversations with LLM-simulated users
  #
  # @example Create a test for a PromptVersion
  #   test = Test.create!(
  #     testable: prompt_version,
  #     name: "greeting_premium_user",
  #     description: "Test greeting for premium customers"
  #   )
  #
  # @example Create a test for an Assistant
  #   test = Test.create!(
  #     testable: assistant,
  #     name: "Headache Consultation",
  #     description: "Test how assistant handles headache complaints"
  #   )
  #
  #   # Add ConversationJudgeEvaluator
  #   test.evaluator_configs.create!(
  #     evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  #     config: {
  #       evaluation_prompt: "Evaluate each assistant message for empathy and accuracy..."
  #     }
  #   )
  #
  class Test < ApplicationRecord
    self.table_name = "prompt_tracker_tests"

    # Test mode enum: determines how the test is executed
    enum :test_mode, { single_turn: 0, conversational: 1 }, default: :single_turn

    # Polymorphic association - can belong to PromptVersion or Assistant
    belongs_to :testable, polymorphic: true

    # Associations
    has_many :test_runs,
             class_name: "PromptTracker::TestRun",
             foreign_key: :test_id,
             dependent: :destroy

    has_many :evaluator_configs,
             as: :configurable,
             class_name: "PromptTracker::EvaluatorConfig",
             dependent: :destroy

    # Accept nested attributes for evaluator configs
    accepts_nested_attributes_for :evaluator_configs, allow_destroy: true

    # Validations
    validates :name, presence: true
    validates :testable, presence: true
    validate :testable_supports_test_mode
    validate :dataset_compatible_with_test_mode, if: -> { respond_to?(:dataset) && dataset.present? }

    # Store configs JSON temporarily for after_save callback
    attr_accessor :evaluator_configs_json

    # Callbacks
    # Auto-set test_mode for assistants (which only support conversational mode)
    before_validation :set_default_test_mode, on: :create

    # Custom setter to handle evaluator_configs as JSON array (for backward compatibility with forms)
    def evaluator_configs=(configs)
      return super(configs) if configs.is_a?(ActiveRecord::Relation) || configs.is_a?(ActiveRecord::Associations::CollectionProxy)
      @evaluator_configs_json = configs
    end

    after_save :sync_evaluator_configs_from_json

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_prompt_versions, -> { where(testable_type: "PromptTracker::PromptVersion") }
    scope :for_assistants, -> { where(testable_type: "PromptTracker::Openai::Assistant") }
    scope :single_turn_tests, -> { where(test_mode: :single_turn) }
    scope :conversational_tests, -> { where(test_mode: :conversational) }

    # Get recent test runs
    def recent_runs(limit = 10)
      test_runs.order(created_at: :desc).limit(limit)
    end

    # Calculate pass rate
    def pass_rate(limit: 30)
      runs = recent_runs(limit).where.not(passed: nil)
      return 0.0 if runs.empty?

      passed_count = runs.where(passed: true).count
      (passed_count.to_f / runs.count * 100).round(2)
    end

    # Get last test run
    def last_run
      test_runs.order(created_at: :desc).first
    end

    # Check if test is passing
    def passing?
      last_run&.passed? || false
    end

    # Get average execution time
    def avg_execution_time(limit: 30)
      runs = recent_runs(limit).where.not(execution_time_ms: nil)
      return nil if runs.empty?

      runs.average(:execution_time_ms).to_i
    end

    # Get average score from the last test run
    def last_run_avg_score
      return nil unless last_run
      last_run.avg_score
    end

    # Run the test with a dataset row
    def run!(dataset_row:)
      testable.run_test(test: self, dataset_row: dataset_row)
    end

    # Returns the partial path for test run rows based on test mode
    #
    # For conversational tests, uses a generic conversational row partial.
    # For single-turn tests, delegates to the testable's default partial.
    #
    # @return [String] the partial path
    #
    # @example Single-turn test
    #   test.test_run_row_partial # => "prompt_tracker/testing/test_runs/prompt_versions/row"
    #
    # @example Conversational test
    #   test.test_run_row_partial # => "prompt_tracker/testing/test_runs/conversational_row"
    #
    def test_run_row_partial
      if conversational?
        "prompt_tracker/testing/test_runs/conversational_row"
      else
        testable.test_run_row_partial
      end
    end

    # Returns the column headers for test runs based on test mode
    #
    # Conversational tests show conversation data instead of rendered prompts.
    #
    # @return [Array<Hash>] array of column definitions
    def test_run_table_headers
      if conversational?
        conversational_test_run_headers
      else
        testable.test_run_table_headers
      end
    end

    # Check if testable supports the current test mode
    #
    # @return [Boolean] true if testable supports this test mode
    def testable_supports_test_mode?
      return true unless testable.present?

      case testable
      when PromptVersion
        # Single-turn always supported
        return true if single_turn?
        # Conversational requires Response API provider
        testable.model_config&.dig("provider") == "openai_responses"
      when Openai::Assistant
        # Assistants only support conversational mode
        conversational?
      else
        true
      end
    end

    private

    # Auto-set test_mode based on testable type
    # Assistants only support conversational mode
    def set_default_test_mode
      return unless testable.present?

      if testable.is_a?(Openai::Assistant)
        self.test_mode = :conversational
      end
    end

    # Validates that testable supports the selected test mode
    def testable_supports_test_mode
      return if testable_supports_test_mode?

      case testable
      when PromptVersion
        errors.add(:test_mode, "conversational mode requires Response API provider (openai_responses)")
      when Openai::Assistant
        errors.add(:test_mode, "Assistants only support conversational mode")
      end
    end

    # Validates that dataset type is compatible with test mode
    def dataset_compatible_with_test_mode
      return unless dataset.respond_to?(:conversational?)

      if conversational? && !dataset.conversational?
        errors.add(:dataset, "must be a conversational dataset for conversational tests")
      end

      if single_turn? && dataset.conversational?
        errors.add(:dataset, "cannot use a conversational dataset for single-turn tests")
      end
    end

    # Returns table headers for conversational test runs
    #
    # @return [Array<Hash>] array of column definitions
    def conversational_test_run_headers
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

    def sync_evaluator_configs_from_json
      return unless @evaluator_configs_json

      configs = @evaluator_configs_json.is_a?(String) ? JSON.parse(@evaluator_configs_json) : @evaluator_configs_json
      return unless configs.is_a?(Array)

      association(:evaluator_configs).reader.destroy_all

      configs.each do |config_hash|
        config_hash = config_hash.with_indifferent_access if config_hash.is_a?(Hash)

        evaluator_key = config_hash[:evaluator_key]
        evaluator_type = if evaluator_key
          registry_entry = EvaluatorRegistry.all[evaluator_key.to_sym]
          registry_entry ? registry_entry[:evaluator_class].name : nil
        else
          config_hash[:evaluator_type]
        end

        next unless evaluator_type

        association(:evaluator_configs).reader.create!(
          evaluator_type: evaluator_type,
          config: config_hash[:config] || {},
          enabled: true
        )
      end

      @evaluator_configs_json = nil
    end
  end
end
