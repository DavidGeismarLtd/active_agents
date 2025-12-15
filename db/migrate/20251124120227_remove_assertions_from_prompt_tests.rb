class RemoveAssertionsFromPromptTests < ActiveRecord::Migration[7.2]
  def up
    # Migrate existing data to evaluator configs
    PromptTracker::PromptTest.find_each do |test|
      # Migrate expected_patterns
      if test.expected_patterns.present? && test.expected_patterns.any?
        test.evaluator_configs.create!(
          evaluator_key: "pattern_match",
          evaluation_mode: "binary",
          enabled: true,
          priority: 1000,  # High priority - binary evaluators show first
          weight: 0,       # Binary evaluators don't contribute to score
          run_mode: "sync",
          config: {
            patterns: test.expected_patterns,
            match_all: true
          }
        )
      end

      # Migrate expected_output
      if test.expected_output.present?
        test.evaluator_configs.create!(
          evaluator_key: "exact_match",
          evaluation_mode: "binary",
          enabled: true,
          priority: 1001,  # High priority - binary evaluators show first
          weight: 0,       # Binary evaluators don't contribute to score
          run_mode: "sync",
          config: {
            expected_text: test.expected_output,
            case_sensitive: false,
            trim_whitespace: true
          }
        )
      end
    end

    # Remove columns
    remove_column :prompt_tracker_prompt_tests, :expected_patterns
    remove_column :prompt_tracker_prompt_tests, :expected_output
  end

  def down
    add_column :prompt_tracker_prompt_tests, :expected_patterns, :jsonb, default: [], null: false
    add_column :prompt_tracker_prompt_tests, :expected_output, :text
  end
end
