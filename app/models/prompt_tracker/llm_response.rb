# frozen_string_literal: true

# == Schema Information
#
# Table name: prompt_tracker_llm_responses
#
#  ab_test_id           :bigint
#  ab_variant           :string
#  context              :jsonb
#  conversation_id      :string           # Groups related responses in a multi-turn conversation
#  cost_usd             :decimal(10, 6)
#  created_at           :datetime         not null
#  environment          :string
#  error_message        :text
#  error_type           :string
#  id                   :bigint           not null, primary key
#  model                :string           not null
#  previous_response_id :string           # References the response_id of the previous turn
#  prompt_version_id    :bigint           not null
#  provider             :string           not null
#  rendered_prompt      :text             not null
#  response_id          :string           # OpenAI Response API response ID (e.g., resp_abc123)
#  response_metadata    :jsonb
#  response_text        :text
#  response_time_ms     :integer
#  session_id           :string
#  status               :string           default("pending"), not null
#  tokens_completion    :integer
#  tokens_prompt        :integer
#  tokens_total         :integer
#  tool_outputs         :jsonb            default({})  # Detailed outputs from each tool
#  tools_used           :jsonb            default([])  # Array of tool names used
#  turn_number          :integer          # Position in the conversation (1, 2, 3, ...)
#  updated_at           :datetime         not null
#  user_id              :string
#  variables_used       :jsonb
#
# Note: LlmResponse is used ONLY for production call tracking via track_llm_call.
# Test runs store their output in TestRun.output_data instead.
#
module PromptTracker
  # Represents a single LLM API call and its response.
  #
  # LlmResponses track every interaction with an LLM, including:
  # - What was sent (rendered_prompt, variables_used)
  # - What came back (response_text, response_metadata)
  # - Performance (response_time_ms, tokens)
  # - Cost (cost_usd)
  # - Context (user_id, session_id, environment)
  #
  # Both successful and failed calls are tracked for complete visibility.
  #
  # @example Creating a successful response
  #   response = LlmResponse.create!(
  #     prompt_version: version,
  #     rendered_prompt: "Hello John",
  #     variables_used: { name: "John" },
  #     provider: "openai",
  #     model: "gpt-4"
  #   )
  #   response.mark_success!(
  #     response_text: "Hi there!",
  #     response_time_ms: 1200,
  #     tokens_total: 15,
  #     cost_usd: 0.00045
  #   )
  #
  # @example Creating a failed response
  #   response.mark_error!(
  #     error_type: "Timeout::Error",
  #     error_message: "Request timed out after 30s",
  #     response_time_ms: 30000
  #   )
  #
  class LlmResponse < ApplicationRecord
    # Constants
    STATUSES = %w[pending success error timeout].freeze

    # Associations
    belongs_to :prompt_version,
               class_name: "PromptTracker::PromptVersion",
               inverse_of: :llm_responses

    belongs_to :ab_test,
               class_name: "PromptTracker::AbTest",
               optional: true,
               inverse_of: :llm_responses

    has_one :prompt,
            through: :prompt_version,
            class_name: "PromptTracker::Prompt"

    has_many :evaluations,
             class_name: "PromptTracker::Evaluation",
             dependent: :destroy,
             inverse_of: :llm_response

    has_many :human_evaluations,
             class_name: "PromptTracker::HumanEvaluation",
             dependent: :destroy

    # Callbacks
    # Auto-evaluate all production tracked calls
    after_create :trigger_auto_evaluation
    before_validation :set_turn_number, if: :conversation_id_changed?

    # Validations
    validates :rendered_prompt, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :provider, presence: true
    validates :model, presence: true

    validates :response_time_ms,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true

    validates :tokens_prompt,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true

    validates :tokens_completion,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true

    validates :tokens_total,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true

    validates :cost_usd,
              numericality: { greater_than_or_equal_to: 0 },
              allow_nil: true

    validates :turn_number,
              numericality: { only_integer: true, greater_than_or_equal_to: 1 },
              allow_nil: true

    validate :variables_used_must_be_hash
    validate :response_metadata_must_be_hash
    validate :context_must_be_hash
    validate :tools_used_must_be_array
    validate :tool_outputs_must_be_hash

    # Scopes

    # Returns only successful responses
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :successful, -> { where(status: "success") }

    # Returns only failed responses (error or timeout)
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :failed, -> { where(status: %w[error timeout]) }

    # Returns only pending responses
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :pending, -> { where(status: "pending") }

    # Returns responses for a specific provider
    # @param provider [String] the provider name
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :for_provider, ->(provider) { where(provider: provider) }

    # Returns responses for a specific model
    # @param model [String] the model name
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :for_model, ->(model) { where(model: model) }

    # Returns responses for a specific user
    # @param user_id [String] the user identifier
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :for_user, ->(user_id) { where(user_id: user_id) }

    # Returns responses in a specific environment
    # @param environment [String] the environment name
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :in_environment, ->(environment) { where(environment: environment) }

    # Returns recent responses (last 24 hours by default)
    # @param hours [Integer] number of hours to look back
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :recent, ->(hours = 24) { where("created_at > ?", hours.hours.ago) }

    # Response API Scopes

    # Returns responses that used tools (web_search, file_search, code_interpreter, etc.)
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :with_tools, -> { where("tools_used IS NOT NULL AND jsonb_array_length(tools_used) > 0") }

    # Returns responses that used a specific tool
    # @param tool_name [String] the tool name (e.g., "web_search", "file_search")
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :with_tool, ->(tool_name) { where("tools_used @> ?", [ tool_name ].to_json) }

    # Returns responses for a specific conversation
    # @param conversation_id [String] the conversation identifier
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id).order(:turn_number) }

    # Returns responses that are part of multi-turn conversations
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :multi_turn, -> { where.not(conversation_id: nil) }

    # Returns only single-turn responses (not part of a conversation)
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :single_turn, -> { where(conversation_id: nil) }

    # Returns the first turn of each conversation
    # @return [ActiveRecord::Relation<LlmResponse>]
    scope :conversation_starts, -> { where(turn_number: 1) }

    # Instance Methods

    # Marks this response as successful and updates metrics.
    #
    # @param response_text [String] the LLM's response
    # @param response_time_ms [Integer] response time in milliseconds
    # @param tokens_prompt [Integer] number of prompt tokens
    # @param tokens_completion [Integer] number of completion tokens
    # @param tokens_total [Integer] total tokens
    # @param cost_usd [Float] cost in USD
    # @param response_metadata [Hash] additional metadata
    # @return [Boolean] true if successful
    def mark_success!(response_text:, response_time_ms:, tokens_total:, cost_usd:,
                      tokens_prompt: nil, tokens_completion: nil, response_metadata: {})
      update!(
        status: "success",
        response_text: response_text,
        response_time_ms: response_time_ms,
        tokens_prompt: tokens_prompt,
        tokens_completion: tokens_completion,
        tokens_total: tokens_total,
        cost_usd: cost_usd,
        response_metadata: response_metadata
      )
    end

    # Marks this response as failed with error details.
    #
    # @param error_type [String] the error class name
    # @param error_message [String] the error message
    # @param response_time_ms [Integer] time before failure
    # @return [Boolean] true if successful
    def mark_error!(error_type:, error_message:, response_time_ms: nil)
      update!(
        status: "error",
        error_type: error_type,
        error_message: error_message,
        response_time_ms: response_time_ms
      )
    end

    # Marks this response as timed out.
    #
    # @param response_time_ms [Integer] time before timeout
    # @param error_message [String] optional timeout message
    # @return [Boolean] true if successful
    def mark_timeout!(response_time_ms:, error_message: "Request timed out")
      update!(
        status: "timeout",
        error_type: "Timeout",
        error_message: error_message,
        response_time_ms: response_time_ms
      )
    end

    # Checks if this response was successful.
    #
    # @return [Boolean] true if status is "success"
    def success?
      status == "success"
    end

    # Checks if this response failed.
    #
    # @return [Boolean] true if status is "error" or "timeout"
    def failed?
      %w[error timeout].include?(status)
    end

    # Checks if this response is pending.
    #
    # @return [Boolean] true if status is "pending"
    def pending?
      status == "pending"
    end

    # Returns detailed breakdown of all evaluation scores.
    #
    # @return [Array<Hash>] array of evaluation details
    def evaluation_breakdown
      evaluations.map do |evaluation|
        # Try to get evaluator name from registry if evaluator_config_id is in metadata
        evaluator_name = if evaluation.metadata&.dig("evaluator_config_id")
          config_id = evaluation.metadata["evaluator_config_id"]
          config = EvaluatorConfig.find_by(id: config_id)
          if config
            registry_meta = EvaluatorRegistry.get(config.evaluator_key)
            registry_meta&.dig(:name) || config.evaluator_key.to_s.titleize
          else
            evaluation.evaluator_id.to_s.titleize
          end
        else
          evaluation.evaluator_id.to_s.titleize
        end

        {
          evaluation_id: evaluation.id,
          evaluator_id: evaluation.evaluator_id,
          evaluator_name: evaluator_name,
          evaluator_type: evaluation.evaluator_type,
          score: evaluation.score,
          passed: evaluation.passed,
          feedback: evaluation.feedback,
          created_at: evaluation.created_at
        }
      end
    end

    # Checks if response passes all evaluations.
    #
    # @return [Boolean] true if all evaluations passed
    def passes_all_evaluations?
      return false if evaluations.empty?

      evaluations.all?(&:passed)
    end

    # Alias for backward compatibility
    alias_method :passes_threshold?, :passes_all_evaluations?

    # Returns the evaluation with the lowest score.
    #
    # @return [Evaluation, nil] weakest evaluation or nil if none
    def weakest_evaluation
      evaluations.min_by(&:score)
    end

    # Returns the evaluation with the highest score.
    #
    # @return [Evaluation, nil] strongest evaluation or nil if none
    def strongest_evaluation
      evaluations.max_by(&:score)
    end

    # Returns the average evaluation score for this response.
    #
    # @return [Float, nil] average score or nil if no evaluations
    def average_evaluation_score
      evaluations.average(:score)&.to_f
    end

    # Returns the total number of evaluations for this response.
    #
    # @return [Integer] count of evaluations
    def evaluation_count
      evaluations.count
    end

    # Calculates cost per token.
    #
    # @return [Float, nil] cost per token in USD
    def cost_per_token
      return nil if cost_usd.nil? || tokens_total.nil? || tokens_total.zero?

      cost_usd / tokens_total
    end

    # Returns a human-readable summary of this response.
    #
    # @return [String] summary
    def summary
      if success?
        "Success: #{response_time_ms}ms, #{tokens_total} tokens, $#{cost_usd}"
      elsif failed?
        "Failed: #{error_type} - #{error_message}"
      else
        "Pending"
      end
    end

    # Response API Helper Methods

    # Checks if this response used any tools
    #
    # @return [Boolean] true if tools were used
    def used_tools?
      tools_used.present? && tools_used.any?
    end

    # Checks if this response used a specific tool
    #
    # @param tool_name [String] the tool name to check
    # @return [Boolean] true if the tool was used
    def used_tool?(tool_name)
      tools_used&.include?(tool_name)
    end

    # Checks if this response is part of a multi-turn conversation
    #
    # @return [Boolean] true if part of a conversation
    def multi_turn?
      conversation_id.present?
    end

    # Checks if this is the first turn in a conversation
    #
    # @return [Boolean] true if this is the first turn
    def first_turn?
      turn_number == 1
    end

    # Returns all responses in this conversation
    #
    # @return [ActiveRecord::Relation<LlmResponse>] ordered by turn_number
    def conversation_responses
      return self.class.none unless conversation_id.present?

      self.class.for_conversation(conversation_id)
    end

    # Returns the previous response in this conversation
    #
    # @return [LlmResponse, nil] the previous response or nil
    def previous_response
      return nil unless previous_response_id.present?

      self.class.find_by(response_id: previous_response_id)
    end

    # Returns the next response in this conversation
    #
    # @return [LlmResponse, nil] the next response or nil
    def next_response
      return nil unless conversation_id.present? && turn_number.present?

      self.class.find_by(conversation_id: conversation_id, turn_number: turn_number + 1)
    end

    # Returns the output from a specific tool
    #
    # @param tool_name [String] the tool name
    # @return [Hash, nil] the tool output or nil
    def tool_output_for(tool_name)
      tool_outputs&.dig(tool_name)
    end

    # Returns summary of tools used in this response
    #
    # @return [String] comma-separated list of tools or "None"
    def tools_summary
      return "None" unless used_tools?

      tools_used.join(", ")
    end

    private

    # Triggers automatic evaluation after response is created
    # @return [void]
    def trigger_auto_evaluation
      AutoEvaluationService.evaluate(self, context: "tracked_call")
    end

    # Validates that variables_used is a hash
    def variables_used_must_be_hash
      return if variables_used.nil? || variables_used.is_a?(Hash)

      errors.add(:variables_used, "must be a hash")
    end

    # Validates that response_metadata is a hash
    def response_metadata_must_be_hash
      return if response_metadata.nil? || response_metadata.is_a?(Hash)

      errors.add(:response_metadata, "must be a hash")
    end

    # Validates that context is a hash
    def context_must_be_hash
      return if context.nil? || context.is_a?(Hash)

      errors.add(:context, "must be a hash")
    end

    # Validates that tools_used is an array
    def tools_used_must_be_array
      return if tools_used.nil? || tools_used.is_a?(Array)

      errors.add(:tools_used, "must be an array")
    end

    # Validates that tool_outputs is a hash
    def tool_outputs_must_be_hash
      return if tool_outputs.nil? || tool_outputs.is_a?(Hash)

      errors.add(:tool_outputs, "must be a hash")
    end

    # Sets turn_number for conversation tracking
    def set_turn_number
      return unless conversation_id.present? && turn_number.nil?

      # Find the max turn number in this conversation and increment
      max_turn = self.class.where(conversation_id: conversation_id).maximum(:turn_number) || 0
      self.turn_number = max_turn + 1
    end
  end
end
