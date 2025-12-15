# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompt_tests
#
#  created_at         :datetime         not null
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  id                 :bigint           not null, primary key
#  metadata           :jsonb            not null
#  model_config       :jsonb            not null
#  name               :string           not null
#  prompt_version_id  :bigint           not null
#  tags               :jsonb            not null
#  updated_at         :datetime         not null
#
module PromptTracker
  # Represents a single test case for a prompt.
  #
  # A PromptTest defines:
  # - Evaluators to run (both binary and scored modes)
  # - Model configuration for LLM calls
  # - Test runs are executed against datasets (DatasetRow provides variables)
  #
  # @example Create a test with evaluators
  #   test = PromptTest.create!(
  #     prompt_version: version,
  #     name: "greeting_premium_user",
  #     description: "Test greeting for premium customers",
  #     model_config: { provider: "openai", model: "gpt-4" }
  #   )
  #
  #   # Add evaluator
  #   test.evaluator_configs.create!(
  #     evaluator_type: "PromptTracker::Evaluators::PatternMatchEvaluator",
  #     config: { patterns: ["/Hello/", "/Alice/"], match_all: true }
  #   )
  #
  #   # Add another evaluator
  #   test.evaluator_configs.create!(
  #     evaluator_type: "PromptTracker::Evaluators::LengthEvaluator",
  #     config: { min_length: 50 }
  #   )
  #
  class PromptTest < ApplicationRecord
    # Associations
    belongs_to :prompt_version
    has_many :prompt_test_runs, dependent: :destroy
    has_many :evaluator_configs,
             as: :configurable,
             class_name: "PromptTracker::EvaluatorConfig",
             dependent: :destroy

    # Delegate to get the prompt through prompt_version
    has_one :prompt, through: :prompt_version

    # Accept nested attributes for evaluator configs
    accepts_nested_attributes_for :evaluator_configs, allow_destroy: true

    # Validations
    validates :name, presence: true
    validates :name, uniqueness: { scope: :prompt_version_id }
    validates :model_config, presence: true

    # Store configs JSON temporarily for after_save callback
    attr_accessor :evaluator_configs_json

    # Custom setter to handle evaluator_configs as JSON array (for backward compatibility with forms)
    # This allows the form to submit evaluator_configs as a JSON string or array
    # and automatically creates/updates the associated EvaluatorConfig records
    #
    # @param configs [String, Array, ActiveRecord::Relation] JSON string, array of hashes, or AR relation
    # @return [void]
    def evaluator_configs=(configs)
      # If it's already an ActiveRecord relation, use the default behavior
      return super(configs) if configs.is_a?(ActiveRecord::Relation) || configs.is_a?(ActiveRecord::Associations::CollectionProxy)

      # Store for after_save callback
      @evaluator_configs_json = configs
    end

    after_save :sync_evaluator_configs_from_json

    private

    def sync_evaluator_configs_from_json
      return unless @evaluator_configs_json

      # Parse JSON if it's a string
      configs = @evaluator_configs_json.is_a?(String) ? JSON.parse(@evaluator_configs_json) : @evaluator_configs_json
      return unless configs.is_a?(Array)

      # Clear existing configs using association method
      association(:evaluator_configs).reader.destroy_all

      # Create new configs from the array
      configs.each do |config_hash|
        config_hash = config_hash.with_indifferent_access if config_hash.is_a?(Hash)

        # Convert evaluator_key (symbol like :keyword) to evaluator_type (full class name)
        evaluator_key = config_hash[:evaluator_key]
        evaluator_type = if evaluator_key
          # Look up the evaluator class from the registry using the key
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

    public

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :recent, -> { order(created_at: :desc) }

    # Get recent test runs
    #
    # @param limit [Integer] number of runs to return
    # @return [ActiveRecord::Relation<PromptTestRun>]
    def recent_runs(limit = 10)
      prompt_test_runs.order(created_at: :desc).limit(limit)
    end

    # Calculate pass rate
    #
    # @param limit [Integer] number of recent runs to consider
    # @return [Float] pass rate as percentage (0-100)
    def pass_rate(limit: 30)
      runs = recent_runs(limit).where.not(passed: nil)
      return 0.0 if runs.empty?

      passed_count = runs.where(passed: true).count
      (passed_count.to_f / runs.count * 100).round(2)
    end

    # Get last test run
    #
    # @return [PromptTestRun, nil]
    def last_run
      prompt_test_runs.order(created_at: :desc).first
    end

    # Check if test is passing
    #
    # @return [Boolean]
    def passing?
      last_run&.passed? || false
    end

    # Get average execution time
    #
    # @param limit [Integer] number of recent runs to consider
    # @return [Integer, nil] average time in milliseconds
    def avg_execution_time(limit: 30)
      runs = recent_runs(limit).where.not(execution_time_ms: nil)
      return nil if runs.empty?

      runs.average(:execution_time_ms).to_i
    end

    # Get average score from the last test run
    #
    # @return [Float, nil] average score (0.0-1.0) or nil if no last run or no evaluations
    def last_run_avg_score
      return nil unless last_run

      last_run.avg_score
    end
  end
end
