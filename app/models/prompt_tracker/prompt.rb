# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_prompts
#
#  archived_at :datetime
#  category    :string
#  created_at  :datetime         not null
#  created_by  :string
#  description :text
#  id          :bigint           not null, primary key
#  name        :string           not null
#  tags        :jsonb
#  updated_at  :datetime         not null
#
module PromptTracker
  # Represents a prompt template container.
  #
  # A Prompt is a named container that groups all versions of a prompt template together.
  # Think of it like a Git repository - the Prompt is the repo, and PromptVersions are commits.
  #
  # @example Creating a new prompt
  #   prompt = Prompt.create!(
  #     name: "customer_support_greeting",
  #     description: "Initial greeting for customer support chats",
  #     created_by: "john@example.com"
  #   )
  #
  # @example Finding a prompt by name
  #   prompt = Prompt.find_by!(name: "customer_support_greeting")
  #   active_version = prompt.active_version
  #
  class Prompt < ApplicationRecord
    # Associations
    has_many :prompt_versions,
             class_name: "PromptTracker::PromptVersion",
             dependent: :destroy,
             inverse_of: :prompt

    has_many :ab_tests,
             class_name: "PromptTracker::AbTest",
             dependent: :destroy,
             inverse_of: :prompt

    has_many :llm_responses,
             through: :prompt_versions,
             class_name: "PromptTracker::LlmResponse"

    has_many :evaluations,
             through: :llm_responses,
             class_name: "PromptTracker::Evaluation"

    # Validations
    validates :name,
              presence: true,
              uniqueness: { case_sensitive: false },
              format: {
                with: /\A[a-z0-9_]+\z/,
                message: "must contain only lowercase letters, numbers, and underscores"
              }

    # Scopes

    # Returns only active (non-archived) prompts
    # @return [ActiveRecord::Relation<Prompt>]
    scope :active, -> { where(archived_at: nil) }

    # Returns only archived prompts
    # @return [ActiveRecord::Relation<Prompt>]
    scope :archived, -> { where.not(archived_at: nil) }

    # Instance Methods

    # Returns the currently active version of this prompt
    # @return [PromptVersion, nil] the active version or nil if none exists
    def active_version
      prompt_versions.active.first
    end

    # Returns the most recently created version (regardless of status)
    # @return [PromptVersion, nil] the latest version or nil if none exists
    def latest_version
      prompt_versions.order(created_at: :desc).first
    end

    # Archives this prompt (soft delete)
    # Also deprecates all versions
    # @return [Boolean] true if successful
    def archive!
      transaction do
        update!(archived_at: Time.current)
        prompt_versions.each(&:deprecate!)
      end
      true
    end

    # Unarchives this prompt
    # @return [Boolean] true if successful
    def unarchive!
      update!(archived_at: nil)
    end

    # Checks if this prompt is archived
    # @return [Boolean] true if archived
    def archived?
      archived_at.present?
    end

    # Returns total number of LLM calls across all versions
    # @return [Integer] total count of LLM responses
    def total_llm_calls
      llm_responses.count
    end

    # Returns total cost across all versions
    # @return [Float] total cost in USD
    def total_cost_usd
      llm_responses.sum(:cost_usd) || 0.0
    end

    # Returns average response time across all versions
    # @return [Float, nil] average response time in milliseconds
    def average_response_time_ms
      llm_responses.average(:response_time_ms)&.to_f
    end

    # Returns evaluator configs for the active version
    # @return [ActiveRecord::Relation<EvaluatorConfig>] evaluator configs or empty relation
    def active_evaluator_configs
      active_version&.evaluator_configs || EvaluatorConfig.none
    end
  end
end
