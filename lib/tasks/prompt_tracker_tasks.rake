# frozen_string_literal: true

namespace :prompt_tracker do
  desc "Show prompt statistics"
  task stats: :environment do
    puts "📊 PromptTracker Statistics"
    puts "=" * 50
    puts ""

    # Prompts
    total_prompts = PromptTracker::Prompt.count
    active_prompts = PromptTracker::Prompt.active.count
    archived_prompts = PromptTracker::Prompt.archived.count

    puts "Prompts:"
    puts "  Total: #{total_prompts}"
    puts "  Active: #{active_prompts}"
    puts "  Archived: #{archived_prompts}"
    puts ""

    # Versions
    total_versions = PromptTracker::PromptVersion.count
    active_versions = PromptTracker::PromptVersion.active.count

    puts "Versions:"
    puts "  Total: #{total_versions}"
    puts "  Active: #{active_versions}"
    puts ""

    # Responses
    total_responses = PromptTracker::LlmResponse.count
    successful_responses = PromptTracker::LlmResponse.successful.count
    failed_responses = PromptTracker::LlmResponse.failed.count

    puts "LLM Responses:"
    puts "  Total: #{total_responses}"
    puts "  Successful: #{successful_responses}"
    puts "  Failed: #{failed_responses}"

    if total_responses > 0
      success_rate = (successful_responses.to_f / total_responses * 100).round(1)
      puts "  Success rate: #{success_rate}%"

      avg_time = PromptTracker::LlmResponse.successful.average(:response_time_ms)
      puts "  Avg response time: #{avg_time.to_i}ms" if avg_time

      total_cost = PromptTracker::LlmResponse.sum(:cost_usd)
      puts "  Total cost: $#{total_cost.round(4)}" if total_cost > 0
    end
    puts ""

    # Evaluations
    total_evaluations = PromptTracker::Evaluation.count
    human_evaluations = PromptTracker::Evaluation.by_humans.count
    automated_evaluations = PromptTracker::Evaluation.automated.count
    llm_judge_evaluations = PromptTracker::Evaluation.by_llm_judge.count

    puts "Evaluations:"
    puts "  Total: #{total_evaluations}"
    puts "  Human: #{human_evaluations}"
    puts "  Automated: #{automated_evaluations}"
    puts "  LLM Judge: #{llm_judge_evaluations}"

    if total_evaluations > 0
      avg_score = PromptTracker::Evaluation.average(:score)
      puts "  Avg score: #{avg_score.round(2)}" if avg_score
    end
  end
end
