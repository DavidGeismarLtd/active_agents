# This migration comes from prompt_tracker (originally 20250104000005)
class CreatePromptTrackerAbTests < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_ab_tests do |t|
      # Basic Info
      t.references :prompt, null: false, foreign_key: { to_table: :prompt_tracker_prompts }, index: true
      t.string :name, null: false
      t.text :description
      t.string :hypothesis

      # Test Configuration
      t.string :status, null: false, default: "draft"
      # Status values: draft, running, paused, completed, cancelled

      t.string :metric_to_optimize, null: false
      # Options: "cost", "response_time", "quality_score", "success_rate", "custom"

      t.string :optimization_direction, null: false, default: "minimize"
      # Options: "minimize" (for cost/time), "maximize" (for quality/success)

      # Traffic Split - JSONB for flexibility
      # Example: { "A" => 50, "B" => 50 } or { "A" => 80, "B" => 20 }
      t.jsonb :traffic_split, null: false, default: {}

      # Variants - JSONB array
      # Example: [
      #   { "name" => "A", "version_id" => 1, "description" => "Current version" },
      #   { "name" => "B", "version_id" => 2, "description" => "Optimized version" }
      # ]
      t.jsonb :variants, null: false, default: []

      # Statistical Configuration
      t.float :confidence_level, default: 0.95  # 95% confidence
      t.float :minimum_detectable_effect, default: 0.05  # 5% improvement
      t.integer :minimum_sample_size, default: 100  # per variant

      # Results - cached for performance
      # Example: {
      #   "A" => { "count" => 500, "mean" => 1200, "std_dev" => 150 },
      #   "B" => { "count" => 500, "mean" => 950, "std_dev" => 140 },
      #   "winner" => "B",
      #   "p_value" => 0.001,
      #   "confidence" => 0.999,
      #   "improvement" => 20.8
      # }
      t.jsonb :results, default: {}

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at

      # Metadata
      t.string :created_by
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for common queries
    add_index :prompt_tracker_ab_tests, :status
    add_index :prompt_tracker_ab_tests, :metric_to_optimize
    add_index :prompt_tracker_ab_tests, [ :prompt_id, :status ]
    add_index :prompt_tracker_ab_tests, :started_at
    add_index :prompt_tracker_ab_tests, :completed_at
  end
end
