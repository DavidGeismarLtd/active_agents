# Quick Reference Guide

## 🔍 What Changed?

### Database Changes

| Table | Old Column | New Column | Type |
|-------|-----------|------------|------|
| `evaluator_configs` | `prompt_id` | `configurable_type` + `configurable_id` | Polymorphic |
| `evaluator_configs` | - | `threshold` | Integer |
| `llm_responses` | - | `is_test_run` | Boolean |
| `evaluations` | - | `evaluation_context` | String (enum: tracked_call, test_run, manual) |
| `prompt_tests` | `evaluator_configs` (JSONB) | - | Removed |

### Model Changes

| Model | Old Association | New Association |
|-------|----------------|-----------------|
| `Prompt` | `has_many :evaluator_configs` | Removed |
| `PromptVersion` | - | `has_many :evaluator_configs, as: :configurable` |
| `PromptTest` | - | `has_many :evaluator_configs, as: :configurable` |
| `EvaluatorConfig` | `belongs_to :prompt` | `belongs_to :configurable, polymorphic: true` |

### Code Changes

**Before:**
```ruby
# Getting evaluator configs
prompt.evaluator_configs

# Creating LlmResponse (always triggers auto-eval)
LlmResponse.create!(...)

# PromptTest evaluators (JSONB)
test.evaluator_configs # => [{evaluator_key: "...", threshold: 80}]
```

**After:**
```ruby
# Getting evaluator configs
prompt_version.evaluator_configs

# Creating LlmResponse (conditional auto-eval)
LlmResponse.create!(is_test_run: false) # triggers auto-eval
LlmResponse.create!(is_test_run: true)  # does NOT trigger auto-eval

# PromptTest evaluators (ActiveRecord)
test.evaluator_configs # => ActiveRecord::Relation
test.evaluator_configs.first # => EvaluatorConfig instance
```

## 📍 Where to Find Things

### Tests Section

**Routes:**
- `/prompts/:id/versions/:version_id/tests` - Tests for a version
- `/test-runs` - All test runs

**Controllers:**
- `PromptTestsController`
- `PromptTestRunsController`

**Views:**
- `app/views/prompt_tracker/prompt_tests/`

### Monitoring Section

**Routes:**
- `/monitoring` - Dashboard
- `/monitoring/responses` - Production LLM responses
- `/monitoring/evaluations` - Production evaluations

**Controllers:**
- `Monitoring::DashboardController`
- `Monitoring::LlmResponsesController`
- `Monitoring::EvaluationsController`

**Views:**
- `app/views/prompt_tracker/monitoring/dashboard/`
- `app/views/prompt_tracker/monitoring/llm_responses/`
- `app/views/prompt_tracker/monitoring/evaluations/`

### Evaluator Config Section

**Routes:**
- `/prompts/:id/versions/:version_id/monitoring` - Monitoring config for version

**Controllers:**
- `EvaluatorConfigsController`

**Views:**
- `app/views/prompt_tracker/evaluator_configs/`

## 🔧 Common Tasks

### Configure Monitoring for a Version

```ruby
version = PromptVersion.find(123)

version.evaluator_configs.create!(
  evaluator_key: :length_check,
  enabled: true,
  run_mode: 'async',
  priority: 10,
  weight: 0.3,
  threshold: 80,
  config: { min_length: 50, max_length: 500 }
)
```

### Copy Monitoring Config to Another Version

```ruby
source_version = PromptVersion.find(1)
target_version = PromptVersion.find(2)

target_version.copy_evaluator_configs_from(source_version)
```

### Configure Evaluators for a Test

```ruby
test = PromptTest.find(456)

test.evaluator_configs.create!(
  evaluator_key: :keyword_check,
  threshold: 90,
  config: { keywords: ['hello', 'world'] }
)
```

### Copy Version Monitoring Config to Test

```ruby
test = PromptTest.find(456)
test.copy_evaluator_configs_from_version
```

### Query Production vs Test Data

```ruby
# Production/staging/dev LLM responses (from host app)
LlmResponse.production_calls

# Test LLM responses
LlmResponse.test_calls

# Tracked evaluations (from host app via track_llm_call)
Evaluation.tracked

# Filter by environment
Evaluation.tracked.joins(:llm_response).where(llm_responses: { environment: 'production' })
Evaluation.tracked.joins(:llm_response).where(llm_responses: { environment: 'staging' })

# Test evaluations
Evaluation.from_tests

# Manual evaluations
Evaluation.manual_only
```

### Check if Monitoring is Enabled

```ruby
version = PromptVersion.find(123)
version.has_monitoring_enabled? # => true/false

prompt = Prompt.find(1)
prompt.monitoring_enabled? # => true/false (checks active version)
```

## 🎨 UI Components

### Navigation

```erb
<%= link_to "Tests", prompt_test_suites_path, class: "nav-link" %>
<%= link_to "Monitoring", monitoring_path, class: "nav-link" %>
```

### Prompt Show Page Tabs

```erb
<!-- Tests Tab (Blue) -->
<a class="nav-link" data-bs-toggle="tab" href="#tests">
  Tests
  <span class="badge bg-primary"><%= @active_version&.prompt_tests&.count || 0 %></span>
</a>

<!-- Monitoring Tab (Green) -->
<a class="nav-link" data-bs-toggle="tab" href="#monitoring">
  Monitoring
  <% if @active_version&.has_monitoring_enabled? %>
    <span class="badge bg-success">Enabled</span>
  <% else %>
    <span class="badge bg-secondary">Disabled</span>
  <% end %>
</a>
```

## 🧪 Testing

### Run All Tests

```bash
bundle exec rspec
```

### Run Specific Tests

```bash
# Models
bundle exec rspec spec/models/prompt_tracker/

# Services
bundle exec rspec spec/services/prompt_tracker/

# Controllers
bundle exec rspec spec/controllers/prompt_tracker/

# Monitoring
bundle exec rspec spec/controllers/prompt_tracker/monitoring/
```

### Create Test Data

```ruby
# Create version with monitoring
version = create(:prompt_version)
create(:evaluator_config, :for_prompt_version, configurable: version)

# Create test with evaluators
test = create(:prompt_test)
create(:evaluator_config, :for_prompt_test, configurable: test)

# Create production response
create(:llm_response, :production_call, prompt_version: version)

# Create test response
create(:llm_response, :test_call, prompt_version: version)

# Create tracked evaluation (from host app)
create(:evaluation, :tracked)

# Create test evaluation
create(:evaluation, :test_run)
```

## 📚 Documentation Files

1. **REFACTORING_PLAN.md** - Start here for overview
2. **REFACTORING_SUMMARY.md** - High-level summary
3. **REFACTORING_QUICK_REFERENCE.md** - This file
4. **REFACTORING_PHASE_1_DATABASE.md** - Database migrations
5. **REFACTORING_PHASE_2_MODELS.md** - Model changes
6. **REFACTORING_PHASE_3_SERVICES.md** - Service changes
7. **REFACTORING_PHASE_4_UI.md** - UI changes
8. **REFACTORING_PHASE_5_TESTING.md** - Testing strategy
9. **REFACTORING_IMPLEMENTATION_CHECKLIST.md** - Implementation steps
