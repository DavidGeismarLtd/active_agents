# frozen_string_literal: true

# This migration comes from prompt_tracker (originally 20250104000004)
# Migration to create the evaluations table.
#
# Evaluations store quality ratings for LLM responses.
# They can be created by humans, automated rules, or other LLMs (LLM-as-judge).
#
# Example:
#   A customer support manager reviews an LLM-generated response and rates it:
#   - Overall score: 4.5/5
#   - Criteria scores: { "helpfulness": 5, "tone": 4, "accuracy": 4.5 }
#   - Feedback: "Good response, but could be more concise"
class CreatePromptTrackerEvaluations < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_evaluations do |t|
      # Foreign key to the LLM response being evaluated
      t.references :llm_response,
                   null: false,
                   foreign_key: { to_table: :prompt_tracker_llm_responses },
                   index: true

      # Overall quality score (typically 0-5 or 0-100)
      # The scale is flexible and defined by the evaluator
      t.decimal :score, precision: 10, scale: 2, null: false

      # Minimum and maximum values for the score scale
      # Example: min=0, max=5 for a 5-star rating
      # Example: min=0, max=100 for a percentage
      t.decimal :score_min, precision: 10, scale: 2, default: 0
      t.decimal :score_max, precision: 10, scale: 2, default: 5

      # Detailed scores for specific criteria
      # Stored as JSON for flexibility
      # Example: {
      #   "helpfulness": 5,
      #   "tone": 4,
      #   "accuracy": 4.5,
      #   "conciseness": 3
      # }
      t.jsonb :criteria_scores, default: {}

      # Type of evaluator
      # - human: Manual evaluation by a person
      # - automated: Rule-based automated evaluation
      # - llm_judge: Evaluation by another LLM
      t.string :evaluator_type, null: false, index: true

      # Identifier of who/what did the evaluation
      # For human: user email or ID
      # For automated: rule name or system identifier
      # For llm_judge: model name (e.g., "gpt-4")
      t.string :evaluator_id

      # Human-readable feedback or comments
      t.text :feedback

      # Additional metadata about the evaluation
      # Stored as JSON for flexibility
      # Example: {
      #   "evaluation_time_ms": 2500,
      #   "confidence": 0.85,
      #   "reasoning": "Response was helpful but too verbose"
      # }
      t.jsonb :metadata, default: {}

      # Standard Rails timestamps
      t.timestamps
    end

    # Index for finding evaluations by type and created_at
    add_index :prompt_tracker_evaluations,
              [ :evaluator_type, :created_at ],
              name: "index_evaluations_on_type_and_created_at"

    # Index for finding evaluations by score (for analytics)
    add_index :prompt_tracker_evaluations,
              :score,
              name: "index_evaluations_on_score"
  end
end
