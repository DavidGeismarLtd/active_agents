# PromptTracker Seed Data

## Overview

This directory contains modular seed files for the PromptTracker dummy application. The seed data demonstrates all features of PromptTracker including prompts, tests, evaluators, assistants, and A/B tests.

## Quick Start

```bash
cd test/dummy
bin/rails db:reset  # Drop, create, migrate, and seed
```

Or just seed:
```bash
cd test/dummy
bin/rails db:seed
```

## File Structure

Seed files are loaded in numerical order:

| File | Purpose | Size | Status |
|------|---------|------|--------|
| `01_cleanup.rb` | Delete all existing data | ~30 lines | ⬜ To create |
| `02_prompts_customer_support.rb` | Customer support greeting prompt | ~120 lines | ⬜ To create |
| `03_prompts_email_generation.rb` | Email summary prompt | ~60 lines | ⬜ To create |
| `04_prompts_code_review.rb` | Code review assistant prompt | ~60 lines | ⬜ To create |
| `05_tests_basic.rb` | Basic tests with single evaluators | ~120 lines | ⬜ To create |
| `06_tests_advanced.rb` | Advanced multi-evaluator tests | ~300 lines | ⬜ To create |
| `07_assistants_openai.rb` | **NEW** OpenAI Assistants | ~200 lines | ⬜ To create |
| `08_llm_responses.rb` | Sample tracked LLM calls | ~120 lines | ⬜ To create |
| `09_evaluations.rb` | Sample evaluations | ~80 lines | ⬜ To create |
| `10_ab_tests.rb` | A/B test examples | ~160 lines | ⬜ To create |
| `99_summary.rb` | Print summary statistics | ~50 lines | ⬜ To create |

**Total**: ~1,300 lines (split across 11 files)

## What Gets Created

### Prompts (3 prompts, 8 versions)
- **Customer Support Greeting**: 5 versions (deprecated, deprecated, active, draft, draft)
- **Email Summary**: 2 versions (active, draft)
- **Code Review Assistant**: 1 version (active)

### OpenAI Assistants (3 assistants) ⭐ NEW
- **Medical Triage Assistant**: Healthcare symptom triage
- **Customer Support Assistant**: General customer inquiries
- **Technical Support Assistant**: Software troubleshooting

### Tests (~15 tests)
- Basic tests with single evaluators
- Advanced tests with multiple evaluators (3-4 evaluators each)
- Assistant tests with ConversationJudgeEvaluator

### Datasets
- Prompt datasets with template variables
- Assistant datasets with conversation scenarios

### Evaluators
- PatternMatchEvaluator
- LengthEvaluator
- KeywordEvaluator
- LlmJudgeEvaluator
- ExactMatchEvaluator
- FormatEvaluator
- **ConversationJudgeEvaluator** ⭐ NEW

### Sample Data
- ~12 LLM responses (tracked calls)
- ~20 evaluations
- 3 A/B tests (draft, running, completed)

## Seed Data Highlights

### 1. Customer Support Greeting
Demonstrates version evolution:
- v1: Too formal → deprecated
- v2: Too casual → deprecated
- v3: **Active** - balanced tone
- v4: Draft - very casual (testing)
- v5: Draft - empathetic (testing)

### 2. Advanced Tests
Shows complex evaluation scenarios:
- **Comprehensive Quality Check**: 3 evaluators (length + keyword + LLM judge)
- **Email Format Validation**: Complex regex patterns
- **Code Review Quality**: LLM judge + keyword validation
- **Technical Patterns**: 10 regex patterns + 4 evaluators

### 3. OpenAI Assistants ⭐ NEW
Demonstrates multi-turn conversation testing:
- **Medical Triage**: 5 symptom scenarios, empathy-focused evaluation
- **Customer Support**: 5 support issues, resolution-focused evaluation
- **Technical Support**: 5 technical issues, diagnostic-focused evaluation

### 4. A/B Tests
Shows different test states:
- **Draft**: Greeting tone comparison (not started)
- **Running**: Email format comparison (in progress)
- **Completed**: Email format comparison (with results)

## Customization

### Disable a Seed File
Rename the file to add `.disabled`:
```bash
mv 08_llm_responses.rb 08_llm_responses.rb.disabled
```

### Run Individual Seed File
```bash
cd test/dummy
bin/rails runner "load 'db/seeds/02_prompts_customer_support.rb'"
```

### Add New Seed File
1. Create file with number prefix (e.g., `11_my_new_seeds.rb`)
2. Follow existing patterns
3. Run `bin/rails db:seed` to test

## Development Workflow

### After Schema Changes
```bash
cd test/dummy
bin/rails db:reset  # Recreate database with new schema
```

### Testing Seed Changes
```bash
cd test/dummy
bin/rails db:seed:replant  # Drop all data and re-seed
```

### Debugging Seeds
Add `binding.pry` or `puts` statements in seed files:
```ruby
puts "DEBUG: Creating assistant #{medical_assistant.name}"
binding.pry  # Pause execution
```

## Best Practices

1. **Keep files focused**: Each file should have one clear purpose
2. **Use descriptive names**: File names should explain what they create
3. **Add comments**: Explain why data is structured a certain way
4. **Be idempotent**: Seeds should work when run multiple times
5. **Use realistic data**: Helps with testing and demos
6. **Follow conventions**: Match existing patterns for consistency

## Related Documentation

- [PLAN.md](./PLAN.md) - Detailed refactoring plan
- [07_assistants_openai_PLAN.md](./07_assistants_openai_PLAN.md) - OpenAI Assistants seed plan
- Main README: `../../README.md`

## Questions?

See the plan files for detailed information about each seed file's structure and content.

