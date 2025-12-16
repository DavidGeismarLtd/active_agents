# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250104000003)
# Migration to create the llm_responses table.
#
# LlmResponses track every LLM API call made using a prompt version.
# This includes successful calls, failed calls, performance metrics, and costs.
#
# Example:
#   A customer support agent uses the "greeting" prompt to generate
#   a response. This table records:
#   - What was sent to the LLM (rendered_prompt)
#   - What came back (response_text)
#   - How long it took (response_time_ms)
#   - How much it cost (cost_usd)
#   - Whether it succeeded or failed (status)
class CreatePromptTrackerLlmResponses < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_llm_responses do |t|
      # Foreign key to the prompt version used
      t.references :prompt_version,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_prompt_versions },
                   index: true

      # The rendered prompt that was sent to the LLM
      # (after variable substitution)
      # Example: "Hello John, how can I help with billing?"
      t.text :rendered_prompt, null: false

      # The variables that were used to render the prompt
      # Stored as JSONB for flexibility
      # Example: { "name": "John", "issue": "billing" }
      t.jsonb :variables_used, default: {}

      # The response from the LLM
      # Null if the call failed before getting a response
      t.text :response_text

      # Additional metadata from the LLM response
      # Stored as JSONB for flexibility across providers
      # Example: { "finish_reason": "stop", "model": "gpt-4-0125-preview" }
      t.jsonb :response_metadata, default: {}

      # Status of the LLM call
      # - pending: Call initiated but not yet complete
      # - success: Call completed successfully
      # - error: Call failed with an error
      # - timeout: Call timed out
      t.string :status, null: false, default: "pending", index: true

      # Error information (if status is error or timeout)
      t.string :error_type
      t.text :error_message

      # Performance metrics
      t.integer :response_time_ms # Response time in milliseconds
      t.integer :tokens_prompt     # Number of tokens in the prompt
      t.integer :tokens_completion # Number of tokens in the completion
      t.integer :tokens_total      # Total tokens used

      # Cost tracking
      t.decimal :cost_usd, precision: 10, scale: 6 # Cost in USD

      # LLM provider and model information
      t.string :provider, null: false, index: true # e.g., "openai", "anthropic"
      t.string :model, null: false, index: true    # e.g., "gpt-4", "claude-3"

      # Context information
      t.string :user_id, index: true      # User who triggered this call
      t.string :session_id, index: true   # Session identifier
      t.string :environment, index: true  # e.g., "production", "staging"
      t.jsonb :context, default: {}        # Additional context data

      # Standard Rails timestamps
      t.timestamps
    end

    # Index for finding responses by status and created_at (for monitoring)
    add_index :prompt_tracker_llm_responses,
              [ :status, :created_at ],
              name: "index_llm_responses_on_status_and_created_at"

    # Index for cost analysis by provider and model
    add_index :prompt_tracker_llm_responses,
              [ :provider, :model, :created_at ],
              name: "index_llm_responses_on_provider_model_created_at"
  end
end
