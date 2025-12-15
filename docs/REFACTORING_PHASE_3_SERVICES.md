# Phase 3: Service Layer Updates

## 📋 Overview

Update services and jobs to:
1. Use polymorphic EvaluatorConfig
2. Set evaluation context
3. Mark test runs appropriately
4. Remove duplicate evaluation logic

## 🔧 Service Changes

### 1. AutoEvaluationService

**File:** `app/services/prompt_tracker/auto_evaluation_service.rb`

**Changes:**
```ruby
class AutoEvaluationService
  def initialize(llm_response, context: 'tracked_call')
    @llm_response = llm_response
    @prompt_version = llm_response.prompt_version
    @context = context
  end

  def self.evaluate(llm_response, context: 'tracked_call')
    new(llm_response, context: context).evaluate
  end

  def evaluate
    return unless @prompt_version

    # Get evaluator configs from PromptVersion (not Prompt)
    independent_configs = @prompt_version.evaluator_configs.enabled.independent.by_priority
    independent_configs.each { |config| run_evaluation(config) }

    dependent_configs = @prompt_version.evaluator_configs.enabled.dependent.by_priority
    dependent_configs.each do |config|
      next unless config.dependency_met?(@llm_response)
      run_evaluation(config)
    end
  end

  private

  def create_evaluation(config, result)
    @llm_response.evaluations.create!(
      evaluator_type: result.evaluator_type,
      evaluator_id: result.evaluator_id,
      score: result.score,
      score_min: result.score_min,
      score_max: result.score_max,
      feedback: result.feedback,
      metadata: result.metadata,
      criteria_scores: result.criteria_scores,
      evaluation_context: @context  # NEW: Set context
    )
  end
end
```

### 2. LlmCallService

**File:** `app/services/prompt_tracker/llm_call_service.rb`

**Changes:**
```ruby
def create_pending_response(prompt_version, rendered_prompt)
  prompt_version.llm_responses.create!(
    rendered_prompt: rendered_prompt,
    variables_used: variables,
    provider: provider,
    model: model,
    status: "pending",
    user_id: user_id,
    session_id: session_id,
    environment: environment,
    context: metadata,
    ab_test: ab_test,
    ab_variant: ab_variant,
    is_test_run: false  # NEW: Explicitly mark as production call
  )
end
```

### 3. PromptTestRunner

**File:** `app/services/prompt_tracker/prompt_test_runner.rb`

**Changes:**
```ruby
def execute_llm_call(&block)
  # ... existing code ...

  llm_response = LlmResponse.create!(
    prompt_version: prompt_version,
    rendered_prompt: rendered_prompt,
    variables_used: prompt_test.template_variables,
    provider: provider,
    model: model,
    response_text: extract_response_text(llm_api_response),
    tokens_prompt: tokens[:prompt],
    tokens_completion: tokens[:completion],
    tokens_total: tokens[:total],
    status: "success",
    is_test_run: true,  # NEW: Mark as test run
    response_metadata: { test_run: true }  # Keep for backwards compatibility
  )

  # ... rest of code ...
end

def run_evaluators(llm_response)
  results = []

  # Use EvaluatorConfig records (not JSONB)
  prompt_test.evaluator_configs.enabled.by_priority.each do |config|
    evaluator = config.build_evaluator(llm_response)

    evaluation = if evaluator.is_a?(PromptTracker::Evaluators::LlmJudgeEvaluator)
      evaluator.evaluate do |judge_prompt|
        if use_real_llm?
          call_real_llm_judge(judge_prompt, config.config)
        else
          generate_mock_judge_response(judge_prompt, config.config)
        end
      end
    else
      evaluator.evaluate
    end

    # Set evaluation context
    evaluation.update!(evaluation_context: 'test_run')

    # Check threshold
    threshold = config.threshold || 80
    passed = evaluation.score >= threshold

    results << {
      evaluator_key: config.evaluator_key.to_s,
      score: evaluation.score,
      threshold: threshold,
      passed: passed,
      feedback: evaluation.feedback
    }
  end

  results
end
```

### 4. RunTestJob

**File:** `app/jobs/prompt_tracker/run_test_job.rb`

**Changes:**
```ruby
def execute_llm_call(test, version, use_real_llm)
  # ... existing code ...

  llm_response = LlmResponse.create!(
    prompt_version: version,
    rendered_prompt: rendered_prompt,
    variables_used: test.template_variables,
    provider: provider,
    model: model,
    response_text: response_text,
    tokens_prompt: tokens[:prompt],
    tokens_completion: tokens[:completion],
    tokens_total: tokens[:total],
    status: "success",
    is_test_run: true,  # NEW: Mark as test run
    response_metadata: { test_run: true }
  )

  llm_response
end

def run_evaluators(test, llm_response, use_real_llm)
  results = []

  # Use EvaluatorConfig records (not JSONB)
  test.evaluator_configs.enabled.by_priority.each do |config|
    evaluator = config.build_evaluator(llm_response)

    evaluation = if evaluator.is_a?(PromptTracker::Evaluators::LlmJudgeEvaluator)
      evaluator.evaluate do |judge_prompt|
        if use_real_llm
          call_real_llm_judge(judge_prompt, config.config)
        else
          generate_mock_judge_response(judge_prompt, config.config)
        end
      end
    else
      evaluator.evaluate
    end

    # Set evaluation context
    evaluation.update!(evaluation_context: 'test_run')

    # Check threshold
    threshold = config.threshold || 80
    passed = evaluation.score >= threshold

    results << {
      evaluator_key: config.evaluator_key.to_s,
      score: evaluation.score,
      threshold: threshold,
      passed: passed,
      feedback: evaluation.feedback
    }
  end

  results
end
```

### 5. EvaluationJob

**File:** `app/jobs/prompt_tracker/evaluation_job.rb`

**Changes:**
```ruby
def perform(llm_response_id, evaluator_config_id, check_dependency: false, context: 'tracked_call')
  llm_response = LlmResponse.find(llm_response_id)
  config = EvaluatorConfig.find(evaluator_config_id)

  # Check dependency if needed
  if check_dependency && !config.dependency_met?(llm_response)
    Rails.logger.info "Skipping evaluation - dependency not met"
    return
  end

  # Build and run evaluator
  evaluator = config.build_evaluator(llm_response)
  result = evaluator.evaluate

  # Create evaluation with context
  llm_response.evaluations.create!(
    evaluator_type: result.evaluator_type,
    evaluator_id: result.evaluator_id,
    score: result.score,
    score_min: result.score_min,
    score_max: result.score_max,
    feedback: result.feedback,
    metadata: result.metadata,
    criteria_scores: result.criteria_scores,
    evaluation_context: context  # NEW: Set context
  )
end
```

## ✅ Validation Checklist

- [ ] AutoEvaluationService uses PromptVersion.evaluator_configs
- [ ] LlmCallService marks responses as is_test_run: false
- [ ] PromptTestRunner marks responses as is_test_run: true
- [ ] RunTestJob uses EvaluatorConfig records (not JSONB)
- [ ] All evaluations have evaluation_context set
- [ ] No duplicate evaluation logic
- [ ] Dependencies work correctly

## 🧪 Testing Services

```ruby
# Test AutoEvaluationService
version = PromptTracker::PromptVersion.first
version.evaluator_configs.create!(
  evaluator_key: :length_check,
  enabled: true,
  run_mode: 'sync',
  weight: 1.0,
  config: { min_length: 10 }
)

response = version.llm_responses.create!(
  rendered_prompt: "Test",
  is_test_run: false,
  # ... other attributes
)

# Should auto-evaluate
response.evaluations.count # => 1
response.evaluations.first.evaluation_context # => "tracked_call"

# Test PromptTestRunner
test = PromptTracker::PromptTest.first
test.evaluator_configs.create!(
  evaluator_key: :length_check,
  threshold: 80,
  config: { min_length: 10 }
)

runner = PromptTracker::PromptTestRunner.new(test, version)
test_run = runner.run! { |prompt| "Mock response" }

test_run.llm_response.is_test_run? # => true
test_run.llm_response.evaluations.first.evaluation_context # => "test_run"
```
