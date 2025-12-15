# Refactoring Documentation: Tests vs Production Monitoring

## 📚 Documentation Index

This directory contains comprehensive documentation for refactoring the PromptTracker application to properly separate **Tests** (pre-deployment validation) from **Production Monitoring** (runtime evaluation).

### 🎯 Start Here

1. **[REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md)** - High-level overview of the refactoring
   - What problems are being solved
   - Key architecture changes
   - Before/after comparison
   - Success criteria

2. **[REFACTORING_QUICK_REFERENCE.md](REFACTORING_QUICK_REFERENCE.md)** - Quick lookup guide
   - What changed (tables, models, code)
   - Where to find things (routes, controllers, views)
   - Common tasks (code examples)
   - Testing commands

### 📋 Planning Documents

3. **[REFACTORING_PLAN.md](REFACTORING_PLAN.md)** - Executive summary and implementation plan
   - Goals and objectives
   - Current vs target architecture
   - Implementation phases overview
   - Timeline and risk assessment

### 🔧 Implementation Guides

4. **[REFACTORING_PHASE_1_DATABASE.md](REFACTORING_PHASE_1_DATABASE.md)** - Database schema changes
   - 4 migrations with full code
   - Data migration strategies
   - Rollback procedures
   - Validation steps

5. **[REFACTORING_PHASE_2_MODELS.md](REFACTORING_PHASE_2_MODELS.md)** - Model updates
   - Polymorphic associations
   - Updated validations
   - New helper methods
   - Testing examples

6. **[REFACTORING_PHASE_3_SERVICES.md](REFACTORING_PHASE_3_SERVICES.md)** - Service layer changes
   - AutoEvaluationService updates
   - LlmCallService updates
   - PromptTestRunner updates
   - Job updates

7. **[REFACTORING_PHASE_4_UI.md](REFACTORING_PHASE_4_UI.md)** - UI restructuring
   - New routes and controllers
   - Monitoring dashboard
   - Updated views
   - Visual design guidelines

8. **[REFACTORING_PHASE_5_TESTING.md](REFACTORING_PHASE_5_TESTING.md)** - RSpec testing strategy
   - Model specs
   - Service specs
   - Controller specs
   - Factory updates

### ✅ Implementation Tools

9. **[REFACTORING_IMPLEMENTATION_CHECKLIST.md](REFACTORING_IMPLEMENTATION_CHECKLIST.md)** - Step-by-step checklist
   - Pre-implementation tasks
   - Phase-by-phase checklist
   - Validation steps
   - Deployment checklist

## 🎯 Key Concepts

### Tests (Pre-Deployment Validation)

**Purpose:** Validate prompts before deploying to production

**Characteristics:**
- Manual trigger (run test button)
- `is_test_run: true`
- `evaluation_context: 'test_run'`
- Blue UI theme
- Pass/fail based on thresholds
- EvaluatorConfig belongs to PromptTest

**User Flow:**
1. Create test for a prompt version
2. Configure evaluators with thresholds
3. Run test manually
4. Review pass/fail results
5. Iterate until all tests pass
6. Deploy to production

### Production Monitoring (Runtime Evaluation)

**Purpose:** Monitor prompt performance in production

**Characteristics:**
- Automatic trigger (on `track_llm_call`)
- `is_test_run: false`
- `evaluation_context: 'tracked_call'`
- Environment tracked separately (production/staging/dev)
- Green UI theme
- Continuous scoring and alerts
- EvaluatorConfig belongs to PromptVersion

**User Flow:**
1. Configure monitoring for a prompt version
2. Deploy version to production
3. Host app calls `track_llm_call`
4. Auto-evaluation runs in background
5. View results in monitoring dashboard
6. Receive alerts for low scores

## 🏗️ Architecture Overview

### Before Refactoring

```
Prompt
├── has_many :evaluator_configs (❌ Wrong level)
└── has_many :prompt_versions
    └── has_many :llm_responses
        └── after_create :trigger_auto_evaluation (❌ Always runs)

PromptTest
└── evaluator_configs (JSONB) (❌ Duplicate schema)
```

**Problems:**
- EvaluatorConfig on Prompt (not version-specific)
- Auto-evaluation runs on ALL responses (including tests)
- Duplicate configuration schemas
- No distinction between test and production evaluations

### After Refactoring

```
PromptVersion
├── has_many :evaluator_configs (polymorphic) ✅
└── has_many :llm_responses
    └── after_create :trigger_auto_evaluation, unless: :is_test_run? ✅

PromptTest
└── has_many :evaluator_configs (polymorphic) ✅

Evaluation
└── evaluation_context (enum) ✅
```

**Benefits:**
- Version-specific evaluation strategies
- No duplicate evaluations
- Single source of truth for configs
- Clear separation of concerns

## 📊 Key Changes Summary

| Aspect | Before | After |
|--------|--------|-------|
| **EvaluatorConfig belongs to** | Prompt | PromptVersion or PromptTest (polymorphic) |
| **Auto-evaluation trigger** | Always | Only for tracked calls (not test runs) |
| **Test evaluator config** | JSONB field | ActiveRecord association |
| **Evaluation context** | Not tracked | Enum field (tracked_call, test_run, manual) |
| **Environment tracking** | Not tracked | Separate field on LlmResponse |
| **UI structure** | Mixed | Separate Tests and Monitoring sections |

## 🚀 Getting Started

### For Implementers

1. Read [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md)
2. Review [REFACTORING_PLAN.md](REFACTORING_PLAN.md)
3. Follow [REFACTORING_IMPLEMENTATION_CHECKLIST.md](REFACTORING_IMPLEMENTATION_CHECKLIST.md)
4. Implement each phase in order
5. Run tests after each phase

### For Reviewers

1. Read [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md)
2. Review architecture diagrams
3. Check each phase document for technical details
4. Verify tests in [REFACTORING_PHASE_5_TESTING.md](REFACTORING_PHASE_5_TESTING.md)

### For Users

1. Read [REFACTORING_QUICK_REFERENCE.md](REFACTORING_QUICK_REFERENCE.md)
2. Learn the difference between Tests and Monitoring
3. Explore the new UI sections
4. Configure monitoring for your prompts

## ⏱️ Timeline

**Total Estimated Time:** 15-20 hours

- Phase 1 (Database): 2-3 hours
- Phase 2 (Models): 3-4 hours
- Phase 3 (Services): 2-3 hours
- Phase 4 (UI): 4-5 hours
- Phase 5 (Testing): 4-5 hours

## 🎯 Success Criteria

- [ ] All tests pass
- [ ] Tests and monitoring clearly separated in UI
- [ ] No duplicate evaluations on test runs
- [ ] Version-specific evaluation configs work
- [ ] Can copy configs between versions and tests
- [ ] Production monitoring dashboard functional
- [ ] Data migration successful
- [ ] Documentation complete

## 📞 Questions?

If you have questions:
1. Check [REFACTORING_QUICK_REFERENCE.md](REFACTORING_QUICK_REFERENCE.md) for quick answers
2. Review the relevant phase document for details
3. Ask the team

## 📝 Document Status

- ✅ All planning documents complete
- ✅ All implementation guides complete
- ✅ Testing strategy complete
- ✅ Checklist complete
- ⏳ Implementation pending
