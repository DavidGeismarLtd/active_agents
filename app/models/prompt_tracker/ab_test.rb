# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_ab_tests
#
#  cancelled_at              :datetime
#  completed_at              :datetime
#  confidence_level          :float            default(0.95)
#  created_at                :datetime         not null
#  created_by                :string
#  description               :text
#  hypothesis                :string
#  id                        :bigint           not null, primary key
#  metadata                  :jsonb
#  metric_to_optimize        :string           not null
#  minimum_detectable_effect :float            default(0.05)
#  minimum_sample_size       :integer          default(100)
#  name                      :string           not null
#  optimization_direction    :string           default("minimize"), not null
#  prompt_id                 :bigint           not null
#  results                   :jsonb
#  started_at                :datetime
#  status                    :string           default("draft"), not null
#  traffic_split             :jsonb            not null
#  updated_at                :datetime         not null
#  variants                  :jsonb            not null
#
module PromptTracker
  # Represents an A/B test for comparing prompt versions.
  #
  # An AbTest allows you to run multiple prompt versions simultaneously,
  # split traffic between them, and analyze which performs better based
  # on statistical significance.
  #
  # @example Creating an A/B test
  #   ab_test = AbTest.create!(
  #     prompt: prompt,
  #     name: "Shorter greeting test",
  #     hypothesis: "Version 2 will reduce response time by 20%",
  #     metric_to_optimize: "response_time",
  #     optimization_direction: "minimize",
  #     traffic_split: { "A" => 50, "B" => 50 },
  #     variants: [
  #       { name: "A", version_id: 1, description: "Current version" },
  #       { name: "B", version_id: 2, description: "Shorter version" }
  #     ],
  #     confidence_level: 0.95,
  #     minimum_sample_size: 200
  #   )
  #
  # @example Starting a test
  #   ab_test.start!
  #
  # @example Selecting a variant
  #   variant_name = ab_test.select_variant  # => "A" or "B" based on traffic split
  #   version = ab_test.version_for_variant(variant_name)
  #
  class AbTest < ApplicationRecord
    # Constants
    STATUSES = %w[draft running paused completed cancelled].freeze
    METRICS = %w[cost response_time quality_score success_rate custom].freeze
    OPTIMIZATION_DIRECTIONS = %w[minimize maximize].freeze

    # Associations
    belongs_to :prompt,
               class_name: "PromptTracker::Prompt",
               inverse_of: :ab_tests

    has_many :llm_responses,
             class_name: "PromptTracker::LlmResponse",
             dependent: :nullify,
             inverse_of: :ab_test

    # Validations
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :metric_to_optimize, presence: true, inclusion: { in: METRICS }
    validates :optimization_direction, presence: true, inclusion: { in: OPTIMIZATION_DIRECTIONS }
    validates :traffic_split, presence: true
    validates :variants, presence: true
    validates :confidence_level,
              numericality: { greater_than: 0, less_than: 1 },
              allow_nil: true
    validates :minimum_detectable_effect,
              numericality: { greater_than: 0, less_than: 1 },
              allow_nil: true
    validates :minimum_sample_size,
              numericality: { only_integer: true, greater_than: 0 },
              allow_nil: true

    validate :traffic_split_must_sum_to_100
    validate :variants_must_have_valid_structure
    validate :variants_must_reference_valid_versions
    validate :only_one_running_test_per_prompt, on: :create

    # Scopes

    # Returns only draft tests
    # @return [ActiveRecord::Relation<AbTest>]
    scope :draft, -> { where(status: "draft") }

    # Returns only running tests
    # @return [ActiveRecord::Relation<AbTest>]
    scope :running, -> { where(status: "running") }

    # Returns only paused tests
    # @return [ActiveRecord::Relation<AbTest>]
    scope :paused, -> { where(status: "paused") }

    # Returns only completed tests
    # @return [ActiveRecord::Relation<AbTest>]
    scope :completed, -> { where(status: "completed") }

    # Returns only cancelled tests
    # @return [ActiveRecord::Relation<AbTest>]
    scope :cancelled, -> { where(status: "cancelled") }

    # Returns tests for a specific prompt
    # @param prompt_id [Integer] the prompt ID
    # @return [ActiveRecord::Relation<AbTest>]
    scope :for_prompt, ->(prompt_id) { where(prompt_id: prompt_id) }

    # Returns tests optimizing a specific metric
    # @param metric [String] the metric name
    # @return [ActiveRecord::Relation<AbTest>]
    scope :optimizing, ->(metric) { where(metric_to_optimize: metric) }

    # Instance Methods

    # Starts the A/B test.
    #
    # @return [Boolean] true if successful
    # @raise [ActiveRecord::RecordInvalid] if validation fails
    def start!
      update!(status: "running", started_at: Time.current)
    end

    # Pauses the A/B test.
    #
    # @return [Boolean] true if successful
    def pause!
      update!(status: "paused")
    end

    # Resumes a paused A/B test.
    #
    # @return [Boolean] true if successful
    def resume!
      update!(status: "running")
    end

    # Completes the A/B test with a winner.
    #
    # @param winner [String] the variant name that won
    # @return [Boolean] true if successful
    def complete!(winner:)
      update!(
        status: "completed",
        completed_at: Time.current,
        results: results.merge("winner" => winner)
      )
    end

    # Cancels the A/B test.
    #
    # @return [Boolean] true if successful
    def cancel!
      update!(status: "cancelled", cancelled_at: Time.current)
    end

    # Selects a variant based on traffic split.
    #
    # Uses weighted random selection.
    #
    # @return [String] the selected variant name
    #
    # @example
    #   ab_test.select_variant  # => "A" or "B"
    def select_variant
      random_value = rand(100)
      cumulative = 0

      traffic_split.each do |variant_name, percentage|
        cumulative += percentage
        return variant_name if random_value < cumulative
      end

      # Fallback to first variant
      traffic_split.keys.first
    end

    # Returns the PromptVersion for a given variant.
    #
    # @param variant_name [String] the variant name (e.g., "A", "B")
    # @return [PromptVersion, nil] the version or nil if not found
    def version_for_variant(variant_name)
      variant = variants.find { |v| v["name"] == variant_name }
      return nil unless variant

      prompt.prompt_versions.find_by(id: variant["version_id"])
    end

    # Returns all variant names.
    #
    # @return [Array<String>] array of variant names
    def variant_names
      variants.map { |v| v["name"] }
    end

    # Checks if the test is running.
    #
    # @return [Boolean] true if status is "running"
    def running?
      status == "running"
    end

    # Checks if the test is completed.
    #
    # @return [Boolean] true if status is "completed"
    def completed?
      status == "completed"
    end

    # Checks if the test is paused.
    #
    # @return [Boolean] true if status is "paused"
    def paused?
      status == "paused"
    end

    # Checks if the test is cancelled.
    #
    # @return [Boolean] true if status is "cancelled"
    def cancelled?
      status == "cancelled"
    end

    # Checks if the test is a draft.
    #
    # @return [Boolean] true if status is "draft"
    def draft?
      status == "draft"
    end

    # Returns the duration of the test in days.
    #
    # @return [Float, nil] duration in days or nil if not started
    def duration_days
      return nil unless started_at

      end_time = completed_at || cancelled_at || Time.current
      ((end_time - started_at) / 1.day).round(1)
    end

    # Returns the total number of responses across all variants.
    #
    # @return [Integer] total count
    def total_responses
      llm_responses.count
    end

    # Returns the number of responses for a specific variant.
    #
    # @param variant_name [String] the variant name
    # @return [Integer] count for that variant
    def responses_for_variant(variant_name)
      llm_responses.where(ab_variant: variant_name).count
    end

    # Promotes the winning variant to active.
    #
    # Only works if test is completed and has a winner.
    #
    # @return [Boolean] true if successful
    # @raise [StandardError] if test is not completed or has no winner
    def promote_winner!
      raise "Test must be completed" unless completed?
      raise "No winner declared" unless results["winner"].present?

      winner_variant = results["winner"]
      winning_version = version_for_variant(winner_variant)

      raise "Winning version not found" unless winning_version

      winning_version.activate!
    end

    private

    # Validates that traffic split percentages sum to 100
    def traffic_split_must_sum_to_100
      return if traffic_split.blank?
      return unless traffic_split.is_a?(Hash)

      total = traffic_split.values.sum
      return if total == 100

      errors.add(:traffic_split, "percentages must sum to 100 (currently #{total})")
    end

    # Validates that variants have the correct structure
    def variants_must_have_valid_structure
      return if variants.blank?
      return unless variants.is_a?(Array)

      variants.each_with_index do |variant, index|
        unless variant.is_a?(Hash)
          errors.add(:variants, "variant at index #{index} must be a hash")
          next
        end

        unless variant["name"].present?
          errors.add(:variants, "variant at index #{index} must have a 'name'")
        end

        unless variant["version_id"].present?
          errors.add(:variants, "variant at index #{index} must have a 'version_id'")
        end
      end

      # Check for duplicate variant names
      variant_names = variants.map { |v| v["name"] }.compact
      duplicates = variant_names.select { |name| variant_names.count(name) > 1 }.uniq
      if duplicates.any?
        errors.add(:variants, "contains duplicate names: #{duplicates.join(', ')}")
      end
    end

    # Validates that variants reference valid prompt versions
    def variants_must_reference_valid_versions
      return if variants.blank? || prompt.nil?
      return unless variants.is_a?(Array)

      variants.each do |variant|
        next unless variant.is_a?(Hash) && variant["version_id"].present?

        version = prompt.prompt_versions.find_by(id: variant["version_id"])
        unless version
          errors.add(:variants, "variant '#{variant['name']}' references non-existent version #{variant['version_id']}")
        end
      end
    end

    # Validates that only one test is running per prompt
    def only_one_running_test_per_prompt
      return unless status == "running"
      return if prompt.nil?

      existing_running = prompt.ab_tests.running.where.not(id: id).exists?
      if existing_running
        errors.add(:base, "Only one running test allowed per prompt")
      end
    end
  end
end
