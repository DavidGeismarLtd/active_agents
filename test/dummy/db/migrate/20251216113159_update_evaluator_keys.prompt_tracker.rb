# This migration comes from prompt_tracker (originally 20251125173955)
class UpdateEvaluatorKeys < ActiveRecord::Migration[7.2]
  def up
    # Update evaluator_key values to match new naming convention
    PromptTracker::EvaluatorConfig.where(evaluator_key: "length_check").update_all(evaluator_key: "length")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "keyword_check").update_all(evaluator_key: "keyword")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "format_check").update_all(evaluator_key: "format")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "gpt4_judge").update_all(evaluator_key: "llm_judge")
  end

  def down
    # Reverse the changes
    PromptTracker::EvaluatorConfig.where(evaluator_key: "length").update_all(evaluator_key: "length_check")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "keyword").update_all(evaluator_key: "keyword_check")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "format").update_all(evaluator_key: "format_check")
    PromptTracker::EvaluatorConfig.where(evaluator_key: "llm_judge").update_all(evaluator_key: "gpt4_judge")
  end
end
