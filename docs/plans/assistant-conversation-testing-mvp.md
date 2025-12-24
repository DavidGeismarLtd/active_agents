# Assistant Conversation Testing - MVP Plan

## 🎯 Vision

Enable testing of OpenAI Assistants through **LLM-simulated conversations** with **per-message scoring** for granular feedback.

**Key Innovations:**
1. **LLM User Simulator**: Generates realistic conversation turns based on scenario description
2. **Per-Message Scoring**: Judge scores each assistant message individually (0-100) with reasons
3. **Unified Testable Index**: Single view for all testables (Prompts + Assistants)
4. **Creation Wizard**: Guided flow for creating new testables
5. **Auto-sync from OpenAI**: Fetch assistant details automatically

## 📋 MVP Scope

### What's IN Scope ✅
- **Unified testable index** at `/testing` (Prompts + Assistants together)
- **Creation wizard modal** for selecting testable type
- Create `Assistant` model (synced from config + **auto-fetched from OpenAI API**)
- Make tests polymorphic (testable: PromptVersion OR Assistant)
- **Rename PromptTest → Test** (polymorphic model)
- **Rename PromptTestRun → TestRun** (polymorphic model)
- Dataset rows contain `user_prompt` + `max_turns` (NO row-level eval config)
- User simulator service (generates conversation turns)
- **Per-message conversation judge** (scores each assistant message individually)
- **Global configuration** for judge model (in initializer)
- **Multiple tests per assistant** (different evaluators for different aspects)
- Basic UI to create assistant tests and view conversation results
- Test results showing conversation with **inline message scores**

### What's OUT of Scope ❌
- Thread reuse across test runs (always create new thread)
- Deterministic/seeded conversations (always stochastic)
- Pre-built user personas (manual per-row definition only)
- Real-time conversation preview in dataset creation
- Assistant CRUD UI (sync from config only, no manual creation)
- Tool call handling (raise error if assistant requires action)
- Playground integration (assistants are test-only for MVP)
- **Row-level evaluation config** (global config only)
- **Criteria scores** (per-message scores only)
- Tool call handling (will raise error if assistant requires_action)

## 🏗️ Architecture Overview

### Core Concept: Polymorphic Testable

```ruby
# Current (Prompt-only)
PromptTest belongs_to :prompt_version

# MVP (Polymorphic)
Test belongs_to :testable, polymorphic: true
# testable can be: PromptVersion OR Assistant
```

### Test Execution Flow

```
1. Test.run!(dataset_row)
   ↓
2. Delegate to testable.run_test(test, dataset_row)
   ↓
3a. PromptVersion.run_test          3b. Assistant.run_test
    - Render prompt with variables       - Create thread
    - Call LLM once                      - Start user simulator
    - Return single response             - Loop: simulator → assistant → simulator
                                         - Return full conversation
   ↓                                     ↓
4. Run evaluators                    4. Run conversation judge
   - Pattern match, length, etc.        - LLM evaluates entire conversation
   ↓                                     ↓
5. Create TestRun with results       5. Create TestRun with conversation
```

## 📊 Database Schema Changes

### New Table: `assistants`

```ruby
create_table :prompt_tracker_assistants do |t|
  t.string :assistant_id, null: false  # e.g., "asst_abc123"
  t.string :name, null: false          # e.g., "Dr Alain Firmier"
  t.string :provider, null: false      # e.g., "openai_assistants"
  t.text :description
  t.string :category                   # e.g., "Medical", "Wellness"
  t.jsonb :metadata, default: {}       # Store assistant config
  t.timestamps
end

add_index :prompt_tracker_assistants, :assistant_id, unique: true
add_index :prompt_tracker_assistants, :provider
```

### Modify Table: `prompt_tests` → `tests`

**Option A: Rename existing table (RECOMMENDED)**
```ruby
rename_table :prompt_tracker_prompt_tests, :prompt_tracker_tests
add_reference :prompt_tracker_tests, :testable, polymorphic: true
# Backfill: set testable_type = 'PromptTracker::PromptVersion', testable_id = prompt_version_id
remove_column :prompt_tracker_tests, :prompt_version_id
```

**Option B: Keep both tables (safer for MVP)**
```ruby
# Keep prompt_tests as-is
# Create new tests table for polymorphic tests
# Migrate later
```

### Modify Table: `prompt_test_runs` → `test_runs`

```ruby
rename_table :prompt_tracker_prompt_test_runs, :prompt_tracker_test_runs
# Add column to store conversation data
add_column :prompt_tracker_test_runs, :conversation_data, :jsonb, default: []

# conversation_data structure for assistants:
# [
#   { role: "user", content: "I have a headache" },
#   { role: "assistant", content: "Can you describe it?" },
#   ...
# ]
```

### Dataset Schema for Assistants

No schema changes needed! Dataset rows already support flexible JSONB:

```ruby
# For PromptVersion tests (existing)
dataset_row.row_data = {
  name: "Alice",
  issue: "billing problem"
}

# For Assistant tests (new) - ONLY test scenario data
dataset_row.row_data = {
  user_prompt: "You are a patient with a severe headache that started 2 days ago. You're worried it might be serious.",
  max_turns: 10
  # ONLY scenario data - NO evaluation_prompt, NO evaluation_config
  # Evaluation config is in Test → EvaluatorConfig (since we have multiple tests per assistant)
}
```

### Global Configuration (Initializer)

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # Existing config...

  # NEW: Conversation testing configuration
  config.conversation_judge_model = "gpt-4"  # Model for ConversationJudgeEvaluator
  config.user_simulator_model = "gpt-3.5-turbo"  # Model for UserSimulatorService
end
```

## 🔧 Implementation Plan

### Phase 0: Unified Testable Index & Creation Wizard (3-4 hours)

**NEW REQUIREMENT: Unified testable index at `/testing` root**

**Files to create:**
- `app/controllers/prompt_tracker/testing/testables_controller.rb`
- `app/views/prompt_tracker/testing/testables/index.html.erb`
- `app/views/prompt_tracker/testing/testables/_creation_wizard_modal.html.erb`
- `app/javascript/controllers/testable_creation_controller.js` (Stimulus)

**Responsibilities:**
1. **Unified Index**: Show all testables (PromptVersions + Assistants) in one view
2. **Creation Wizard**: Modal to select testable type
   - If "Prompt" → Redirect to `/testing/playground`
   - If "Assistant" → Show assistant selector → Redirect to `/testing/assistants/:id`

**Index View Structure:**
```erb
<h1>Testing</h1>

<button data-action="click->testable-creation#openModal">
  Create New Testable
</button>

<table>
  <thead>
    <tr>
      <th>Type</th>
      <th>Name</th>
      <th>Tests</th>
      <th>Pass Rate</th>
      <th>Last Run</th>
    </tr>
  </thead>
  <tbody>
    <% @prompt_versions.each do |pv| %>
      <tr>
        <td><span class="badge">Prompt</span></td>
        <td><%= link_to pv.name, testing_prompt_path(pv.prompt) %></td>
        <td><%= pv.tests.count %></td>
        <td><%= pv.pass_rate %>%</td>
        <td><%= time_ago_in_words(pv.last_test_run&.created_at) %></td>
      </tr>
    <% end %>

    <% @assistants.each do |assistant| %>
      <tr>
        <td><span class="badge">Assistant</span></td>
        <td><%= link_to assistant.name, testing_assistant_path(assistant) %></td>
        <td><%= assistant.tests.count %></td>
        <td><%= assistant.pass_rate %>%</td>
        <td><%= time_ago_in_words(assistant.last_test_run&.created_at) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Creation Wizard Modal:**
```erb
<div class="modal" data-testable-creation-target="modal">
  <h2>What do you want to test?</h2>

  <div class="testable-type-cards">
    <div class="card" data-action="click->testable-creation#selectPrompt">
      <h3>Prompt</h3>
      <p>Test single LLM responses with variable inputs</p>
    </div>

    <div class="card" data-action="click->testable-creation#selectAssistant">
      <h3>Assistant</h3>
      <p>Test multi-turn conversations with LLM-simulated users</p>
    </div>
  </div>

  <!-- Step 2: Assistant selector (shown if Assistant selected) -->
  <div data-testable-creation-target="assistantSelector" class="hidden">
    <h3>Select an Assistant</h3>
    <select data-testable-creation-target="assistantSelect">
      <% @assistants.each do |assistant| %>
        <option value="<%= assistant.id %>"><%= assistant.name %></option>
      <% end %>
    </select>
    <button data-action="click->testable-creation#goToAssistant">Continue</button>
  </div>
</div>
```

**Routes:**
```ruby
# config/routes.rb
namespace :testing do
  root to: "testables#index"  # NEW: Unified index

  resources :assistants, only: [:index, :show] do
    member do
      post :sync  # Sync from OpenAI API
    end
  end

  # Existing routes...
end
```

### Phase 1: Core Models (2-3 hours)

**Files to create:**
- `app/models/prompt_tracker/assistant.rb`
- `db/migrate/XXX_create_assistants.rb`
- `db/migrate/XXX_add_polymorphic_testable_to_tests.rb`
- `db/migrate/XXX_add_conversation_data_to_test_runs.rb`

**Files to modify:**
- `app/models/prompt_tracker/prompt_test.rb` → Add polymorphic support
- `app/models/prompt_tracker/prompt_test_run.rb` → Add conversation_data handling

**Key decisions:**
- ✅ Use polymorphic `testable` association
- ✅ Store conversation in `conversation_data` JSONB column
- ✅ Keep backward compatibility with existing prompt tests

### Phase 2: User Simulator Service (2-3 hours)

**Files to create:**
- `app/services/prompt_tracker/user_simulator_service.rb`
- `spec/services/prompt_tracker/user_simulator_service_spec.rb`

**Responsibilities:**
```ruby
UserSimulatorService.new(
  persona_prompt: "You are a patient with a headache...",
  max_turns: 10
).generate_message(conversation_history: [...])
# => "Hi doctor, I have a really bad headache"
# OR nil if conversation should end
```

**Key features:**
- Uses fixed model: `gpt-3.5-turbo` (cheaper for simulation)
- Temperature: `0.8` (natural variation)
- Detects `CONVERSATION_COMPLETE` token to end conversation
- Flips roles in conversation history (user ↔ assistant)

### Phase 3: Assistant Test Runner (3-4 hours)

**Files to create:**
- `app/services/prompt_tracker/assistant_test_runner.rb`
- `spec/services/prompt_tracker/assistant_test_runner_spec.rb`

**Responsibilities:**
```ruby
AssistantTestRunner.new(assistant, dataset_row).run!
# => TestRun with conversation_data populated
```

**Flow:**
1. Create thread via `OpenaiAssistantService`
2. Initialize `UserSimulatorService` with `dataset_row[:user_prompt]`
3. Loop up to `max_turns`:
   - Simulator generates user message
   - Send to assistant via `OpenaiAssistantService`
   - Collect response
   - Add both to conversation array
   - Check if simulator wants to end
4. Return conversation data

**Key features:**
- Reuses existing `OpenaiAssistantService`
- Stores thread_id in metadata
- Handles timeouts gracefully
- Raises error if assistant requires action (tool calls)

### Phase 4: Conversation Judge Evaluator (3-4 hours) - PER-MESSAGE SCORING

**Files to create:**
- `app/services/prompt_tracker/evaluators/conversation_judge_evaluator.rb`
- `app/views/prompt_tracker/evaluators/forms/_conversation_judge.html.erb`
- `app/views/prompt_tracker/evaluators/templates/_conversation_judge.html.erb`
- `spec/services/prompt_tracker/evaluators/conversation_judge_evaluator_spec.rb`

**SIMPLIFIED Config schema (NO criteria):**
```ruby
{
  evaluation_prompt: "Evaluate each assistant message for quality, empathy, and accuracy. Score each message from 0-100.",
  judge_model: nil  # Uses global config.conversation_judge_model
}
```

**NEW: Per-Message Evaluation Logic:**
1. Format conversation with message indices
2. Build judge prompt requesting per-message scores
3. Call LLM judge (uses global config.conversation_judge_model)
4. Parse JSON response with message_scores array
5. Calculate overall score = average of message scores
6. Return result with message-level feedback

**Output format:**
```ruby
{
  overall_score: 88,  # Average of message scores
  message_scores: [
    { message_index: 0, role: "assistant", score: 90, reason: "Good empathetic opening" },
    { message_index: 2, role: "assistant", score: 85, reason: "Asked relevant questions" },
    { message_index: 4, role: "assistant", score: 90, reason: "Appropriate recommendation" }
  ],
  overall_feedback: "The assistant handled the conversation well..."
}
```

**Register in EvaluatorRegistry:**
```ruby
EvaluatorRegistry.register(
  key: :conversation_judge,
  name: "Conversation Judge (Per-Message)",
  description: "Scores each assistant message individually using LLM",
  evaluator_class: ConversationJudgeEvaluator,
  icon: "chat-dots",
  default_config: {
    judge_model: "gpt-4",
    criteria: []
  }
)
```

### Phase 5: Test Interface (Polymorphic) (3-4 hours)

**Files to modify:**
- `app/models/prompt_tracker/prompt_test.rb` → Support polymorphic testable
- `app/services/prompt_tracker/prompt_test_runner.rb` → Delegate to testable

**New pattern:**
```ruby
class PromptTest
  belongs_to :testable, polymorphic: true  # Was: belongs_to :prompt_version

  def run!(dataset_row:)
    # Delegate to testable
    testable.run_test(test: self, dataset_row: dataset_row)
  end
end

class PromptVersion
  has_many :tests, as: :testable

  def run_test(test:, dataset_row:)
    # Existing single-shot test logic
    PromptTestRunner.new(test, self, dataset_row).run!
  end
end

class Assistant
  has_many :tests, as: :testable

  def run_test(test:, dataset_row:)
    # New conversation test logic
    AssistantTestRunner.new(self, dataset_row).run!
  end
end
```

### Phase 6: Basic UI (4-5 hours)

**Files to create:**
- `app/views/prompt_tracker/testing/assistants/index.html.erb` (list assistants)
- `app/views/prompt_tracker/testing/assistants/show.html.erb` (assistant details + tests)
- `app/views/prompt_tracker/testing/assistant_tests/new.html.erb` (create test)
- `app/views/prompt_tracker/testing/assistant_tests/_conversation_result.html.erb` (show conversation)

**Files to modify:**
- `app/controllers/prompt_tracker/testing/tests_controller.rb` → Support polymorphic testable
- `app/views/prompt_tracker/testing/prompt_tests/show.html.erb` → Detect conversation vs single response

**UI Features:**
1. **Assistant List** (`/testing/assistants`)
   - Show all assistants from config
   - Link to create test

2. **Create Assistant Test** (`/testing/assistants/:id/tests/new`)
   - Test name, description
   - Select dataset (or create new)
   - Add conversation judge evaluator

3. **Dataset Row Form** (for assistants)
   - `user_prompt` textarea (large, with help text: "Describe the user persona and scenario")
   - `max_turns` number input (default: 10)
   - NO evaluation fields (evaluation config is in Test → EvaluatorConfig)

4. **Test Results** (`/testing/tests/:id/runs/:run_id`)
   - Show conversation as chat bubbles
   - Show judge evaluation with criteria scores
   - Show metadata (turns, thread_id, execution time)

### Phase 7: Integration & Testing (2-3 hours)

**Tasks:**
- Write integration specs for full flow
- Test with real OpenAI assistant
- Handle edge cases (timeout, errors, tool calls)
- Update documentation

## 📝 Detailed File Specifications

### 1. Assistant Model (WITH OPENAI API FETCHING)

```ruby
# app/models/prompt_tracker/assistant.rb
module PromptTracker
  class Assistant < ApplicationRecord
    # Associations
    has_many :tests, as: :testable, class_name: "PromptTracker::Test"
    has_many :test_runs, through: :tests, source: :test_runs
    has_many :datasets, as: :testable, class_name: "PromptTracker::Dataset"

    # Validations
    validates :assistant_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :provider, presence: true

    # Callbacks
    after_create :create_default_test
    after_create :fetch_from_openai  # NEW: Auto-fetch on creation

    # Run a test with this assistant
    def run_test(test:, dataset_row:)
      AssistantTestRunner.new(self, dataset_row, test: test).run!
    end

    # NEW: Fetch assistant details from OpenAI API
    def fetch_from_openai!
      return unless provider == "openai_assistants"

      client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      response = client.assistants.retrieve(id: assistant_id)

      update!(
        name: response['name'],
        description: response['description'],
        metadata: {
          instructions: response['instructions'],
          model: response['model'],
          tools: response['tools'],
          file_ids: response['file_ids'],
          openai_metadata: response['metadata'],
          last_synced_at: Time.current
        }
      )
    rescue => e
      Rails.logger.error "Failed to fetch assistant #{assistant_id}: #{e.message}"
      # Don't raise - allow assistant to exist with config data only
    end

    # Get assistant from config by ID
    def self.from_config(assistant_id)
      config = PromptTracker.configuration.available_models
      assistants = config[:openai_assistants] || []

      assistant_config = assistants.find { |a| a[:id] == assistant_id }
      return nil unless assistant_config

      find_or_create_by!(assistant_id: assistant_id) do |a|
        a.name = assistant_config[:name]
        a.provider = "openai_assistants"
        a.category = assistant_config[:category]
        a.metadata = assistant_config
      end
    end

    # Sync all assistants from config
    def self.sync_from_config
      config = PromptTracker.configuration.available_models
      assistants = config[:openai_assistants] || []

      assistants.map do |assistant_config|
        from_config(assistant_config[:id])
      end
    end
  end
end
```

### 2. User Simulator Service

```ruby
# app/services/prompt_tracker/user_simulator_service.rb
module PromptTracker
  class UserSimulatorService
    SIMULATOR_MODEL = "gpt-3.5-turbo"
    SIMULATOR_TEMPERATURE = 0.8
    COMPLETION_TOKEN = "CONVERSATION_COMPLETE"

    attr_reader :persona_prompt, :max_turns

    def initialize(persona_prompt:, max_turns: 10)
      @persona_prompt = persona_prompt
      @max_turns = max_turns
    end

    # Generate next user message based on conversation history
    # Returns nil if conversation should end
    def generate_message(conversation_history:)
      system_prompt = build_system_prompt
      messages = build_messages(system_prompt, conversation_history)

      response = LlmClientService.call(
        provider: "openai",
        model: SIMULATOR_MODEL,
        messages: messages,
        temperature: SIMULATOR_TEMPERATURE
      )

      text = response[:text].strip

      # Check if simulator wants to end conversation
      return nil if text.include?(COMPLETION_TOKEN)

      text
    end

    private

    def build_system_prompt
      <<~PROMPT
        #{persona_prompt}

        Instructions:
        - You are simulating a real user in a conversation
        - Respond naturally as this person would
        - Keep responses concise (1-3 sentences)
        - Don't reveal you're an AI
        - If the conversation has reached a natural conclusion, respond with exactly: "#{COMPLETION_TOKEN}"
        - Otherwise, continue the conversation naturally
      PROMPT
    end

    def build_messages(system_prompt, conversation_history)
      messages = [{ role: "system", content: system_prompt }]

      # Flip roles: what was "user" becomes "assistant" (simulator's output)
      # what was "assistant" becomes "user" (input to simulator)
      conversation_history.each do |msg|
        flipped_role = msg[:role] == "user" ? "assistant" : "user"
        messages << { role: flipped_role, content: msg[:content] }
      end

      messages
    end
  end
end
```

### 3. Assistant Test Runner Service

```ruby
# app/services/prompt_tracker/assistant_test_runner.rb
module PromptTracker
  class AssistantTestRunner
    attr_reader :assistant, :dataset_row, :test

    def initialize(assistant, dataset_row, test:)
      @assistant = assistant
      @dataset_row = dataset_row
      @test = test
    end

    def run!
      start_time = Time.current

      # Create test run record
      test_run = create_test_run

      begin
        # Run the conversation
        conversation = execute_conversation

        # Update test run with conversation
        test_run.update!(
          conversation_data: conversation,
          status: "running",
          execution_time_ms: ((Time.current - start_time) * 1000).to_i,
          metadata: test_run.metadata.merge(
            thread_id: @thread_id,
            turns: conversation.length / 2
          )
        )

        # Run evaluators
        run_evaluators(test_run, conversation)

        test_run.reload
      rescue => e
        test_run.update!(
          status: "error",
          error_message: e.message,
          execution_time_ms: ((Time.current - start_time) * 1000).to_i
        )
        raise
      end
    end

    private

    def create_test_run
      test.prompt_test_runs.create!(
        prompt_version: nil, # Not applicable for assistants
        dataset_row: dataset_row,
        status: "pending",
        metadata: {
          assistant_id: assistant.assistant_id,
          user_prompt: dataset_row.row_data["user_prompt"]
        }
      )
    end

    def execute_conversation
      conversation = []
      max_turns = dataset_row.row_data["max_turns"] || 10
      user_prompt = dataset_row.row_data["user_prompt"]

      # Initialize user simulator
      simulator = UserSimulatorService.new(
        persona_prompt: user_prompt,
        max_turns: max_turns
      )

      # Create thread (store for metadata)
      @thread_id = create_thread

      # Conversation loop
      max_turns.times do
        # Generate user message
        user_message = simulator.generate_message(conversation_history: conversation)
        break if user_message.nil? # Simulator ended conversation

        conversation << { role: "user", content: user_message }

        # Send to assistant
        assistant_response = call_assistant(user_message)
        conversation << { role: "assistant", content: assistant_response }
      end

      conversation
    end

    def create_thread
      # Use OpenaiAssistantService to create thread
      response = OpenaiAssistantService.call(
        assistant_id: assistant.assistant_id,
        prompt: "init", # Dummy message to create thread
        timeout: 60
      )

      # Extract thread_id from response metadata
      response[:raw]&.dig("thread_id") || response[:thread_id]
    end

    def call_assistant(message)
      response = OpenaiAssistantService.call(
        assistant_id: assistant.assistant_id,
        prompt: message,
        thread_id: @thread_id,
        timeout: 60
      )

      response[:text]
    end

    def run_evaluators(test_run, conversation)
      # Get evaluator configs for this test
      evaluator_configs = test.evaluator_configs.enabled

      return if evaluator_configs.empty?

      # For conversation tests, we pass the conversation to evaluators
      # Conversation judge evaluator will handle it specially
      evaluations = []

      evaluator_configs.each do |config|
        evaluator = config.build_evaluator_for_conversation(conversation, test_run)
        evaluation = evaluator.evaluate
        evaluations << evaluation
      end

      # Update test run with results
      passed = evaluations.all? { |e| e.passed }

      test_run.update!(
        status: passed ? "passed" : "failed",
        passed: passed,
        passed_evaluators: evaluations.count(&:passed),
        failed_evaluators: evaluations.count { |e| !e.passed },
        total_evaluators: evaluations.count
      )
    end
  end
end
```

### 4. Conversation Judge Evaluator

```ruby
# app/services/prompt_tracker/evaluators/conversation_judge_evaluator.rb
module PromptTracker
  module Evaluators
    class ConversationJudgeEvaluator < BaseEvaluator
      # Override initialize to accept conversation instead of llm_response
      def initialize(conversation:, test_run:, config: {})
        @conversation = conversation
        @test_run = test_run
        @config = config.symbolize_keys
      end

      def evaluate_score
        judge_response = call_judge
        parse_score(judge_response)
      end

      def generate_feedback
        judge_response = call_judge
        parse_feedback(judge_response)
      end

      def metadata
        {
          config: @config,
          conversation_turns: @conversation.length / 2,
          judge_model: judge_model,
          criteria: criteria
        }
      end

      private

      def call_judge
        @judge_response ||= begin
          prompt = build_judge_prompt

          response = LlmClientService.call(
            provider: "openai",
            model: judge_model,
            prompt: prompt,
            temperature: 0.3 # Lower temp for consistent evaluation
          )

          response[:text]
        end
      end

      def build_judge_prompt
        <<~PROMPT
          Evaluate this conversation between a user and an AI assistant.

          CONVERSATION:
          #{format_conversation}

          #{expected_outcome_section}

          EVALUATION CRITERIA:
          #{format_criteria}

          Please evaluate the conversation and provide:
          1. An overall score from 0-100
          2. Individual scores for each criterion (0-100)
          3. Specific feedback explaining your evaluation

          Respond in JSON format:
          {
            "overall_score": 85,
            "criteria_scores": {
              "criterion_1": 90,
              "criterion_2": 80
            },
            "feedback": "The assistant showed excellent...",
            "passed": true
          }
        PROMPT
      end

      def format_conversation
        @conversation.map do |msg|
          role = msg[:role].upcase
          content = msg[:content]
          "#{role}: #{content}"
        end.join("\n\n")
      end

      def expected_outcome_section
        outcome = @test_run.dataset_row&.row_data&.dig("expected_outcome")
        return "" if outcome.blank?

        <<~SECTION
          EXPECTED OUTCOME:
          #{outcome}
        SECTION
      end

      def format_criteria
        return "- Overall conversation quality" if criteria.empty?

        criteria.map { |c| "- #{c}" }.join("\n")
      end

      def parse_score(response)
        json = JSON.parse(response)
        json["overall_score"] || 0
      rescue JSON::ParserError
        50 # Default score if parsing fails
      end

      def parse_feedback(response)
        json = JSON.parse(response)
        json["feedback"] || "Evaluation completed"
      rescue JSON::ParserError
        "Unable to parse judge response"
      end

      def judge_model
        @config[:judge_model] || "gpt-4"
      end

      def criteria
        @config[:criteria] || []
      end
    end
  end
end
```

### 5. Migration Files

```ruby
# db/migrate/XXX_create_assistants.rb
class CreateAssistants < ActiveRecord::Migration[7.2]
  def change
    create_table :prompt_tracker_assistants do |t|
      t.string :assistant_id, null: false
      t.string :name, null: false
      t.string :provider, null: false, default: "openai_assistants"
      t.text :description
      t.string :category
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :prompt_tracker_assistants, :assistant_id, unique: true
    add_index :prompt_tracker_assistants, :provider
    add_index :prompt_tracker_assistants, :category
  end
end
```

```ruby
# db/migrate/XXX_add_polymorphic_testable_to_tests.rb
class AddPolymorphicTestableToTests < ActiveRecord::Migration[7.2]
  def change
    # Add polymorphic columns
    add_reference :prompt_tracker_prompt_tests, :testable, polymorphic: true, index: true

    # Backfill existing tests to point to prompt_version
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE prompt_tracker_prompt_tests
          SET testable_type = 'PromptTracker::PromptVersion',
              testable_id = prompt_version_id
          WHERE prompt_version_id IS NOT NULL
        SQL
      end
    end

    # Make testable required (after backfill)
    change_column_null :prompt_tracker_prompt_tests, :testable_type, false
    change_column_null :prompt_tracker_prompt_tests, :testable_id, false

    # Keep prompt_version_id for backward compatibility (can remove later)
    # remove_column :prompt_tracker_prompt_tests, :prompt_version_id
  end
end
```

```ruby
# db/migrate/XXX_add_conversation_data_to_test_runs.rb
class AddConversationDataToTestRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :prompt_tracker_prompt_test_runs, :conversation_data, :jsonb, default: [], null: false
    add_index :prompt_tracker_prompt_test_runs, :conversation_data, using: :gin
  end
end
```

## 🎯 MVP Success Criteria

### Must Have ✅
1. ✅ **Unified testable index** at `/testing` (Prompts + Assistants)
2. ✅ **Creation wizard modal** for selecting testable type
3. ✅ Assistant model created and synced from config
4. ✅ **Auto-fetch assistant details from OpenAI API** on show page
5. ✅ Tests can belong to Assistant (polymorphic testable)
6. ✅ **PromptTest renamed to Test** (polymorphic model)
7. ✅ **PromptTestRun renamed to TestRun** (polymorphic model)
8. ✅ User simulator generates natural conversation turns
9. ✅ Assistant test runner executes multi-turn conversations
10. ✅ **Conversation judge scores EACH assistant message individually**
11. ✅ **Overall score = average of message scores**
12. ✅ Test results display conversation with **inline message scores**
13. ✅ Can create dataset rows with user_prompt + max_turns
14. ✅ **Global configuration** for judge model in initializer
15. ✅ **Multiple tests per assistant** (different evaluators for different aspects)

### Nice to Have (Post-MVP) 🔮
- Thread reuse across test runs
- Deterministic/seeded conversations
- Pre-built user personas library
- Real-time conversation preview
- Assistant CRUD UI
- Tool call handling
- Playground integration
- Conversation analytics (avg turns, common patterns)
- **Multiple tests per assistant** (MVP: one test only)
- **Row-level evaluation config** (MVP: global config only)
- **Criteria-based scoring** (MVP: per-message scores only)

## 📊 Estimated Timeline (UPDATED)

| Phase | Hours | Description |
|-------|-------|-------------|
| Phase 0: Unified Index & Wizard | 3-4 | Unified testable index, creation wizard modal |
| Phase 1: Core Models | 2-3 | Assistant model, migrations, polymorphic tests, model renames |
| Phase 2: User Simulator | 2-3 | Service to generate user messages |
| Phase 3: Test Runner | 3-4 | Orchestrate conversation execution |
| Phase 4: Judge Evaluator | 3-4 | **Per-message scoring** LLM evaluation |
| Phase 5: Test Interface | 3-4 | Polymorphic test support |
| Phase 6: UI | 5-6 | Assistant show with OpenAI sync, test creation, **inline message scores** |
| Phase 7: Testing | 3-4 | **Comprehensive test suite** (see below) |
| **TOTAL** | **24-32 hours** | **~4-5 days of focused work** |

## 🚀 Getting Started

### Step 1: Create Assistant Model
```bash
rails g model prompt_tracker/assistant assistant_id:string name:string provider:string description:text category:string metadata:jsonb
```

### Step 2: Add Polymorphic Association
```bash
rails g migration AddPolymorphicTestableToTests testable:references{polymorphic}
```

### Step 3: Add Conversation Data
```bash
rails g migration AddConversationDataToTestRuns conversation_data:jsonb
```

### Step 4: Implement Services
- Create `UserSimulatorService`
- Create `AssistantTestRunner`
- Create `ConversationJudgeEvaluator`

### Step 5: Update Models
- Add `testable` polymorphic association to `PromptTest`
- Add `run_test` method to `PromptVersion` and `Assistant`

### Step 6: Build UI
- Assistant list view
- Test creation form
- Conversation results display

## 📝 Comprehensive Testing Strategy

### 1. Model Tests (RSpec)

**`spec/models/prompt_tracker/assistant_spec.rb`**
```ruby
RSpec.describe PromptTracker::Assistant do
  describe "associations" do
    it { should have_many(:tests).class_name("PromptTracker::Test") }
    it { should have_many(:test_runs).through(:tests) }
    it { should have_many(:datasets).class_name("PromptTracker::Dataset") }
  end

  describe "validations" do
    it { should validate_presence_of(:assistant_id) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:provider) }
    it { should validate_uniqueness_of(:assistant_id) }
  end

  describe "callbacks" do
    it "creates default test after creation" do
      assistant = create(:assistant)
      expect(assistant.tests.count).to eq(1)
      expect(assistant.tests.first.evaluator_configs.first.evaluator_type).to eq("conversation_judge")
    end

    it "fetches from OpenAI API after creation" do
      VCR.use_cassette("openai_assistant_fetch") do
        assistant = create(:assistant, assistant_id: "asst_123")
        expect(assistant.metadata["instructions"]).to be_present
        expect(assistant.metadata["model"]).to be_present
      end
    end
  end

  describe "#fetch_from_openai!" do
    it "updates assistant with OpenAI data" do
      assistant = create(:assistant, assistant_id: "asst_123")

      VCR.use_cassette("openai_assistant_fetch") do
        assistant.fetch_from_openai!
      end

      expect(assistant.metadata["instructions"]).to eq("You are a helpful medical assistant...")
      expect(assistant.metadata["model"]).to eq("gpt-4")
      expect(assistant.metadata["last_synced_at"]).to be_present
    end

    it "handles API errors gracefully" do
      assistant = create(:assistant, assistant_id: "invalid_id")

      expect {
        VCR.use_cassette("openai_assistant_fetch_error") do
          assistant.fetch_from_openai!
        end
      }.not_to raise_error
    end
  end

  describe "#run_test" do
    it "delegates to AssistantTestRunner" do
      assistant = create(:assistant)
      test = create(:test, testable: assistant)
      dataset_row = create(:dataset_row, row_data: { user_prompt: "Test", max_turns: 5 })

      runner = instance_double(PromptTracker::AssistantTestRunner)
      allow(PromptTracker::AssistantTestRunner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run!)

      assistant.run_test(test: test, dataset_row: dataset_row)

      expect(PromptTracker::AssistantTestRunner).to have_received(:new).with(assistant, dataset_row, test: test)
      expect(runner).to have_received(:run!)
    end
  end
end
```

**`spec/models/prompt_tracker/test_spec.rb`** (renamed from prompt_test_spec.rb)
```ruby
RSpec.describe PromptTracker::Test do
  describe "polymorphic testable" do
    it "can belong to PromptVersion" do
      prompt_version = create(:prompt_version)
      test = create(:test, testable: prompt_version)

      expect(test.testable).to eq(prompt_version)
      expect(test.testable_type).to eq("PromptTracker::PromptVersion")
    end

    it "can belong to Assistant" do
      assistant = create(:assistant)
      test = create(:test, testable: assistant)

      expect(test.testable).to eq(assistant)
      expect(test.testable_type).to eq("PromptTracker::Assistant")
    end
  end

  describe "#run!" do
    it "delegates to testable.run_test for PromptVersion" do
      prompt_version = create(:prompt_version)
      test = create(:test, testable: prompt_version)
      dataset_row = create(:dataset_row)

      expect(prompt_version).to receive(:run_test).with(test: test, dataset_row: dataset_row)

      test.run!(dataset_row: dataset_row)
    end

    it "delegates to testable.run_test for Assistant" do
      assistant = create(:assistant)
      test = create(:test, testable: assistant)
      dataset_row = create(:dataset_row)

      expect(assistant).to receive(:run_test).with(test: test, dataset_row: dataset_row)

      test.run!(dataset_row: dataset_row)
    end
  end
end
```

### 2. Service Tests (RSpec)

**`spec/services/prompt_tracker/user_simulator_service_spec.rb`**
```ruby
RSpec.describe PromptTracker::UserSimulatorService do
  let(:service) do
    described_class.new(
      persona_prompt: "You are a patient with a headache",
      max_turns: 10
    )
  end

  describe "#generate_message" do
    it "generates a user message based on persona" do
      VCR.use_cassette("user_simulator_first_message") do
        message = service.generate_message(conversation_history: [])

        expect(message).to be_a(String)
        expect(message).to include("headache")
      end
    end

    it "generates contextual responses based on conversation history" do
      conversation_history = [
        { role: "user", content: "I have a headache" },
        { role: "assistant", content: "How long have you had it?" }
      ]

      VCR.use_cassette("user_simulator_contextual") do
        message = service.generate_message(conversation_history: conversation_history)

        expect(message).to be_a(String)
        expect(message.downcase).to match(/day|hour|week/)
      end
    end

    it "returns nil when conversation should end" do
      VCR.use_cassette("user_simulator_complete") do
        message = service.generate_message(
          conversation_history: [],
          force_complete: true
        )

        expect(message).to be_nil
      end
    end

    it "uses gpt-3.5-turbo model" do
      expect_any_instance_of(OpenAI::Client).to receive(:chat).with(
        hash_including(model: "gpt-3.5-turbo")
      )

      VCR.use_cassette("user_simulator_model_check") do
        service.generate_message(conversation_history: [])
      end
    end

    it "flips roles in conversation history" do
      # User simulator sees assistant messages as user messages and vice versa
      conversation_history = [
        { role: "user", content: "I have a headache" },
        { role: "assistant", content: "How long?" }
      ]

      expected_flipped = [
        { role: "assistant", content: "I have a headache" },
        { role: "user", content: "How long?" }
      ]

      expect_any_instance_of(OpenAI::Client).to receive(:chat).with(
        hash_including(messages: array_including(expected_flipped))
      )

      service.generate_message(conversation_history: conversation_history)
    end
  end
end
```

**`spec/services/prompt_tracker/assistant_test_runner_spec.rb`**
```ruby
RSpec.describe PromptTracker::AssistantTestRunner do
  let(:assistant) { create(:assistant, assistant_id: "asst_123") }
  let(:test) { create(:test, testable: assistant) }
  let(:dataset_row) do
    create(:dataset_row, row_data: {
      user_prompt: "You are a patient with a headache",
      max_turns: 3
    })
  end
  let(:runner) { described_class.new(assistant, dataset_row, test: test) }

  describe "#run!" do
    it "creates a test run with conversation data" do
      VCR.use_cassette("assistant_test_run_full") do
        test_run = runner.run!

        expect(test_run).to be_persisted
        expect(test_run.conversation_data).to be_an(Array)
        expect(test_run.conversation_data.length).to be > 0
        expect(test_run.status).to eq("completed")
      end
    end

    it "executes conversation up to max_turns" do
      VCR.use_cassette("assistant_test_run_max_turns") do
        test_run = runner.run!

        # Should have at most 3 user messages + 3 assistant messages = 6 total
        expect(test_run.conversation_data.length).to be <= 6
      end
    end

    it "stores thread_id in metadata" do
      VCR.use_cassette("assistant_test_run_thread") do
        test_run = runner.run!

        expect(test_run.metadata["thread_id"]).to be_present
      end
    end

    it "handles simulator ending conversation early" do
      allow_any_instance_of(PromptTracker::UserSimulatorService)
        .to receive(:generate_message).and_return(nil)

      VCR.use_cassette("assistant_test_run_early_end") do
        test_run = runner.run!

        expect(test_run.conversation_data.length).to be < 6
      end
    end

    it "raises error if assistant requires action (tool calls)" do
      VCR.use_cassette("assistant_test_run_tool_call") do
        expect {
          runner.run!
        }.to raise_error(/requires_action/)
      end
    end
  end
end
```

**`spec/services/prompt_tracker/evaluators/conversation_judge_evaluator_spec.rb`**
```ruby
RSpec.describe PromptTracker::Evaluators::ConversationJudgeEvaluator do
  let(:test_run) do
    create(:test_run, conversation_data: [
      { role: "user", content: "I have a headache" },
      { role: "assistant", content: "I'm sorry to hear that. How long have you had it?" },
      { role: "user", content: "About 2 days" },
      { role: "assistant", content: "Have you taken any medication?" },
      { role: "user", content: "Just ibuprofen" },
      { role: "assistant", content: "I recommend seeing a doctor if it persists." }
    ])
  end

  let(:config) do
    {
      evaluation_prompt: "Evaluate each assistant message for quality and empathy.",
      judge_model: nil  # Uses global config
    }
  end

  let(:evaluator) { described_class.new(test_run: test_run, config: config) }

  describe "#evaluate" do
    it "returns per-message scores for assistant messages only" do
      VCR.use_cassette("conversation_judge_evaluate") do
        result = evaluator.evaluate

        expect(result[:message_scores]).to be_an(Array)
        expect(result[:message_scores].length).to eq(3)  # 3 assistant messages

        result[:message_scores].each do |score|
          expect(score[:role]).to eq("assistant")
          expect(score[:score]).to be_between(0, 100)
          expect(score[:reason]).to be_present
          expect(score[:message_index]).to be_an(Integer)
        end
      end
    end

    it "calculates overall score as average of message scores" do
      VCR.use_cassette("conversation_judge_evaluate") do
        result = evaluator.evaluate

        message_scores = result[:message_scores].map { |s| s[:score] }
        expected_avg = message_scores.sum / message_scores.length

        expect(result[:overall_score]).to eq(expected_avg)
      end
    end

    it "includes overall feedback" do
      VCR.use_cassette("conversation_judge_evaluate") do
        result = evaluator.evaluate

        expect(result[:overall_feedback]).to be_present
        expect(result[:overall_feedback]).to be_a(String)
      end
    end

    it "uses global conversation_judge_model config" do
      allow(PromptTracker.configuration).to receive(:conversation_judge_model).and_return("gpt-4")

      expect_any_instance_of(OpenAI::Client).to receive(:chat).with(
        hash_including(model: "gpt-4")
      )

      VCR.use_cassette("conversation_judge_model_config") do
        evaluator.evaluate
      end
    end

    it "handles empty conversations gracefully" do
      empty_test_run = create(:test_run, conversation_data: [])
      empty_evaluator = described_class.new(test_run: empty_test_run, config: config)

      result = empty_evaluator.evaluate

      expect(result[:message_scores]).to eq([])
      expect(result[:overall_score]).to eq(0)
    end
  end

  describe "#evaluate_score" do
    it "returns the overall score" do
      VCR.use_cassette("conversation_judge_evaluate") do
        score = evaluator.evaluate_score

        expect(score).to be_between(0, 100)
      end
    end
  end

  describe "#generate_feedback" do
    it "returns the overall feedback" do
      VCR.use_cassette("conversation_judge_evaluate") do
        feedback = evaluator.generate_feedback

        expect(feedback).to be_a(String)
        expect(feedback.length).to be > 20
      end
    end
  end
end
```

### 3. Controller Tests (RSpec)

**`spec/controllers/prompt_tracker/testing/testables_controller_spec.rb`**
```ruby
RSpec.describe PromptTracker::Testing::TestablesController do
  describe "GET #index" do
    it "shows both prompts and assistants" do
      prompt_version = create(:prompt_version)
      assistant = create(:assistant)

      get :index

      expect(assigns(:prompt_versions)).to include(prompt_version)
      expect(assigns(:assistants)).to include(assistant)
      expect(response).to render_template(:index)
    end

    it "calculates pass rates for each testable" do
      assistant = create(:assistant)
      test = create(:test, testable: assistant)
      create(:test_run, test: test, passed: true)
      create(:test_run, test: test, passed: false)

      get :index

      expect(assigns(:assistants).first.pass_rate).to eq(50)
    end
  end
end
```

**`spec/controllers/prompt_tracker/testing/assistants_controller_spec.rb`**
```ruby
RSpec.describe PromptTracker::Testing::AssistantsController do
  describe "GET #show" do
    it "fetches assistant details from OpenAI API" do
      assistant = create(:assistant, assistant_id: "asst_123")

      expect(assistant).to receive(:fetch_from_openai!)

      VCR.use_cassette("assistant_show_fetch") do
        get :show, params: { id: assistant.id }
      end

      expect(response).to be_successful
    end

    it "displays assistant metadata" do
      assistant = create(:assistant, metadata: {
        instructions: "You are a helpful assistant",
        model: "gpt-4"
      })

      get :show, params: { id: assistant.id }

      expect(response.body).to include("You are a helpful assistant")
      expect(response.body).to include("gpt-4")
    end
  end

  describe "POST #sync" do
    it "manually syncs assistant from OpenAI" do
      assistant = create(:assistant, assistant_id: "asst_123")

      VCR.use_cassette("assistant_manual_sync") do
        post :sync, params: { id: assistant.id }
      end

      expect(response).to redirect_to(testing_assistant_path(assistant))
      expect(flash[:notice]).to include("synced")
    end
  end
end
```

### 4. Integration Tests (RSpec System/Feature Tests)

**`spec/system/assistant_conversation_testing_spec.rb`**
```ruby
RSpec.describe "Assistant Conversation Testing", type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  scenario "User creates and runs an assistant test end-to-end" do
    # Setup
    assistant = create(:assistant, assistant_id: "asst_123", name: "Dr. Alain")

    # Visit unified testable index
    visit prompt_tracker.testing_root_path

    expect(page).to have_content("Testing")
    expect(page).to have_content("Dr. Alain")
    expect(page).to have_content("Assistant")

    # Click on assistant
    click_link "Dr. Alain"

    # Should auto-fetch from OpenAI
    expect(page).to have_content("Instructions")
    expect(page).to have_content("Model")

    # Create dataset
    click_button "Create Dataset"
    fill_in "Name", with: "Headache Scenarios"
    click_button "Save"

    # Add dataset row
    click_button "Add Scenario"
    fill_in "User Prompt", with: "You are a patient with a severe headache that started 2 days ago"
    fill_in "Max Turns", with: "5"
    click_button "Save Scenario"

    # Run test
    VCR.use_cassette("assistant_full_integration_test") do
      click_button "Run Test"

      # Wait for test to complete
      expect(page).to have_content("Test completed", wait: 30)

      # View results
      expect(page).to have_content("Conversation")
      expect(page).to have_css(".message.user", minimum: 1)
      expect(page).to have_css(".message.assistant", minimum: 1)

      # Check per-message scores
      expect(page).to have_content("Score:")
      expect(page).to have_content("/100")

      # Check overall score
      expect(page).to have_content("Overall Score")
      expect(page).to have_css(".overall-score")
    end
  end

  scenario "User uses creation wizard to create assistant" do
    create(:assistant, name: "Dr. Alain")

    visit prompt_tracker.testing_root_path

    # Open creation wizard
    click_button "Create New Testable"

    # Modal should appear
    expect(page).to have_content("What do you want to test?")
    expect(page).to have_content("Prompt")
    expect(page).to have_content("Assistant")

    # Select Assistant
    click_on "Assistant"

    # Should show assistant selector
    expect(page).to have_select("assistant_select")
    select "Dr. Alain", from: "assistant_select"

    click_button "Continue"

    # Should redirect to assistant show page
    expect(current_path).to match(/\/testing\/assistants\/\d+/)
    expect(page).to have_content("Dr. Alain")
  end
end
```

### 5. Factory Definitions

**`spec/factories/prompt_tracker/assistants.rb`**
```ruby
FactoryBot.define do
  factory :assistant, class: "PromptTracker::Assistant" do
    sequence(:assistant_id) { |n| "asst_test_#{n}" }
    sequence(:name) { |n| "Test Assistant #{n}" }
    provider { "openai_assistants" }
    description { "A test assistant" }
    category { "medical" }
    metadata do
      {
        instructions: "You are a helpful medical assistant",
        model: "gpt-4",
        tools: [],
        file_ids: []
      }
    end

    # Skip callbacks for faster tests
    trait :skip_callbacks do
      after(:build) do |assistant|
        assistant.class.skip_callback(:create, :after, :create_default_test)
        assistant.class.skip_callback(:create, :after, :fetch_from_openai)
      end

      after(:create) do |assistant|
        assistant.class.set_callback(:create, :after, :create_default_test)
        assistant.class.set_callback(:create, :after, :fetch_from_openai)
      end
    end
  end
end
```

**`spec/factories/prompt_tracker/tests.rb`** (renamed from prompt_tests.rb)
```ruby
FactoryBot.define do
  factory :test, class: "PromptTracker::Test" do
    association :testable, factory: :prompt_version
    name { "Test" }
    description { "A test" }
    enabled { true }

    trait :for_assistant do
      association :testable, factory: :assistant
    end

    trait :with_conversation_judge do
      after(:create) do |test|
        create(:evaluator_config,
          configurable: test,
          evaluator_type: "conversation_judge",
          config: {
            evaluation_prompt: "Evaluate the conversation quality",
            judge_model: nil
          }
        )
      end
    end
  end
end
```

**`spec/factories/prompt_tracker/test_runs.rb`** (renamed from prompt_test_runs.rb)
```ruby
FactoryBot.define do
  factory :test_run, class: "PromptTracker::TestRun" do
    association :test
    status { "completed" }
    passed { true }
    execution_time_ms { 1500 }
    conversation_data { [] }

    trait :with_conversation do
      conversation_data do
        [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
          { role: "user", content: "How are you?" },
          { role: "assistant", content: "I'm doing well, thanks!" }
        ]
      end
    end

    trait :with_evaluations do
      after(:create) do |test_run|
        create(:evaluation,
          test_run: test_run,
          evaluator_type: "conversation_judge",
          score: 85,
          passed: true,
          feedback: "Good conversation quality",
          metadata: {
            message_scores: [
              { message_index: 1, role: "assistant", score: 90, reason: "Friendly greeting" },
              { message_index: 3, role: "assistant", score: 80, reason: "Appropriate response" }
            ]
          }
        )
      end
    end
  end
end
```

### 6. VCR Cassettes

All API calls should be recorded with VCR for deterministic tests:

**`spec/support/vcr.rb`**
```ruby
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ASSISTANT_ID>') { |interaction|
    interaction.request.uri.match(/assistants\/(asst_[^\/]+)/)[1] rescue nil
  }
end
```

### 7. Test Coverage Goals

- **Models**: 100% coverage (all validations, associations, methods)
- **Services**: 95%+ coverage (all business logic paths)
- **Controllers**: 90%+ coverage (all actions and edge cases)
- **Integration**: All critical user flows covered

### 8. Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/models/prompt_tracker/assistant_spec.rb
bundle exec rspec spec/services/prompt_tracker/user_simulator_service_spec.rb
bundle exec rspec spec/system/assistant_conversation_testing_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec

# Run with VCR recording (to update cassettes)
VCR_RECORD_MODE=all bundle exec rspec
```
- Polymorphic test execution for both prompts and assistants
- Dataset row creation for assistant scenarios

### Manual Testing
- Create test with real OpenAI assistant
- Verify conversation quality
- Check judge evaluation accuracy

## 🎉 MVP Deliverables

1. **Working Code**
   - All models, services, and evaluators implemented
   - Migrations run successfully
   - Tests passing

2. **Documentation**
   - README section on assistant testing
   - Code comments and examples
   - API documentation

3. **Demo**
   - Video showing full flow
   - Example assistant test with results
   - Conversation judge evaluation

---

**Ready to implement? Let's start with Phase 1! 🚀**
