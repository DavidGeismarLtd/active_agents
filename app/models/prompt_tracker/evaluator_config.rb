# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_evaluator_configs
#
#  config            :jsonb            not null
#  configurable_id   :bigint           not null
#  configurable_type :string           not null
#  created_at        :datetime         not null
#  enabled           :boolean          default(TRUE), not null
#  evaluator_type    :string           not null
#  id                :bigint           not null, primary key
#  updated_at        :datetime         not null
#
module PromptTracker
  # Represents configuration for an evaluator that should run automatically for a prompt.
  #
  # EvaluatorConfigs define which evaluators run when a response is created,
  # along with their parameters and evaluation mode.
  #
  # @example Creating a basic evaluator config
  #   prompt.evaluator_configs.create!(
  #     evaluator_type: 'PromptTracker::Evaluators::LengthEvaluator',
  #     enabled: true,
  #     config: { min_length: 50, max_length: 500 }
  #   )
  #
  # @example Creating an exact match evaluator config
  #   prompt.evaluator_configs.create!(
  #     evaluator_type: 'PromptTracker::Evaluators::ExactMatchEvaluator',
  #     enabled: true,
  #     config: { expected_output: "Hello, world!" }
  #   )
  #
  # @example Finding enabled configs for a prompt
  #   configs = prompt.evaluator_configs.enabled
  #   configs.each { |config| puts "#{config.evaluator_type}: #{config.name}" }
  #
  class EvaluatorConfig < ApplicationRecord
    # Associations
    belongs_to :configurable, polymorphic: true

    # Validations
    validates :evaluator_type,
              presence: true,
              uniqueness: { scope: [ :configurable_type, :configurable_id ] }
    validate :evaluator_compatible_with_testable

    # Scopes

    # Returns only enabled evaluator configs
    # @return [ActiveRecord::Relation<EvaluatorConfig>]
    scope :enabled, -> { where(enabled: true) }

    # Instance Methods

    # Returns the evaluator class
    # @return [Class] the evaluator class
    def evaluator_class
      evaluator_type.constantize
    end

    # Returns the registry key for this evaluator
    # Derives key from class name (e.g., "PromptTracker::Evaluators::KeywordEvaluator" -> :keyword)
    # @return [Symbol, nil] the registry key, or nil if evaluator_type is not set
    def evaluator_key
      return nil if evaluator_type.blank?

      evaluator_type.demodulize.underscore.gsub("_evaluator", "").to_sym
    end

    # Sets the evaluator_type from a registry key
    #
    # This setter is essential for form submissions and API usage. It allows:
    # 1. Forms to submit user-friendly keys (e.g., "llm_judge") instead of internal class names
    # 2. Factories and tests to use readable keys: `create(:evaluator_config, evaluator_key: :keyword)`
    # 3. Consistent API where keys are the public interface, class names are internal
    #
    # When a form submits `evaluator_config[evaluator_key] = "llm_judge"`, Rails calls this setter,
    # which converts the key to the full class name that gets stored in the database.
    #
    # @param key [String, Symbol] the registry key (e.g., "keyword", :keyword)
    # @example
    #   config.evaluator_key = :llm_judge
    #   config.evaluator_type # => "PromptTracker::Evaluators::LlmJudgeEvaluator"
    def evaluator_key=(key)
      return if key.blank?

      metadata = EvaluatorRegistry.get(key)
      if metadata
        self.evaluator_type = metadata[:evaluator_class].name
      else
        # Set to invalid value to trigger validation error
        self.evaluator_type = "Invalid::#{key}"
      end
    end

    # Returns metadata about this evaluator from the registry
    # @return [Hash, nil] evaluator metadata or nil if not found
    def evaluator_metadata
      EvaluatorRegistry.get(evaluator_key)
    end

    # Builds an instance of the evaluator for a specific response
    # @param llm_response [LlmResponse] the response to evaluate
    # @return [BaseEvaluator] an instance of the evaluator
    def build_evaluator(llm_response)
      # Add evaluator_config_id and llm_response to config so evaluations can reference them
      merged_config = config.merge(
        evaluator_config_id: id,
        llm_response: llm_response
      )
      # Pass response_text (String) as the evaluated data
      evaluator_class.new(llm_response.response_text, merged_config)
    end

    # Returns a human-readable name for this evaluator
    # @return [String, nil] evaluator name from metadata or derived from class, or nil if not set
    def name
      return nil if evaluator_type.blank?

      evaluator_metadata&.dig(:name) || evaluator_type.demodulize.gsub("Evaluator", "").titleize
    end

    # Returns a description of this evaluator
    # @return [String, nil] evaluator description from metadata
    def description
      evaluator_metadata&.dig(:description)
    end

    # Override as_json to include computed evaluator_key and name
    # This ensures the registry key and human-readable name are available in JSON responses
    # @param options [Hash] serialization options
    # @return [Hash] JSON representation with evaluator_key and evaluator_name included
    def as_json(options = {})
      super(options).merge(
        "evaluator_key" => evaluator_key.to_s,
        "evaluator_name" => name
      )
    end

    private

    # Validates that the evaluator is compatible with the testable
    # This prevents adding evaluators to tests where they won't work
    # (e.g., adding a ConversationJudgeEvaluator to a PromptVersion test)
    def evaluator_compatible_with_testable
      return unless configurable.respond_to?(:testable)
      return if evaluator_type.blank?

      testable = configurable.testable
      klass = evaluator_type.constantize

      unless klass.compatible_with?(testable)
        compatible_types = klass.compatible_with.map(&:name).join(", ")
        errors.add(:evaluator_type,
          "#{klass.name.demodulize} is only compatible with #{compatible_types}, " \
          "but this test is for #{testable.class.name}")
      end
    rescue NameError
      errors.add(:evaluator_type, "is not a valid evaluator class")
    end
  end
end
