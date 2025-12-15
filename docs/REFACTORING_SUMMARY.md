# Refactoring Summary: Tests vs Production Monitoring

## 📖 Overview

This refactoring separates two distinct use cases that were previously conflated:

1. **Tests** - Pre-deployment validation of prompts
2. **Production Monitoring** - Runtime evaluation of prompts in production

## 🎯 Key Problems Solved

### Problem 1: EvaluatorConfig on Wrong Level
**Before:** EvaluatorConfig belonged to Prompt
**After:** EvaluatorConfig belongs to PromptVersion (polymorphic)
**Benefit:** Each version can have its own evaluation strategy

### Problem 2: Duplicate Evaluations
**Before:** Auto-evaluation ran on ALL LlmResponse creation (including tests)
**After:** Auto-evaluation only runs on production calls (`unless: :is_test_run?`)
**Benefit:** No duplicate evaluations, clear separation of concerns

### Problem 3: Conflated Use Cases
**Before:** No distinction between test evaluations and host app monitoring
**After:** `evaluation_context` field tracks context (test_run, tracked_call, manual)
**Benefit:** Clear analytics, separate UI sections, environment tracked separately

### Problem 4: Duplicated Configuration
**Before:** EvaluatorConfig model + PromptTest.evaluator_configs JSONB
**After:** Single polymorphic EvaluatorConfig model
**Benefit:** No duplication, can reuse configs, consistent features

## 🏗️ Architecture Changes

### Database Schema

```
BEFORE:
Prompt (1) ──> (N) EvaluatorConfig
PromptTest.evaluator_configs (JSONB)

AFTER:
PromptVersion (1) ──> (N) EvaluatorConfig (polymorphic)
PromptTest (1) ──> (N) EvaluatorConfig (polymorphic)
```

### New Fields

- `evaluator_configs.configurable_type` - Polymorphic type
- `evaluator_configs.configurable_id` - Polymorphic ID
- `evaluator_configs.threshold` - Pass/fail threshold (moved from JSONB)
- `llm_responses.is_test_run` - Boolean flag
- `evaluations.evaluation_context` - Enum (tracked_call, test_run, manual)

### Removed Fields

- `evaluator_configs.prompt_id` - Replaced by polymorphic association
- `prompt_tests.evaluator_configs` - Replaced by has_many association

## 🎨 UI Changes

### New Navigation Structure

```
Prompts → Tests → Monitoring → A/B Tests → Analytics
```

### Prompt Show Page

**Tabs:**
1. Overview - General info
2. Tests - Pre-deployment validation (blue theme)
3. Monitoring - Production evaluation (green theme)
4. Versions - Version history

### New Monitoring Section

**Routes:**
- `/monitoring` - Dashboard
- `/monitoring/responses` - Production LLM responses
- `/monitoring/evaluations` - Production evaluations

**Features:**
- Real-time monitoring dashboard
- Production response logs
- Evaluation analytics
- Low score alerts

## 📊 Key Differences: Tests vs Monitoring

| Aspect | Tests | Monitoring |
|--------|-------|------------|
| **Purpose** | Pre-deployment validation | Runtime evaluation from host app |
| **Trigger** | Manual (run test button) | Automatic (on track_llm_call) |
| **Data** | `is_test_run: true` | `is_test_run: false` |
| **Context** | `evaluation_context: 'test_run'` | `evaluation_context: 'tracked_call'` |
| **Environment** | N/A | Tracked separately (production/staging/dev) |
| **UI Color** | Blue (bg-primary) | Green (bg-success) |
| **UI Icon** | clipboard-check | activity |
| **Metrics** | Pass/fail rate, thresholds | Avg score, alerts |
| **Config** | EvaluatorConfig on PromptTest | EvaluatorConfig on PromptVersion |

## 🔄 Migration Strategy

### Data Migration

1. **EvaluatorConfig:** Migrate from Prompt to PromptVersion (assign to active version)
2. **LlmResponse:** Backfill `is_test_run` from `response_metadata`
3. **Evaluation:** Backfill `evaluation_context` from `llm_response.is_test_run`
4. **PromptTest:** Migrate JSONB configs to EvaluatorConfig records

### Code Migration

1. **Models:** Update associations and validations
2. **Services:** Update to use PromptVersion configs, set context
3. **Controllers:** Create monitoring controllers, update existing
4. **Views:** Create monitoring views, update prompt show page

## 📚 Documentation Structure

1. **REFACTORING_PLAN.md** - Executive summary and overview
2. **REFACTORING_PHASE_1_DATABASE.md** - Database migrations
3. **REFACTORING_PHASE_2_MODELS.md** - Model updates
4. **REFACTORING_PHASE_3_SERVICES.md** - Service layer changes
5. **REFACTORING_PHASE_4_UI.md** - UI restructuring
6. **REFACTORING_PHASE_5_TESTING.md** - RSpec testing strategy
7. **REFACTORING_IMPLEMENTATION_CHECKLIST.md** - Step-by-step checklist
8. **REFACTORING_SUMMARY.md** - This document

## ⏱️ Timeline

**Total Estimated Time:** 15-20 hours

- Phase 1 (Database): 2-3 hours
- Phase 2 (Models): 3-4 hours
- Phase 3 (Services): 2-3 hours
- Phase 4 (UI): 4-5 hours
- Phase 5 (Testing): 4-5 hours

## ✅ Success Criteria

- [ ] Tests and monitoring clearly separated in UI
- [ ] No duplicate evaluations on test runs
- [ ] Version-specific evaluation configs work
- [ ] Can copy configs between versions and tests
- [ ] All tests pass
- [ ] Production monitoring dashboard functional
- [ ] Data migration successful

## 🚨 Risks & Mitigation

### High Risk: Data Migration
**Risk:** Losing evaluator configs during migration
**Mitigation:** Reversible migrations, backups, thorough testing

### Medium Risk: Breaking Changes
**Risk:** Existing code using `prompt.evaluator_configs`
**Mitigation:** Comprehensive search/replace, deprecation warnings

### Low Risk: UI Changes
**Risk:** User confusion with new UI
**Mitigation:** Clear visual distinctions, documentation

## 📞 Next Steps

1. Review all documentation
2. Get team approval
3. Create feature branch
4. Follow implementation checklist
5. Create PR
6. Deploy to staging
7. Deploy to production

## 🙋 Questions?

If you have questions about any phase, refer to the detailed phase documentation or ask the team.
