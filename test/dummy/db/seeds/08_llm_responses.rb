# frozen_string_literal: true

# ============================================================================
# Sample LLM Responses (Tracked Calls)
# ============================================================================

puts "  Creating sample LLM responses..."

# Get prompt versions
support_greeting_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "customer_support_greeting" })
  .where(status: "deprecated")
  .first!

support_greeting_v3 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "customer_support_greeting" })
  .where(status: "active")
  .first!

email_summary_v1 = PromptTracker::PromptVersion.joins(:prompt)
  .where(prompt_tracker_prompts: { name: "email_summary_generator" })
  .where(status: "active")
  .first!

# Successful responses for support greeting v3
5.times do |i|
  response = support_greeting_v3.llm_responses.create!(
    rendered_prompt: "Hi John! Thanks for contacting us. I'm here to help with your billing question. What's going on?",
    variables_used: { "customer_name" => "John", "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-4o",
    user_id: "user_#{i + 1}",
    session_id: "session_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "I'd be happy to help you with your billing question. Could you please provide more details about the specific issue you're experiencing?",
    response_time_ms: rand(800..1500),
    tokens_prompt: 25,
    tokens_completion: rand(20..30),
    tokens_total: rand(45..55),
    cost_usd: rand(0.0008..0.0015).round(6),
    response_metadata: { "finish_reason" => "stop", "model" => "gpt-4-0125-preview" }
  )
end

# Failed response
failed_response = support_greeting_v3.llm_responses.create!(
  rendered_prompt: "Hi Jane! Thanks for contacting us. I'm here to help with your technical question. What's going on?",
  variables_used: { "customer_name" => "Jane", "issue_category" => "technical" },
  provider: "openai",
  model: "gpt-4o",
  user_id: "user_6",
  session_id: "session_6",
  environment: "production"
)

failed_response.mark_error!(
  error_type: "OpenAI::RateLimitError",
  error_message: "Rate limit exceeded. Please try again in 20 seconds.",
  response_time_ms: 450
)

# Timeout response
timeout_response = support_greeting_v3.llm_responses.create!(
  rendered_prompt: "Hi Bob! Thanks for contacting us. I'm here to help with your account question. What's going on?",
  variables_used: { "customer_name" => "Bob", "issue_category" => "account" },
  provider: "anthropic",
  model: "claude-3-opus",
  user_id: "user_7",
  session_id: "session_7",
  environment: "production"
)

timeout_response.mark_timeout!(
  response_time_ms: 30000,
  error_message: "Request timed out after 30 seconds"
)

# Responses for older versions (v1 and v2)
2.times do |i|
  response = support_greeting_v1.llm_responses.create!(
    rendered_prompt: "Hello Sarah! Thank you for contacting support. How can I help you with billing today?",
    variables_used: { "customer_name" => "Sarah", "issue_category" => "billing" },
    provider: "openai",
    model: "gpt-3.5-turbo",
    user_id: "user_old_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "I would be pleased to assist you with your billing inquiry.",
    response_time_ms: rand(600..1000),
    tokens_total: rand(30..40),
    cost_usd: rand(0.0003..0.0006).round(6)
  )
end

# Email summary responses
3.times do |i|
  response = email_summary_v1.llm_responses.create!(
    rendered_prompt: "Summarize the following email thread in 2-3 sentences:\n\nLong email thread here...",
    variables_used: { "email_thread" => "Long email thread here..." },
    provider: "openai",
    model: "gpt-4o",
    user_id: "user_email_#{i + 1}",
    environment: "production"
  )

  response.mark_success!(
    response_text: "The email thread discusses the upcoming product launch. The team agrees on a March 15th release date. Action items include finalizing the marketing materials and scheduling a press release.",
    response_time_ms: rand(1000..2000),
    tokens_total: rand(60..80),
    cost_usd: rand(0.0015..0.0025).round(6)
  )
end

puts "  ✓ Created sample LLM responses (10 successful, 1 failed, 1 timeout)"
