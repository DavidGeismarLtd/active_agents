# Implementation Checklist

## 📋 Pre-Implementation

- [ ] Review all planning documents
- [ ] Create feature branch: `git checkout -b refactor/tests-vs-monitoring`
- [ ] Backup database: `pg_dump prompt_tracker_development > backup.sql`
- [ ] Ensure all current tests pass: `bundle exec rspec`
- [ ] Communicate changes to team

## 🗄️ Phase 1: Database Schema Changes (2-3 hours)

### Migration 1: Make EvaluatorConfig Polymorphic
- [ ] Create migration file
- [ ] Add `configurable_type` and `configurable_id` columns
- [ ] Add `threshold` column
- [ ] Migrate existing data from Prompt to PromptVersion
- [ ] Add indexes
- [ ] Remove old `prompt_id` column
- [ ] Test up migration: `rails db:migrate`
- [ ] Verify data integrity in console
- [ ] Test down migration: `rails db:rollback`
- [ ] Re-run up migration

### Migration 2: Add Test Run Tracking
- [ ] Create migration file
- [ ] Add `is_test_run` boolean column to LlmResponse
- [ ] Backfill from `response_metadata`
- [ ] Add index
- [ ] Test migration
- [ ] Verify data

### Migration 3: Add Evaluation Context
- [ ] Create migration file
- [ ] Add `evaluation_context` string column to Evaluation
- [ ] Backfill based on `llm_response.is_test_run`
- [ ] Add index
- [ ] Test migration
- [ ] Verify data

### Migration 4: Migrate PromptTest Evaluator Configs
- [ ] Create migration file
- [ ] Migrate JSONB to EvaluatorConfig records
- [ ] Remove `evaluator_configs` JSONB column
- [ ] Test migration
- [ ] Verify all test configs migrated

### Validation
- [ ] All migrations run successfully
- [ ] No data loss
- [ ] All indexes created
- [ ] Can rollback all migrations
- [ ] Database constraints intact

## 🔧 Phase 2: Model Updates (3-4 hours)

### EvaluatorConfig Model
- [ ] Change `belongs_to :prompt` to `belongs_to :configurable, polymorphic: true`
- [ ] Update validations for polymorphic association
- [ ] Add `threshold` validation
- [ ] Update dependency validation methods
- [ ] Add helper methods: `for_prompt_version?`, `for_prompt_test?`
- [ ] Update `normalized_weight` method
- [ ] Run model specs: `rspec spec/models/prompt_tracker/evaluator_config_spec.rb`

### PromptVersion Model
- [ ] Add `has_many :evaluator_configs, as: :configurable`
- [ ] Add `copy_evaluator_configs_from` method
- [ ] Add `has_monitoring_enabled?` method
- [ ] Run model specs: `rspec spec/models/prompt_tracker/prompt_version_spec.rb`

### Prompt Model
- [ ] Remove `has_many :evaluator_configs`
- [ ] Add `active_evaluator_configs` helper
- [ ] Add `monitoring_enabled?` helper
- [ ] Run model specs: `rspec spec/models/prompt_tracker/prompt_spec.rb`

### PromptTest Model
- [ ] Add `has_many :evaluator_configs, as: :configurable`
- [ ] Remove JSONB validation
- [ ] Add `copy_evaluator_configs_from_version` method
- [ ] Add `has_evaluators?` method
- [ ] Run model specs: `rspec spec/models/prompt_tracker/prompt_test_spec.rb`

### LlmResponse Model
- [ ] Update callback: `after_create :trigger_auto_evaluation, unless: :is_test_run?`
- [ ] Add scopes: `production_calls`, `test_calls`
- [ ] Add helper methods: `production_call?`, `test_call?`
- [ ] Update `trigger_auto_evaluation` to set context
- [ ] Run model specs: `rspec spec/models/prompt_tracker/llm_response_spec.rb`

### Evaluation Model
- [ ] Add enum: `evaluation_context`
- [ ] Add scopes: `production`, `from_tests`, `manual_only`
- [ ] Add validation
- [ ] Run model specs: `rspec spec/models/prompt_tracker/evaluation_spec.rb`

### Validation
- [ ] All model specs pass
- [ ] No deprecation warnings
- [ ] Schema comments updated
- [ ] Associations work correctly

## 🛠️ Phase 3: Service Layer Updates (2-3 hours)

### AutoEvaluationService
- [ ] Update to use `@prompt_version.evaluator_configs`
- [ ] Add `context` parameter
- [ ] Set `evaluation_context` when creating evaluations
- [ ] Run service specs: `rspec spec/services/prompt_tracker/auto_evaluation_service_spec.rb`

### LlmCallService
- [ ] Set `is_test_run: false` explicitly
- [ ] Run service specs: `rspec spec/services/prompt_tracker/llm_call_service_spec.rb`

### PromptTestRunner
- [ ] Set `is_test_run: true` on LlmResponse
- [ ] Use `EvaluatorConfig` records instead of JSONB
- [ ] Set `evaluation_context: 'test_run'`
- [ ] Run service specs: `rspec spec/services/prompt_tracker/prompt_test_runner_spec.rb`

### RunTestJob
- [ ] Set `is_test_run: true`
- [ ] Use `EvaluatorConfig` records
- [ ] Set evaluation context
- [ ] Run job specs: `rspec spec/jobs/prompt_tracker/run_test_job_spec.rb`

### EvaluationJob
- [ ] Add `context` parameter
- [ ] Set evaluation context
- [ ] Run job specs: `rspec spec/jobs/prompt_tracker/evaluation_job_spec.rb`

### Validation
- [ ] All service specs pass
- [ ] No duplicate evaluation logic
- [ ] Context correctly set

## 🎨 Phase 4: UI Restructuring (4-5 hours)

### Routes
- [ ] Add monitoring namespace
- [ ] Nest evaluator_configs under prompt_versions
- [ ] Update test routes
- [ ] Test routes: `rails routes | grep monitoring`

### Controllers
- [ ] Create `Monitoring::DashboardController`
- [ ] Create `Monitoring::LlmResponsesController`
- [ ] Create `Monitoring::EvaluationsController`
- [ ] Update `EvaluatorConfigsController`
- [ ] Update `PromptsController`
- [ ] Run controller specs

### Views
- [ ] Create monitoring dashboard view
- [ ] Create monitoring responses views
- [ ] Create monitoring evaluations views
- [ ] Create evaluator_configs views
- [ ] Update prompt show page with tabs
- [ ] Update navigation
- [ ] Test UI manually

### Validation
- [ ] All controller specs pass
- [ ] UI renders correctly
- [ ] Navigation works
- [ ] Tabs work
- [ ] Filters work

## 🧪 Phase 5: Testing (4-5 hours)

### Update Factories
- [ ] Update `evaluator_configs` factory
- [ ] Update `llm_responses` factory
- [ ] Update `evaluations` factory
- [ ] Add traits for different contexts

### Write New Specs
- [ ] Model specs for all changes
- [ ] Service specs for all changes
- [ ] Controller specs for monitoring
- [ ] Integration specs for key flows

### Run Full Test Suite
- [ ] `bundle exec rspec`
- [ ] Fix any failing tests
- [ ] Achieve target coverage

### Validation
- [ ] All specs pass
- [ ] Coverage goals met
- [ ] No flaky tests

## ✅ Final Validation

- [ ] All phases complete
- [ ] All tests pass
- [ ] Manual testing complete
- [ ] No console errors
- [ ] No N+1 queries
- [ ] Performance acceptable
- [ ] Documentation updated

## 🚀 Deployment

- [ ] Create PR with detailed description
- [ ] Request code review
- [ ] Address review feedback
- [ ] Merge to main
- [ ] Deploy to staging
- [ ] Run migrations on staging
- [ ] Test on staging
- [ ] Deploy to production
- [ ] Run migrations on production
- [ ] Monitor for errors
- [ ] Announce changes to team

## 🔄 Rollback Plan (If Needed)

- [ ] Revert code changes: `git revert <commit>`
- [ ] Rollback migrations: `rails db:rollback STEP=4`
- [ ] Verify rollback successful
- [ ] Communicate to team

