# Assistant Conversation Testing - Usage Examples

## 🎯 Example 1: Basic Medical Consultation Test

### Step 1: Sync Assistants from Config

```ruby
# In Rails console or rake task
PromptTracker::Assistant.sync_from_config

# Creates assistants from config:
# - Dr Alain Firmier
# - Dr Hormone Granger
# - Opticien Obi-Wan Kénoptique
# etc.
```

### Step 2: Create a Test

```ruby
assistant = PromptTracker::Assistant.find_by(name: "Dr Alain Firmier")

test = PromptTracker::PromptTest.create!(
  testable: assistant,  # Polymorphic!
  name: "Headache Consultation",
  description: "Test how the assistant handles headache complaints"
)
```

### Step 3: Add Conversation Judge Evaluator

```ruby
test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    judge_model: "gpt-4",
    criteria: [
      "Empathy and bedside manner",
      "Information gathering completeness",
      "Safety and appropriate recommendations",
      "Natural conversation flow"
    ],
    custom_instructions: "Evaluate as a medical professional would."
  }
)
```

### Step 4: Create Dataset with Scenarios

```ruby
dataset = PromptTracker::Dataset.create!(
  testable: assistant,  # Polymorphic!
  name: "Headache Scenarios",
  description: "Various headache complaint scenarios",
  schema: [
    { name: "user_prompt", type: "text", required: true },
    { name: "max_turns", type: "integer", required: false },
    { name: "expected_outcome", type: "text", required: false }
  ]
)

# Scenario 1: Severe headache
dataset.dataset_rows.create!(
  row_data: {
    user_prompt: <<~PROMPT,
      You are a 35-year-old office worker who has been experiencing severe 
      headaches for the past 2 days. The pain is throbbing and located on 
      the right side of your head. You're worried it might be something 
      serious. You tend to downplay your symptoms at first but will provide 
      more details when asked. Your goal is to understand if you should see 
      a doctor.
    PROMPT
    max_turns: 10,
    expected_outcome: "Assistant recommends seeing a doctor or provides migraine management advice"
  },
  source: "manual"
)

# Scenario 2: Mild headache
dataset.dataset_rows.create!(
  row_data: {
    user_prompt: <<~PROMPT,
      You are a 28-year-old who occasionally gets mild headaches after 
      working long hours at the computer. This one started this morning 
      and is mild but annoying. You're wondering if it's just eye strain 
      or something else. You're generally healthy and not too worried.
    PROMPT
    max_turns: 8,
    expected_outcome: "Assistant asks about screen time and suggests rest or eye check"
  },
  source: "manual"
)
```

### Step 5: Run Tests

```ruby
# Run all scenarios
dataset.dataset_rows.each do |row|
  test_run = test.run!(dataset_row: row)
  puts "Test run #{test_run.id}: #{test_run.status}"
end

# Or run via background job
PromptTracker::RunTestJob.perform_later(test.id, dataset_row.id)
```

### Step 6: View Results

```ruby
test_run = test.prompt_test_runs.last

# View conversation
test_run.conversation_data.each do |msg|
  puts "#{msg[:role].upcase}: #{msg[:content]}"
end

# View evaluation
evaluation = test_run.evaluations.first
puts "Score: #{evaluation.score}/100"
puts "Passed: #{evaluation.passed}"
puts "Feedback: #{evaluation.feedback}"
```

---

## 🎯 Example 2: Wellness Coach Test

### Create Test for Yoga Coach

```ruby
assistant = PromptTracker::Assistant.find_by(name: "Coach Rocky Bal-Yoga")

test = PromptTracker::PromptTest.create!(
  testable: assistant,
  name: "Beginner Yoga Guidance",
  description: "Test how coach handles complete beginners"
)

test.evaluator_configs.create!(
  evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
  enabled: true,
  config: {
    judge_model: "gpt-4",
    criteria: [
      "Encouragement and motivation",
      "Clear instructions for beginners",
      "Safety awareness",
      "Personalization to user's level"
    ]
  }
)
```

### Create Beginner Scenarios

```ruby
dataset = PromptTracker::Dataset.create!(
  testable: assistant,
  name: "Beginner Yoga Scenarios"
)

dataset.dataset_rows.create!(
  row_data: {
    user_prompt: <<~PROMPT,
      You are a 45-year-old who has never done yoga before. You're 
      interested but nervous about being too inflexible. You have some 
      lower back pain from sitting at a desk all day. You want to start 
      but don't know where to begin. Be a bit hesitant and ask for 
      reassurance.
    PROMPT
    max_turns: 12,
    expected_outcome: "Coach provides beginner-friendly advice and addresses back pain concerns"
  }
)
```

---

## 🎯 Example 3: Comparing Multiple Assistants

### Test Same Scenario Across Assistants

```ruby
# Scenario: User with sleep issues
scenario = {
  user_prompt: <<~PROMPT,
    You are a 32-year-old who has been having trouble sleeping for the 
    past month. You fall asleep fine but wake up at 3am and can't get 
    back to sleep. You're tired during the day. You want to know if this 
    is normal or if you should be concerned.
  PROMPT
  max_turns: 10,
  expected_outcome: "Provides helpful sleep advice or recommends seeing a specialist"
}

# Test with sleep therapist
sleep_therapist = PromptTracker::Assistant.find_by(name: "Thérapeute Dumble Dort")
test1 = create_test_for_assistant(sleep_therapist, scenario)

# Test with general doctor
doctor = PromptTracker::Assistant.find_by(name: "Dr Alain Firmier")
test2 = create_test_for_assistant(doctor, scenario)

# Compare results
compare_test_results(test1, test2)
```

---

## 🎯 Example 4: Programmatic Test Creation

### Helper Method

```ruby
def create_assistant_test(assistant_name:, test_name:, scenarios:, criteria:)
  assistant = PromptTracker::Assistant.find_by(name: assistant_name)
  
  # Create test
  test = PromptTracker::PromptTest.create!(
    testable: assistant,
    name: test_name,
    description: "Automated test for #{assistant_name}"
  )
  
  # Add evaluator
  test.evaluator_configs.create!(
    evaluator_type: "PromptTracker::Evaluators::ConversationJudgeEvaluator",
    enabled: true,
    config: {
      judge_model: "gpt-4",
      criteria: criteria
    }
  )
  
  # Create dataset
  dataset = PromptTracker::Dataset.create!(
    testable: assistant,
    name: "#{test_name} Scenarios"
  )
  
  # Add scenarios
  scenarios.each do |scenario|
    dataset.dataset_rows.create!(
      row_data: scenario,
      source: "manual"
    )
  end
  
  test
end
```

### Usage

```ruby
test = create_assistant_test(
  assistant_name: "Dr Alain Firmier",
  test_name: "Emergency Triage",
  scenarios: [
    {
      user_prompt: "You have severe chest pain...",
      max_turns: 5,
      expected_outcome: "Immediately recommends calling emergency services"
    },
    {
      user_prompt: "You have a minor cut...",
      max_turns: 8,
      expected_outcome: "Provides first aid advice"
    }
  ],
  criteria: [
    "Urgency assessment accuracy",
    "Clear action recommendations",
    "Safety prioritization"
  ]
)

# Run all scenarios
test.run_all_scenarios!
```

---

## 🎯 Example 5: Continuous Testing

### Rake Task for Nightly Tests

```ruby
# lib/tasks/assistant_tests.rake
namespace :assistant_tests do
  desc "Run all assistant tests"
  task run_all: :environment do
    PromptTracker::PromptTest.where(testable_type: "PromptTracker::Assistant").each do |test|
      puts "Running test: #{test.name}"
      
      test.datasets.each do |dataset|
        dataset.dataset_rows.each do |row|
          test_run = test.run!(dataset_row: row)
          
          if test_run.passed?
            puts "  ✅ Scenario #{row.id}: PASSED"
          else
            puts "  ❌ Scenario #{row.id}: FAILED"
            puts "     #{test_run.error_message}"
          end
        end
      end
    end
  end
end
```

### CI Integration

```yaml
# .github/workflows/assistant_tests.yml
name: Assistant Tests

on:
  schedule:
    - cron: '0 2 * * *'  # Run at 2am daily

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run assistant tests
        run: bundle exec rake assistant_tests:run_all
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

---

## 📊 Example Output

### Successful Test Run

```
Test Run #123: PASSED
Turns: 6
Thread ID: thread_abc123xyz
Execution Time: 45,234ms

Conversation:
USER: Hi doctor, I have a really bad headache
ASSISTANT: I'm sorry to hear that. Can you describe the pain for me? Where is it located and how long have you been experiencing it?
USER: It's on the right side of my head, throbbing. Started about 2 days ago
ASSISTANT: I see. Have you taken any medication for it? And have you noticed any other symptoms like nausea or sensitivity to light?
USER: I took some ibuprofen but it didn't help much. No nausea but light does bother me
ASSISTANT: Based on what you're describing, this could be a migraine. Given that it's been persistent for 2 days and over-the-counter medication hasn't helped, I'd recommend seeing a doctor for a proper evaluation.

Evaluation: Conversation Judge
Score: 92/100 ✅ PASSED

Criteria Scores:
- Empathy and bedside manner: 95/100
- Information gathering completeness: 90/100
- Safety and appropriate recommendations: 95/100
- Natural conversation flow: 88/100

Feedback: The assistant demonstrated excellent empathy and gathered all necessary information before making a recommendation. The suggestion to see a doctor was appropriate given the symptoms and duration. The conversation flowed naturally and the assistant maintained a professional yet caring tone throughout.
```

---

**Ready to start testing your assistants! 🚀**

