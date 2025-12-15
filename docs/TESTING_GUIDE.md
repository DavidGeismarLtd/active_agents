# Testing Guide for PromptTracker

This guide explains how to run and verify the Phase 1 implementation.

## Running Migrations

### Option 1: Run migrations in development
```bash
bin/rails db:migrate
```

### Option 2: Run migrations in test environment
```bash
bin/rails db:migrate RAILS_ENV=test
```

### Option 3: Reset and run all migrations
```bash
bin/rails db:migrate:reset
```

## Running Tests

### Run all model tests
```bash
bin/rails test test/models/prompt_tracker/
```

### Run individual model tests
```bash
# Test Prompt model
bin/rails test test/models/prompt_tracker/prompt_test.rb

# Test PromptVersion model
bin/rails test test/models/prompt_tracker/prompt_version_test.rb

# Test LlmResponse model
bin/rails test test/models/prompt_tracker/llm_response_test.rb

# Test Evaluation model
bin/rails test test/models/prompt_tracker/evaluation_test.rb
```

### Run a specific test
```bash
bin/rails test test/models/prompt_tracker/prompt_test.rb:25
```

## Manual Testing in Rails Console

### Start the console
```bash
bin/rails console
```

### Test Prompt Model

```ruby
# Create a prompt
prompt = PromptTracker::Prompt.create!(
  name: "customer_greeting",
  description: "Greeting for customer support",
  category: "support",
  tags: ["customer-facing", "high-priority"],
  created_by: "john@example.com"
)

# Verify it was created
prompt.persisted?  # => true
prompt.id  # => 1

# Test validations
invalid_prompt = PromptTracker::Prompt.new(name: "Invalid Name")
invalid_prompt.valid?  # => false
invalid_prompt.errors.full_messages  # => ["Name must contain only lowercase letters..."]

# Test scopes
PromptTracker::Prompt.active  # => [prompt]
PromptTracker::Prompt.in_category("support")  # => [prompt]

# Test archive
prompt.archive!
prompt.archived?  # => true
```

### Test PromptVersion Model

```ruby
# Create a version
version = prompt.prompt_versions.create!(
  template: "Hello {{customer_name}}, how can I help with {{issue}}?",
  status: "active",
  source: "file",
  variables_schema: [
    { "name" => "customer_name", "type" => "string", "required" => true },
    { "name" => "issue", "type" => "string", "required" => false }
  ],
  model_config: { "temperature" => 0.7, "max_tokens" => 150 }
)

# Test auto-increment version number
version.version_number  # => 1

# Create another version
version2 = prompt.prompt_versions.create!(
  template: "Hi {{customer_name}}! What can I help you with today?",
  status: "draft",
  source: "web_ui"
)
version2.version_number  # => 2

# Test render method
rendered = version.render(customer_name: "John", issue: "billing")
# => "Hello John, how can I help with billing?"

# Test with missing required variable
version.render(issue: "billing")  # => ArgumentError: Missing required variables: customer_name

# Test activate method
version2.activate!
version.reload.status  # => "deprecated"
version2.status  # => "active"

# Test immutability (will work after creating a response)
version.template = "New template"
version.save  # => true (no responses yet)
```

### Test LlmResponse Model

```ruby
# Create an LLM response
response = version.llm_responses.create!(
  rendered_prompt: "Hello John, how can I help with billing?",
  variables_used: { "customer_name" => "John", "issue" => "billing" },
  provider: "openai",
  model: "gpt-4",
  user_id: "user_123",
  session_id: "session_456",
  environment: "production"
)

# Initially pending
response.status  # => "pending"
response.pending?  # => true

# Mark as successful
response.mark_success!(
  response_text: "Hi John! I'd be happy to help with your billing question. Could you please provide more details?",
  response_time_ms: 1200,
  tokens_prompt: 15,
  tokens_completion: 20,
  tokens_total: 35,
  cost_usd: 0.00105,
  response_metadata: { "finish_reason" => "stop", "model" => "gpt-4-0125-preview" }
)

# Verify success
response.reload
response.success?  # => true
response.response_time_ms  # => 1200
response.cost_usd  # => 0.00105
response.summary  # => "Success: 1200ms, 35 tokens, $0.00105"

# Test cost per token
response.cost_per_token  # => 0.00003

# Create a failed response
failed_response = version.llm_responses.create!(
  rendered_prompt: "Hello Jane",
  variables_used: { "customer_name" => "Jane" },
  provider: "openai",
  model: "gpt-4"
)

failed_response.mark_error!(
  error_type: "OpenAI::RateLimitError",
  error_message: "Rate limit exceeded. Please try again later.",
  response_time_ms: 500
)

failed_response.failed?  # => true
failed_response.summary  # => "Failed: OpenAI::RateLimitError - Rate limit exceeded..."

# Test scopes
PromptTracker::LlmResponse.successful  # => [response]
PromptTracker::LlmResponse.failed  # => [failed_response]
PromptTracker::LlmResponse.for_provider("openai")  # => [response, failed_response]
PromptTracker::LlmResponse.for_user("user_123")  # => [response]
```

### Test Evaluation Model

```ruby
# Create a human evaluation
evaluation = response.evaluations.create!(
  score: 4.5,
  score_min: 0,
  score_max: 5,
  criteria_scores: {
    "helpfulness" => 5,
    "tone" => 4,
    "accuracy" => 4.5,
    "conciseness" => 4
  },
  evaluator_type: "human",
  evaluator_id: "manager@example.com",
  feedback: "Great response! Very helpful and professional. Could be slightly more concise."
)

# Test score calculations
evaluation.normalized_score  # => 0.9
evaluation.score_percentage  # => 90.0
evaluation.passing?  # => true (default threshold is 70%)
evaluation.passing?(95)  # => false

# Test criteria access
evaluation.criterion_score("helpfulness")  # => 5
evaluation.criterion_score("tone")  # => 4
evaluation.criteria_names  # => ["helpfulness", "tone", "accuracy", "conciseness"]
evaluation.has_criteria_scores?  # => true

# Test summary
evaluation.summary  # => "Human: 4.5/5 (90.0%)"

# Create a keyword evaluator evaluation
keyword_eval = response.evaluations.create!(
  score: 85,
  score_min: 0,
  score_max: 100,
  evaluator_type: "PromptTracker::Evaluators::KeywordEvaluator",
  metadata: { "matched_keywords" => ["help", "support"], "processing_time_ms" => 150 }
)

keyword_eval.score_percentage  # => 85.0

# Create an LLM judge evaluation
llm_eval = response.evaluations.create!(
  score: 4,
  score_max: 5,
  evaluator_type: "PromptTracker::Evaluators::LlmJudgeEvaluator",
  feedback: "The response is helpful and accurate, but could be more empathetic.",
  metadata: { "reasoning" => "Good factual content, tone could be warmer" }
)

# Test scopes
PromptTracker::Evaluation.by_evaluator("PromptTracker::Evaluators::KeywordEvaluator")  # => [keyword_eval]
PromptTracker::Evaluation.by_evaluator("PromptTracker::Evaluators::LlmJudgeEvaluator")  # => [llm_eval]
PromptTracker::Evaluation.above_score(4.0)  # => [evaluation, llm_eval]
PromptTracker::Evaluation.tracked  # => evaluations from tracked_call context
PromptTracker::Evaluation.from_tests  # => evaluations from test_run context
```

### Test Associations and Metrics

```ruby
# Test associations
prompt.prompt_versions.count  # => 2
prompt.llm_responses.count  # => 2
version.llm_responses.count  # => 2
response.evaluations.count  # => 3

# Test metrics
prompt.total_llm_calls  # => 2
prompt.total_cost_usd  # => 0.00105
prompt.average_response_time_ms  # => 850.0 (average of 1200 and 500)

version.total_llm_calls  # => 2
version.total_cost_usd  # => 0.00105
version.average_response_time_ms  # => 850.0

response.average_evaluation_score  # => 4.5 (average of 4.5, 85/100*5, and 4)
response.evaluation_count  # => 3

# Test through associations
evaluation.prompt_version  # => version
evaluation.prompt  # => prompt
```

## Expected Test Results

When you run the full test suite, you should see:

```
Run options: --seed 12345

# Running:

.....................................................................................................

Finished in 2.5s, 50 runs/s, 125 assertions/s.

125 runs, 125 assertions, 0 failures, 0 errors, 0 skips
```

## Troubleshooting

### If migrations fail

```bash
# Check migration status
bin/rails db:migrate:status

# Rollback last migration
bin/rails db:rollback

# Rollback all migrations
bin/rails db:rollback STEP=4

# Reset database
bin/rails db:drop db:create db:migrate
```

### If tests fail

1. **Check that migrations have run:**
   ```bash
   bin/rails db:migrate RAILS_ENV=test
   ```

2. **Check for syntax errors:**
   ```bash
   ruby -c app/models/prompt_tracker/prompt.rb
   ```

3. **Run tests with backtrace:**
   ```bash
   bin/rails test test/models/prompt_tracker/prompt_test.rb --backtrace
   ```

4. **Check test database:**
   ```bash
   bin/rails db:test:prepare
   ```

### If console commands fail

1. **Reload the console:**
   ```ruby
   reload!
   ```

2. **Check that models are loaded:**
   ```ruby
   PromptTracker::Prompt
   # Should show the class, not an error
   ```

3. **Check database connection:**
   ```ruby
   ActiveRecord::Base.connection.active?
   # => true
   ```

## Next Steps

After verifying Phase 1 works correctly:

1. ✅ All migrations run successfully
2. ✅ All 125 tests pass
3. ✅ Manual testing in console works
4. ✅ Associations work correctly
5. ✅ Metrics calculate correctly

You're ready to move on to **Phase 2: File-Based Prompt System**!
