# This migration comes from prompt_tracker (originally 20251203091402)
class CreatePromptTrackerHumanEvaluations < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_human_evaluations do |t|
      t.references :evaluation, null: false, foreign_key: { to_table: :prompt_tracker_evaluations }, index: true
      t.decimal :score, precision: 10, scale: 2, null: false
      t.text :feedback

      t.timestamps
    end
  end
end
