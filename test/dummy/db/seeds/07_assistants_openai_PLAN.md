# OpenAI Assistants Seed Data Plan

## File: `07_assistants_openai.rb`

### Purpose
Create comprehensive seed data for OpenAI Assistants feature, demonstrating:
- Multi-turn conversation testing
- ConversationJudgeEvaluator usage
- Dataset creation for assistants
- Different assistant use cases

### Structure (~200 lines)

```ruby
# frozen_string_literal: true

puts "  Creating OpenAI assistants..."

# ============================================================================
# 1. Medical Triage Assistant
# ============================================================================

medical_assistant = PromptTracker::Openai::Assistant.create!(...)
medical_dataset = PromptTracker::Dataset.create!(...)
medical_dataset.dataset_rows.create!([...])
medical_test = PromptTracker::Test.create!(...)
medical_test.evaluator_configs.create!(...)

# ============================================================================
# 2. Customer Support Assistant
# ============================================================================

support_assistant = PromptTracker::Openai::Assistant.create!(...)
support_dataset = PromptTracker::Dataset.create!(...)
support_dataset.dataset_rows.create!([...])
support_test = PromptTracker::Test.create!(...)
support_test.evaluator_configs.create!(...)

# ============================================================================
# 3. Technical Support Assistant
# ============================================================================

tech_assistant = PromptTracker::Openai::Assistant.create!(...)
tech_dataset = PromptTracker::Dataset.create!(...)
tech_dataset.dataset_rows.create!([...])
tech_test = PromptTracker::Test.create!(...)
tech_test.evaluator_configs.create!(...)
```

## Detailed Content

### 1. Medical Triage Assistant

**Assistant Configuration:**
- **Name**: `medical_triage_assistant`
- **Description**: "Helps triage patient symptoms and recommend next steps"
- **Assistant ID**: `asst_medical_triage_001` (mock ID for demo)
- **Instructions**: Multi-paragraph medical triage instructions
- **Model**: `gpt-4o`
- **Tools**: None (pure conversation)
- **Tags**: `["healthcare", "triage", "high-priority"]`

**Dataset: "Common Symptoms"**
- 5 rows covering different medical scenarios:
  1. Headache + light sensitivity (migraine scenario)
  2. Fever for 2 days (infection scenario)
  3. Chest pain (urgent care scenario)
  4. Persistent cough (respiratory scenario)
  5. Abdominal pain (digestive scenario)

**Row Data Structure:**
```ruby
{
  user_prompt: "I have a severe headache and sensitivity to light",
  max_turns: 3,
  expected_topics: ["migraine", "medical attention", "symptoms"],
  notes: "Should ask about duration, severity, other symptoms"
}
```

**Test: "Symptom Triage Quality"**
- **Evaluator**: ConversationJudgeEvaluator
- **Judge Model**: `gpt-4o`
- **Evaluation Prompt**: "Evaluate this medical triage response for: 1) Empathy and bedside manner, 2) Asking appropriate follow-up questions, 3) Providing clear next steps, 4) Avoiding medical advice beyond triage scope"
- **Threshold**: 75/100

### 2. Customer Support Assistant

**Assistant Configuration:**
- **Name**: `customer_support_assistant`
- **Description**: "Handles customer inquiries and resolves common issues"
- **Assistant ID**: `asst_support_001`
- **Instructions**: Customer support best practices
- **Model**: `gpt-4o-mini`
- **Tools**: None
- **Tags**: `["customer-service", "support", "production"]`

**Dataset: "Common Support Issues"**
- 5 rows covering different support scenarios:
  1. Password reset request
  2. Billing question
  3. Feature request
  4. Bug report
  5. Account cancellation

**Row Data Structure:**
```ruby
{
  user_prompt: "I can't log into my account",
  max_turns: 4,
  expected_resolution: "password_reset",
  customer_sentiment: "frustrated",
  notes: "Should verify identity, offer reset link, provide alternatives"
}
```

**Test: "Support Quality & Resolution"**
- **Evaluator**: ConversationJudgeEvaluator
- **Judge Model**: `gpt-4o-mini`
- **Evaluation Prompt**: "Evaluate this support conversation for: 1) Professionalism and empathy, 2) Problem-solving approach, 3) Clear communication, 4) Timely resolution"
- **Threshold**: 70/100

### 3. Technical Support Assistant

**Assistant Configuration:**
- **Name**: `technical_support_assistant`
- **Description**: "Provides technical troubleshooting for software issues"
- **Assistant ID**: `asst_tech_support_001`
- **Instructions**: Technical troubleshooting methodology
- **Model**: `gpt-4o`
- **Tools**: `[{ type: "code_interpreter" }]` (for analyzing logs)
- **Tags**: `["technical", "engineering", "troubleshooting"]`

**Dataset: "Technical Issues"**
- 5 rows covering different technical scenarios:
  1. API integration error
  2. Performance issue
  3. Database connection problem
  4. Deployment failure
  5. Authentication error

**Row Data Structure:**
```ruby
{
  user_prompt: "Our API is returning 500 errors intermittently",
  max_turns: 5,
  issue_type: "api_error",
  severity: "high",
  error_logs: "Sample error stack trace...",
  notes: "Should ask about frequency, recent changes, error patterns"
}
```

**Test: "Technical Troubleshooting Quality"**
- **Evaluator**: ConversationJudgeEvaluator
- **Judge Model**: `gpt-4o`
- **Evaluation Prompt**: "Evaluate this technical support conversation for: 1) Systematic troubleshooting approach, 2) Asking relevant diagnostic questions, 3) Technical accuracy, 4) Clear explanations for non-technical users"
- **Threshold**: 80/100

## Key Features Demonstrated

### 1. **Polymorphic Testable**
- Assistants use same Test/Dataset models as PromptVersions
- Shows flexibility of polymorphic design

### 2. **ConversationJudgeEvaluator**
- Different evaluation criteria for different domains
- Customizable threshold scores
- Different judge models (gpt-4o vs gpt-4o-mini)

### 3. **Rich Dataset Metadata**
- `user_prompt`: Initial message
- `max_turns`: Conversation length limit
- `expected_topics`: What should be discussed
- `notes`: Testing guidance
- Domain-specific fields (severity, error_logs, etc.)

### 4. **Real-World Use Cases**
- Healthcare (regulated, high-stakes)
- Customer Support (high-volume, empathy-focused)
- Technical Support (complex, diagnostic)

### 5. **Different Configurations**
- Different models (gpt-4o vs gpt-4o-mini)
- Different tools (code_interpreter for tech support)
- Different thresholds (70-80 based on domain)

## Benefits for Demo/Testing

1. **Immediate Value**: Users can see working assistants without setup
2. **Best Practices**: Shows recommended configurations
3. **Variety**: Different domains demonstrate flexibility
4. **Realistic**: Based on actual use cases
5. **Testable**: Can run tests immediately with mock mode

## Integration with Existing Seeds

- **After**: Prompts and basic tests (01-06)
- **Before**: LLM responses and evaluations (08-09)
- **Parallel**: Similar structure to prompt seeds
- **Consistent**: Uses same patterns and conventions

## File Size Estimate

- Medical Assistant: ~60 lines
- Customer Support Assistant: ~60 lines
- Technical Support Assistant: ~60 lines
- Comments and formatting: ~20 lines
- **Total**: ~200 lines ✅ (within reasonable size)

