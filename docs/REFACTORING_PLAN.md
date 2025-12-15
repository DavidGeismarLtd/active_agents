# Refactoring Plan: Tests vs Production Monitoring

## 📋 Executive Summary

This document outlines the architectural changes needed to properly separate:
- **Tests** (pre-deployment validation)
- **Production Monitoring** (runtime evaluation via `track_llm_call`)

## 🎯 Goals

1. **Move EvaluatorConfig from Prompt → PromptVersion**
   - Each version has its own evaluation strategy
   - Enables version-specific evaluation criteria
   - Supports A/B testing of evaluation configs

2. **Prevent Auto-Evaluation on Test Runs**
   - Tests control their own evaluators
   - No duplicate evaluations
   - Clear separation of concerns

3. **Distinguish Evaluation Contexts**
   - Production monitoring vs test validation
   - Different UI sections
   - Separate analytics

4. **Unify EvaluatorConfig Model**
   - Remove JSONB `evaluator_configs` from PromptTest
   - Use polymorphic EvaluatorConfig for both PromptVersion and PromptTest
   - Single source of truth

## 📊 Current State vs Target State

### Current Architecture

```
Prompt (1) ──────> (N) EvaluatorConfig
  │                      ├─ evaluator_key
  │                      ├─ weight
  │                      ├─ run_mode
  │                      └─ config (JSONB)
  │
  └──> (N) PromptVersion
         └──> (N) LlmResponse
                ├─ after_create :trigger_auto_evaluation (ALWAYS)
                └──> (N) Evaluation

PromptTest
  ├─ evaluator_configs (JSONB array)
  │    ├─ evaluator_key
  │    ├─ threshold
  │    └─ config
  └──> (N) PromptTestRun
         └──> LlmResponse (triggers auto-eval + test evals = DUPLICATE!)
```

**Problems:**
- ❌ EvaluatorConfig on Prompt (not version-specific)
- ❌ Duplicate evaluator config schemas (model vs JSONB)
- ❌ Auto-evaluation runs on ALL LlmResponse creation (including tests)
- ❌ No distinction between test evals and production evals

### Target Architecture

```
PromptVersion (1) ──────> (N) EvaluatorConfig (polymorphic)
  │                              ├─ configurable_type: "PromptVersion"
  │                              ├─ configurable_id
  │                              ├─ evaluator_key
  │                              ├─ weight
  │                              ├─ threshold (NEW)
  │                              ├─ run_mode
  │                              ├─ depends_on
  │                              └─ config (JSONB)
  │
  └──> (N) LlmResponse
         ├─ is_test_run (boolean)
         ├─ after_create :trigger_auto_evaluation, unless: :is_test_run?
         └──> (N) Evaluation
                └─ evaluation_context (enum: production_monitoring, test_run, manual)

PromptTest (1) ──────> (N) EvaluatorConfig (polymorphic)
  │                          ├─ configurable_type: "PromptTest"
  │                          ├─ configurable_id
  │                          ├─ evaluator_key
  │                          ├─ threshold
  │                          └─ config (JSONB)
  │
  └──> (N) PromptTestRun
         └──> LlmResponse (is_test_run: true, no auto-eval)
```

**Benefits:**
- ✅ Version-specific evaluation configs
- ✅ Single EvaluatorConfig model (no duplication)
- ✅ Tests don't trigger auto-evaluation
- ✅ Clear context tracking (production vs test)
- ✅ Can copy configs between versions and tests
- ✅ Tests can use dependencies, weights, priorities
- ✅ Production can use thresholds for alerting

## 🗂️ Implementation Phases

### Phase 1: Database Schema Changes
**Files:** `db/migrate/`, models
**Estimated Time:** 2-3 hours
**Details:** See `REFACTORING_PHASE_1_DATABASE.md`

### Phase 2: Model Updates
**Files:** `app/models/prompt_tracker/`
**Estimated Time:** 3-4 hours
**Details:** See `REFACTORING_PHASE_2_MODELS.md`

### Phase 3: Service Layer Updates
**Files:** `app/services/prompt_tracker/`, `app/jobs/prompt_tracker/`
**Estimated Time:** 2-3 hours
**Details:** See `REFACTORING_PHASE_3_SERVICES.md`

### Phase 4: UI Restructuring
**Files:** `app/controllers/`, `app/views/`, `config/routes.rb`
**Estimated Time:** 4-5 hours
**Details:** See `REFACTORING_PHASE_4_UI.md`

### Phase 5: Testing
**Files:** `spec/`
**Estimated Time:** 4-5 hours
**Details:** See `REFACTORING_PHASE_5_TESTING.md`

## 📅 Timeline

**Total Estimated Time:** 15-20 hours

**Recommended Approach:**
1. Create feature branch: `refactor/tests-vs-monitoring`
2. Implement phases sequentially (each phase builds on previous)
3. Run tests after each phase
4. Create PR with comprehensive documentation
5. Deploy with data migration plan

## 🚨 Risk Assessment

### High Risk
- **Data Migration:** Moving EvaluatorConfig from Prompt to PromptVersion
  - Mitigation: Reversible migration, backup data, test thoroughly

### Medium Risk
- **Breaking Changes:** Existing code using `prompt.evaluator_configs`
  - Mitigation: Comprehensive search and replace, deprecation warnings

### Low Risk
- **UI Changes:** New monitoring section
  - Mitigation: Incremental rollout, feature flags

## 📝 Success Criteria

- [ ] All tests pass (models, services, controllers)
- [ ] Data migration completes successfully
- [ ] UI clearly separates Tests and Monitoring
- [ ] No duplicate evaluations on test runs
- [ ] Can copy evaluator configs between versions and tests
- [ ] Production monitoring works as expected
- [ ] Documentation updated

## 🔄 Rollback Plan

1. Revert database migrations (down migrations provided)
2. Restore from backup if needed
3. Revert code changes via git
4. Clear cache and restart services

## 📚 Related Documents

- `REFACTORING_PHASE_1_DATABASE.md` - Database schema changes
- `REFACTORING_PHASE_2_MODELS.md` - Model updates
- `REFACTORING_PHASE_3_SERVICES.md` - Service layer changes
- `REFACTORING_PHASE_4_UI.md` - UI restructuring
- `REFACTORING_PHASE_5_TESTING.md` - Testing strategy

