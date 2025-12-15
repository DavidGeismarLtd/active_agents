# Phase 2: Model Updates

## 📋 Overview

Update models to use new polymorphic associations and add new behavior.

## 🔧 Model Changes

### 1. EvaluatorConfig Model

**File:** `app/models/prompt_tracker/evaluator_config.rb`

**Changes:**
```ruby
# BEFORE
belongs_to :prompt, class_name: "PromptTracker::Prompt"
validates :evaluator_key, uniqueness: { scope: :prompt_id }

# AFTER
belongs_to :configurable, polymorphic: true
validates :evaluator_key, uniqueness: { scope: [:configurable_type, :configurable_id] }

# Add threshold validation
validates :threshold,
          numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
          allow_nil: true

# Update dependency validation to work with polymorphic
def dependency_exists
  return unless depends_on.present?
  return unless configurable.respond_to?(:evaluator_configs)

  unless configurable.evaluator_configs.exists?(evaluator_key: depends_on)
    errors.add(:depends_on, "evaluator '#{depends_on}' must be configured")
  end
end

# Update circular dependency check
def no_circular_dependencies
  return unless depends_on.present?
  return unless configurable.respond_to?(:evaluator_configs)

  visited = Set.new([evaluator_key.to_s])
  current = depends_on

  while current.present?
    if visited.include?(current)
      errors.add(:depends_on, "creates a circular dependency")
      break
    end

    visited.add(current)
    dependency_config = configurable.evaluator_configs.find_by(evaluator_key: current)
    current = dependency_config&.depends_on
  end
end

# Add helper methods
def for_prompt_version?
  configurable_type == 'PromptTracker::PromptVersion'
end

def for_prompt_test?
  configurable_type == 'PromptTracker::PromptTest'
end

# Update normalized_weight to work with polymorphic
def normalized_weight
  return 0 unless configurable.respond_to?(:evaluator_configs)

  total_weight = configurable.evaluator_configs.enabled.sum(:weight)
  total_weight > 0 ? (weight / total_weight) : 0
end
```

### 2. PromptVersion Model

**File:** `app/models/prompt_tracker/prompt_version.rb`

**Changes:**
```ruby
# Add association
has_many :evaluator_configs,
         as: :configurable,
         class_name: "PromptTracker::EvaluatorConfig",
         dependent: :destroy

# Add helper methods
def copy_evaluator_configs_from(source_version)
  source_version.evaluator_configs.each do |config|
    evaluator_configs.create!(
      evaluator_key: config.evaluator_key,
      enabled: config.enabled,
      run_mode: config.run_mode,
      priority: config.priority,
      weight: config.weight,
      threshold: config.threshold,
      depends_on: config.depends_on,
      min_dependency_score: config.min_dependency_score,
      config: config.config
    )
  end
end

def has_monitoring_enabled?
  evaluator_configs.enabled.any?
end
```

### 3. Prompt Model

**File:** `app/models/prompt_tracker/prompt.rb`

**Changes:**
```ruby
# REMOVE this association (no longer needed)
# has_many :evaluator_configs, ...

# Add helper to get evaluator configs from active version
def active_evaluator_configs
  active_version&.evaluator_configs || EvaluatorConfig.none
end

def monitoring_enabled?
  active_version&.has_monitoring_enabled? || false
end
```

### 4. PromptTest Model

**File:** `app/models/prompt_tracker/prompt_test.rb`

**Changes:**
```ruby
# Add association
has_many :evaluator_configs,
         as: :configurable,
         class_name: "PromptTracker::EvaluatorConfig",
         dependent: :destroy

# REMOVE JSONB validation
# validates :evaluator_configs, presence: true

# Add helper methods
def copy_evaluator_configs_from_version
  prompt_version.evaluator_configs.each do |config|
    evaluator_configs.create!(
      evaluator_key: config.evaluator_key,
      threshold: config.threshold || 80,
      config: config.config,
      enabled: true,
      run_mode: 'sync',
      priority: config.priority,
      weight: config.weight,
      depends_on: config.depends_on,
      min_dependency_score: config.min_dependency_score
    )
  end
end

def has_evaluators?
  evaluator_configs.any?
end
```

### 5. LlmResponse Model

**File:** `app/models/prompt_tracker/llm_response.rb`

**Changes:**
```ruby
# Update callback to skip test runs
after_create :trigger_auto_evaluation, unless: :is_test_run?

# Add scopes
scope :production_calls, -> { where(is_test_run: false) }
scope :test_calls, -> { where(is_test_run: true) }

# Add helper methods
def production_call?
  !is_test_run?
end

def test_call?
  is_test_run?
end

# Update trigger_auto_evaluation to set context
def trigger_auto_evaluation
  AutoEvaluationService.evaluate(self, context: 'tracked_call')
end
```

### 6. Evaluation Model

**File:** `app/models/prompt_tracker/evaluation.rb`

**Changes:**
```ruby
# Add enum
enum evaluation_context: {
  tracked_call: 'tracked_call',  # From host app via track_llm_call
  test_run: 'test_run',          # From PromptTest execution
  manual: 'manual'               # Manual evaluation in UI
}

# Add scopes
scope :tracked, -> { where(evaluation_context: 'tracked_call') }
scope :from_tests, -> { where(evaluation_context: 'test_run') }
scope :manual_only, -> { where(evaluation_context: 'manual') }

# Add validation
validates :evaluation_context, presence: true, inclusion: { in: evaluation_contexts.keys }
```

## 📝 Schema Documentation Updates

Update schema comments in all affected models:

```ruby
# == Schema Information
#
# Table name: prompt_tracker_evaluator_configs
#
#  configurable_type    :string           not null
#  configurable_id      :bigint           not null
#  evaluator_key        :string           not null
#  threshold            :integer
#  ...
```

## ✅ Validation Checklist

- [ ] All associations updated
- [ ] Validations work with polymorphic associations
- [ ] Helper methods added
- [ ] Callbacks updated
- [ ] Scopes added
- [ ] Enums defined
- [ ] Schema comments updated
- [ ] No references to old associations remain

## 🧪 Testing Models

```ruby
# Test polymorphic associations
version = PromptTracker::PromptVersion.first
config = version.evaluator_configs.create!(
  evaluator_key: :length_check,
  weight: 1.0,
  config: { min_length: 10 }
)
config.configurable # => PromptVersion
config.for_prompt_version? # => true

test = PromptTracker::PromptTest.first
test_config = test.evaluator_configs.create!(
  evaluator_key: :length_check,
  threshold: 80,
  config: { min_length: 10 }
)
test_config.configurable # => PromptTest
test_config.for_prompt_test? # => true

# Test LlmResponse callback
response = PromptTracker::LlmResponse.create!(
  prompt_version: version,
  is_test_run: true,
  # ... other attributes
)
# Should NOT trigger auto-evaluation

response = PromptTracker::LlmResponse.create!(
  prompt_version: version,
  is_test_run: false,
  # ... other attributes
)
# SHOULD trigger auto-evaluation

# Test evaluation context
eval = response.evaluations.first
eval.evaluation_context # => "tracked_call"
eval.tracked_call? # => true
```
