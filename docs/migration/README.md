# model_config Provider/API Split Migration

## Overview

This directory contains the complete migration plan to fix the `model_config` storage format in PromptTracker.

## The Problem

Currently, `model_config` stores provider and API as a compound value:

```json
{
  "provider": "openai_responses",
  "model": "gpt-4o",
  "temperature": 0.7
}
```

This causes three major issues:

1. **UI Bug**: Playground form expects separate `provider` and `api` fields, causing cascading dropdowns to fail
2. **Display Issues**: Show pages display "openai_responses" instead of "OpenAI - Response API"
3. **Data Model Inconsistency**: Configuration defines providers with nested APIs, but storage uses compound keys

## The Solution

Split into separate fields:

```json
{
  "provider": "openai",
  "api": "response_api",
  "model": "gpt-4o",
  "temperature": 0.7
}
```

## Documents in This Directory

### 1. **QUICK_START.md** - Start Here!
Quick overview of the problem and solution. Read this first to understand the issue.

### 2. **model_config_provider_api_split.md** - Complete Plan
Detailed implementation plan with:
- Root cause analysis
- Impact analysis
- Step-by-step implementation guide
- Code examples for each change
- Testing strategy
- Rollback plan

### 3. **CHECKLIST.md** - Execution Tracker
Interactive checklist to track progress during migration. Use this while implementing.

### 4. **README.md** - This File
Overview and navigation guide.

## Visual Diagrams

Three Mermaid diagrams are embedded in the plan document:

1. **Data Flow Diagram**: Shows current vs. target data flow
2. **Migration Timeline**: Gantt chart of all phases
3. **Architecture Diagram**: Before/after architecture comparison

## Quick Navigation

**Just want to understand the problem?**
→ Read `QUICK_START.md`

**Ready to implement?**
→ Read `model_config_provider_api_split.md` then use `CHECKLIST.md`

**Need to see the big picture?**
→ View the Mermaid diagrams in the plan document

**Looking for specific code changes?**
→ See "Detailed Implementation Plan" section in main plan

## Migration Phases

### Phase 1: Backward Compatible Readers (2-3 hours)
Make all code that reads `model_config` support BOTH old and new formats.

**Files**: PromptVersion model, ApplicationHelper, show page view

### Phase 2: New Format Writers (1-2 hours)
Update all code that creates/updates `model_config` to use new format.

**Files**: PlaygroundExecuteService, factories, seeds

### Phase 3: Data Migration (30 minutes)
Convert all existing database records to new format.

**Tool**: Rake task `rails prompt_tracker:migrate_model_config`

### Phase 4: Cleanup (1 hour, optional)
Remove backward compatibility code after confirming migration success.

## Key Files to Change

### Models
- `app/models/prompt_tracker/prompt_version.rb`

### Services
- `app/services/prompt_tracker/playground_execute_service.rb`

### Helpers
- `app/helpers/prompt_tracker/application_helper.rb`

### Views
- `app/views/prompt_tracker/testing/prompt_versions/show.html.erb`

### Tests
- `spec/factories/prompt_tracker/llm_responses.rb`
- `spec/factories/prompt_tracker/prompt_versions.rb`

### Seeds
- `test/dummy/db/seeds/04c_prompts_with_tools.rb`

### Tasks
- `lib/tasks/prompt_tracker/migrate_model_config.rake` (new file)

## Success Criteria

Migration is successful when:

1. ✅ All PromptVersion records have separate `provider` and `api` fields
2. ✅ Show pages display "OpenAI - Response API" instead of "openai_responses"
3. ✅ Playground cascading dropdowns work correctly
4. ✅ Tools display as "Web Search, File Search" instead of arrays
5. ✅ All tests pass
6. ✅ No compound provider values exist in database

## Estimated Effort

- **Phase 1**: 2-3 hours
- **Phase 2**: 1-2 hours
- **Phase 3**: 30 minutes
- **Phase 4**: 1 hour (optional)

**Total**: ~5-7 hours

## Questions?

See the "Questions & Answers" section in `model_config_provider_api_split.md`.

## Getting Started

1. Read `QUICK_START.md`
2. Read `model_config_provider_api_split.md`
3. Create a new git branch
4. Open `CHECKLIST.md` and start checking off items
5. Test thoroughly after each phase
6. Deploy and run migration
7. Verify success criteria

Good luck! 🚀

