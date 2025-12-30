# Seed File Refactoring Plan

## Current State
- **File**: `test/dummy/db/seeds.rb`
- **Size**: 909 lines (too large, hard to maintain)
- **Structure**: Monolithic file with 8 sections

## Problem
- Hard to navigate and maintain
- Difficult to add new seed data (e.g., OpenAI Assistants)
- No clear separation of concerns
- Risk of merge conflicts when multiple developers work on seeds

## Solution: Split into Modular Seed Files

### New Directory Structure
```
test/dummy/db/
├── seeds.rb                          # Main orchestrator (50 lines)
└── seeds/
    ├── PLAN.md                       # This file
    ├── 01_cleanup.rb                 # Delete all existing data
    ├── 02_prompts_customer_support.rb
    ├── 03_prompts_email_generation.rb
    ├── 04_prompts_code_review.rb
    ├── 05_tests_basic.rb             # Basic tests for prompts
    ├── 06_tests_advanced.rb          # Advanced multi-evaluator tests
    ├── 07_assistants_openai.rb       # NEW: OpenAI Assistants
    ├── 08_llm_responses.rb           # Sample tracked calls
    ├── 09_evaluations.rb             # Sample evaluations
    ├── 10_ab_tests.rb                # A/B test examples
    └── 99_summary.rb                 # Print summary statistics
```

## File Breakdown

### `seeds.rb` (Main Orchestrator)
**Purpose**: Load all seed files in order
**Size**: ~50 lines
**Content**:
```ruby
puts "🌱 Seeding PromptTracker database..."

# Load seed files in order
seed_files = Dir[Rails.root.join("db/seeds/*.rb")].sort
seed_files.each do |file|
  puts "\n📄 Loading #{File.basename(file)}..."
  load file
end

puts "\n✅ All seed files loaded!"
```

### `01_cleanup.rb`
**Purpose**: Delete all existing data in correct order
**Size**: ~30 lines
**Content**: Current lines 9-20 (cleanup section)

### `02_prompts_customer_support.rb`
**Purpose**: Customer support greeting prompt with 5 versions
**Size**: ~120 lines
**Content**: Current lines 22-98 (Section 1)
**Includes**:
- 1 prompt: `customer_support_greeting`
- 5 versions (v1-v5: deprecated, deprecated, active, draft, draft)

### `03_prompts_email_generation.rb`
**Purpose**: Email summary prompt with 2 versions
**Size**: ~60 lines
**Content**: Current lines 100-134 (Section 2)
**Includes**:
- 1 prompt: `email_summary`
- 2 versions (v1: active, v2: draft)

### `04_prompts_code_review.rb`
**Purpose**: Code review assistant prompt
**Size**: ~60 lines
**Content**: Current lines 136-173 (Section 3)
**Includes**:
- 1 prompt: `code_review_assistant`
- 1 version (v1: active)

### `05_tests_basic.rb`
**Purpose**: Basic tests with single evaluators
**Size**: ~120 lines
**Content**: Current lines 175-273 (Section 4)
**Includes**:
- Tests for customer support greeting (technical, account)
- Basic evaluator configs (PatternMatch, Length)

### `06_tests_advanced.rb`
**Purpose**: Advanced tests with multiple evaluators
**Size**: ~300 lines
**Content**: Current lines 274-564 (Advanced Tests section)
**Includes**:
- Comprehensive quality check (3 evaluators)
- Email format validation (complex regex)
- Code review quality (LLM judge + keyword)
- Exact output validation
- Technical patterns (10 regex patterns + 4 evaluators)

### `07_assistants_openai.rb` ⭐ NEW
**Purpose**: OpenAI Assistants with tests and datasets
**Size**: ~200 lines
**Content**: NEW - to be created
**Includes**:
- Medical Triage Assistant
  - Dataset with symptom scenarios
  - Test with ConversationJudgeEvaluator
- Customer Support Assistant
  - Dataset with support scenarios
  - Test with ConversationJudgeEvaluator
- Technical Support Assistant
  - Dataset with technical scenarios
  - Test with ConversationJudgeEvaluator

### `08_llm_responses.rb`
**Purpose**: Sample tracked LLM calls
**Size**: ~120 lines
**Content**: Current lines 566-664 (Section 5 - LLM Responses)
**Includes**:
- 10 successful responses
- 2 failed responses
- Realistic metadata (tokens, cost, timing)

### `09_evaluations.rb`
**Purpose**: Sample evaluations for tracked calls
**Size**: ~80 lines
**Content**: Current lines 666-722 (Section 5 - Evaluations)
**Includes**:
- Evaluations for tracked calls
- Mix of passed/failed evaluations

### `10_ab_tests.rb`
**Purpose**: A/B test examples
**Size**: ~160 lines
**Content**: Current lines 724-866 (Section 6)
**Includes**:
- Draft A/B test
- Running A/B test
- Completed A/B test with results

### `99_summary.rb`
**Purpose**: Print summary statistics
**Size**: ~50 lines
**Content**: Current lines 868-909 (Summary section)
**Includes**:
- Count of all created records
- Statistics (cost, response time)
- Tips for exploring the data

## Benefits

### 1. **Maintainability**
- Each file is focused on one domain
- Easy to find and update specific seed data
- Clear separation of concerns

### 2. **Scalability**
- Easy to add new seed files (e.g., more assistants)
- Can disable specific seed files by renaming (add `.disabled`)
- Can run individual seed files for testing

### 3. **Collaboration**
- Reduced merge conflicts
- Multiple developers can work on different seed files
- Clear ownership of seed data

### 4. **Testing**
- Can test individual seed files in isolation
- Faster iteration when working on specific features
- Can load only relevant seeds for specific tests

### 5. **Documentation**
- Each file is self-documenting
- Clear naming convention shows order and purpose
- Easier to understand what data exists

## Implementation Steps

1. ✅ Create `test/dummy/db/seeds/` directory
2. ✅ Create this PLAN.md file
3. ⬜ Create `01_cleanup.rb` (extract cleanup logic)
4. ⬜ Create `02_prompts_customer_support.rb` (extract section 1)
5. ⬜ Create `03_prompts_email_generation.rb` (extract section 2)
6. ⬜ Create `04_prompts_code_review.rb` (extract section 3)
7. ⬜ Create `05_tests_basic.rb` (extract section 4)
8. ⬜ Create `06_tests_advanced.rb` (extract advanced tests)
9. ⬜ Create `07_assistants_openai.rb` ⭐ NEW (create from scratch)
10. ⬜ Create `08_llm_responses.rb` (extract LLM responses)
11. ⬜ Create `09_evaluations.rb` (extract evaluations)
12. ⬜ Create `10_ab_tests.rb` (extract A/B tests)
13. ⬜ Create `99_summary.rb` (extract summary)
14. ⬜ Update `seeds.rb` to load all seed files
15. ⬜ Test: `cd test/dummy && bin/rails db:seed`
16. ⬜ Verify all data is created correctly
17. ⬜ Delete old `seeds.rb` content (keep only orchestrator)

## Naming Convention

- **Prefix with numbers** (01-99) to control load order
- **Use descriptive names** that match the domain
- **Group related seeds** (e.g., all prompts together)
- **Reserve 99** for summary/reporting

## Notes

- Keep `seeds.rb` as the main entry point (Rails convention)
- Use `load` instead of `require` to allow re-running seeds
- Each seed file should be idempotent (can run multiple times)
- Cleanup happens first (01_cleanup.rb) to ensure clean state
- Summary happens last (99_summary.rb) to show final counts

