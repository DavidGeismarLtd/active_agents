# Feature 2: Prompt Test System

## 📋 Overview

A comprehensive test system that allows users to:
- Define test cases for prompts with specific configurations
- Execute tests against LLM providers with different models
- Run evaluators against test results automatically
- Track test results over time
- Compare test results across prompt versions
- Integrate tests into CI/CD pipelines

## 🎯 Goals

1. **Enable regression testing** - Ensure prompt changes don't break existing functionality
2. **Support multiple configurations** - Test with different models, temperatures, etc.
3. **Automate quality checks** - Run evaluators automatically on test results
4. **Track quality over time** - Monitor prompt quality across versions
5. **Enable CI/CD integration** - Run tests in automated pipelines
6. **Support test-driven development** - Write tests before changing prompts

## 🏗️ Architecture

### Core Concepts

#### 1. **PromptTest** (Model)
Represents a single test case for a prompt.

**Attributes:**
- `prompt_id` - The prompt being tested
- `name` - Test case name (e.g., "greeting_with_premium_user")
- `description` - What this test validates
- `template_variables` - Variables to use in the test
- `expected_output` - Optional expected output (for exact matching)
- `expected_patterns` - Regex patterns that should match
- `model_config` - Model, temperature, max_tokens, etc.
- `evaluator_configs` - Which evaluators to run and their thresholds
- `enabled` - Whether this test is active
- `tags` - For organizing tests (e.g., ["smoke", "regression"])

#### 2. **PromptTestRun** (Model)
Represents a single execution of a test.

**Attributes:**
- `prompt_test_id` - The test that was run
- `prompt_version_id` - The version tested
- `llm_response_id` - The LLM response generated
- `status` - passed, failed, error, skipped
- `passed_evaluators` - Count of passing evaluators
- `failed_evaluators` - Count of failing evaluators
- `total_evaluators` - Total evaluators run
- `execution_time_ms` - How long the test took
- `error_message` - If status is error
- `metadata` - Additional context (CI run ID, branch, etc.)

#### 3. **PromptTestSuite** (Model)
Groups related tests together.

**Attributes:**
- `name` - Suite name (e.g., "Customer Support Smoke Tests")
- `description` - What this suite covers
- `prompt_id` - Optional: limit to one prompt
- `tags` - For filtering (e.g., ["smoke", "nightly"])
- `enabled` - Whether this suite is active

**Associations:**
- `has_many :prompt_tests`
- `has_many :prompt_test_suite_runs`

#### 4. **PromptTestSuiteRun** (Model)
Represents execution of an entire test suite.

**Attributes:**
- `prompt_test_suite_id` - The suite that was run
- `status` - passed, failed, error
- `total_tests` - Number of tests in suite
- `passed_tests` - Number that passed
- `failed_tests` - Number that failed
- `skipped_tests` - Number skipped
- `total_duration_ms` - Total execution time
- `triggered_by` - user_id, ci_system, scheduled_job
- `metadata` - CI context, git commit, etc.

## 📊 Database Schema

```ruby
# Migration: create_prompt_tracker_prompt_tests.rb
class CreatePromptTrackerPromptTests < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_prompt_tests do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :prompt_tracker_prompts }
      t.references :prompt_test_suite, foreign_key: { to_table: :prompt_tracker_prompt_test_suites }

      t.string :name, null: false
      t.text :description
      t.jsonb :template_variables, default: {}, null: false
      t.text :expected_output
      t.jsonb :expected_patterns, default: []
      t.jsonb :model_config, default: {}, null: false
      t.jsonb :evaluator_configs, default: [], null: false
      t.boolean :enabled, default: true, null: false
      t.jsonb :tags, default: []

      t.timestamps

      t.index [:prompt_id, :name], unique: true
      t.index :enabled
      t.index :tags, using: :gin
    end

    create_table :prompt_tracker_prompt_test_runs do |t|
      t.references :prompt_test, null: false, foreign_key: { to_table: :prompt_tracker_prompt_tests }
      t.references :prompt_version, null: false, foreign_key: { to_table: :prompt_tracker_prompt_versions }
      t.references :llm_response, foreign_key: { to_table: :prompt_tracker_llm_responses }
      t.references :prompt_test_suite_run, foreign_key: { to_table: :prompt_tracker_prompt_test_suite_runs }

      t.string :status, null: false # passed, failed, error, skipped
      t.integer :passed_evaluators, default: 0
      t.integer :failed_evaluators, default: 0
      t.integer :total_evaluators, default: 0
      t.integer :execution_time_ms
      t.text :error_message
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index :status
      t.index :created_at
    end

    create_table :prompt_tracker_prompt_test_suites do |t|
      t.string :name, null: false
      t.text :description
      t.references :prompt, foreign_key: { to_table: :prompt_tracker_prompts }
      t.jsonb :tags, default: []
      t.boolean :enabled, default: true, null: false

      t.timestamps

      t.index :name, unique: true
      t.index :enabled
    end

    create_table :prompt_tracker_prompt_test_suite_runs do |t|
      t.references :prompt_test_suite, null: false, foreign_key: { to_table: :prompt_tracker_prompt_test_suites }

      t.string :status, null: false # passed, failed, error
      t.integer :total_tests, default: 0
      t.integer :passed_tests, default: 0
      t.integer :failed_tests, default: 0
      t.integer :skipped_tests, default: 0
      t.integer :total_duration_ms
      t.string :triggered_by
      t.jsonb :metadata, default: {}

      t.timestamps

      t.index :status
      t.index :created_at
    end
  end
end
```

## 🔧 Implementation Plan

### Phase 1: Core Models (Week 1)

**Tasks:**
1. Create migrations for all test-related tables
2. Create ActiveRecord models with associations
3. Add validations and scopes
4. Write comprehensive model tests

**Files to Create:**
- `db/migrate/XXXXXX_create_prompt_tracker_test_system.rb`
- `app/models/prompt_tracker/prompt_test.rb`
- `app/models/prompt_tracker/prompt_test_run.rb`
- `app/models/prompt_tracker/prompt_test_suite.rb`
- `app/models/prompt_tracker/prompt_test_suite_run.rb`
- `spec/models/prompt_tracker/prompt_test_spec.rb`
- `spec/models/prompt_tracker/prompt_test_run_spec.rb`
- `spec/models/prompt_tracker/prompt_test_suite_spec.rb`
- `spec/models/prompt_tracker/prompt_test_suite_run_spec.rb`
- `spec/factories/prompt_tracker/prompt_tests.rb`
- `spec/factories/prompt_tracker/prompt_test_runs.rb`

**Model Example:**
```ruby
# app/models/prompt_tracker/prompt_test.rb
module PromptTracker
  class PromptTest < ApplicationRecord
    # Associations
    belongs_to :prompt
    belongs_to :prompt_test_suite, optional: true
    has_many :prompt_test_runs, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :prompt_id }
    validates :template_variables, presence: true
    validates :model_config, presence: true
    validates :status, inclusion: { in: %w[passed failed error skipped] }, allow_nil: true

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :with_tag, ->(tag) { where("tags @> ?", [tag].to_json) }
    scope :for_prompt, ->(prompt) { where(prompt: prompt) }

    # Instance Methods

    # Run this test against a specific prompt version
    def run!(version: nil, metadata: {})
      version ||= prompt.active_version
      raise "No version available" unless version

      PromptTestRunner.new(self, version, metadata).run!
    end

    # Get the latest test run
    def latest_run
      prompt_test_runs.order(created_at: :desc).first
    end

    # Check if the latest run passed
    def passing?
      latest_run&.passed?
    end

    # Get pass rate over last N runs
    def pass_rate(limit: 10)
      runs = prompt_test_runs.order(created_at: :desc).limit(limit)
      return 0 if runs.empty?

      passed = runs.count(&:passed?)
      (passed.to_f / runs.count * 100).round(2)
    end
  end
end
```

### Phase 2: Test Runner Service (Week 1-2)

**Tasks:**
1. Create PromptTestRunner service
2. Implement test execution logic
3. Handle evaluator execution
4. Calculate pass/fail status
5. Write comprehensive tests

**Files to Create:**
- `app/services/prompt_tracker/prompt_test_runner.rb`
- `spec/services/prompt_tracker/prompt_test_runner_spec.rb`

**Service Example:**
```ruby
# app/services/prompt_tracker/prompt_test_runner.rb
module PromptTracker
  class PromptTestRunner
    attr_reader :test, :version, :metadata

    def initialize(test, version, metadata = {})
      @test = test
      @version = version
      @metadata = metadata
      @start_time = nil
      @llm_response = nil
      @test_run = nil
    end

    # Execute the test and return the test run
    def run!
      @start_time = Time.current

      # Create pending test run
      @test_run = create_pending_test_run

      begin
        # Step 1: Execute LLM call
        execute_llm_call

        # Step 2: Run evaluators
        run_evaluators

        # Step 3: Check assertions
        check_assertions

        # Step 4: Calculate final status
        calculate_status

        # Step 5: Update test run
        finalize_test_run

        @test_run
      rescue => e
        handle_error(e)
        @test_run
      end
    end

    private

    def create_pending_test_run
      test.prompt_test_runs.create!(
        prompt_version: version,
        status: 'running',
        metadata: metadata
      )
    end

    def execute_llm_call
      # Use LlmCallService to track the call
      result = LlmCallService.track(
        prompt_name: test.prompt.name,
        version: version.version_number,
        variables: test.template_variables,
        provider: test.model_config['provider'] || 'openai',
        model: test.model_config['model'] || 'gpt-4',
        metadata: { test_id: test.id, test_run_id: @test_run.id }
      ) do |rendered_prompt|
        # Call the actual LLM API
        call_llm_api(rendered_prompt)
      end

      @llm_response = result[:llm_response]
      @test_run.update!(llm_response: @llm_response)
    end

    def call_llm_api(prompt)
      # This would be replaced with actual LLM API calls
      # For now, return a mock response
      {
        text: "Mock LLM response for: #{prompt}",
        tokens: { prompt: 10, completion: 20, total: 30 },
        model: test.model_config['model']
      }
    end

    def run_evaluators
      return if test.evaluator_configs.blank?

      test.evaluator_configs.each do |evaluator_config|
        run_evaluator(evaluator_config)
      end
    end

    def run_evaluator(config)
      evaluator_key = config['evaluator_key'].to_sym
      evaluator_config = config['config'] || {}
      threshold = config['threshold']

      # Build and run the evaluator
      evaluator = EvaluatorRegistry.build(evaluator_key, @llm_response, evaluator_config)
      evaluation = evaluator.evaluate

      # Check if it passed the threshold
      if threshold && evaluation.normalized_score < threshold
        @test_run.failed_evaluators += 1
      else
        @test_run.passed_evaluators += 1
      end

      @test_run.total_evaluators += 1
    end

    def check_assertions
      # Check expected output (exact match)
      if test.expected_output.present?
        unless @llm_response.response_text == test.expected_output
          @test_run.metadata['assertion_failures'] ||= []
          @test_run.metadata['assertion_failures'] << {
            type: 'exact_match',
            expected: test.expected_output,
            actual: @llm_response.response_text
          }
        end
      end

      # Check expected patterns (regex)
      if test.expected_patterns.present?
        test.expected_patterns.each do |pattern|
          regex = Regexp.new(pattern)
          unless @llm_response.response_text.match?(regex)
            @test_run.metadata['assertion_failures'] ||= []
            @test_run.metadata['assertion_failures'] << {
              type: 'pattern_match',
              pattern: pattern,
              actual: @llm_response.response_text
            }
          end
        end
      end
    end

    def calculate_status
      # Failed if any evaluators failed
      if @test_run.failed_evaluators > 0
        @test_run.status = 'failed'
        return
      end

      # Failed if any assertions failed
      if @test_run.metadata['assertion_failures'].present?
        @test_run.status = 'failed'
        return
      end

      # Failed if LLM call failed
      if @llm_response.status != 'success'
        @test_run.status = 'failed'
        @test_run.error_message = @llm_response.error_message
        return
      end

      # Otherwise passed
      @test_run.status = 'passed'
    end

    def finalize_test_run
      execution_time = ((Time.current - @start_time) * 1000).to_i
      @test_run.update!(
        execution_time_ms: execution_time,
        metadata: @test_run.metadata.merge(
          finished_at: Time.current.iso8601
        )
      )
    end

    def handle_error(error)
      @test_run.update!(
        status: 'error',
        error_message: error.message,
        execution_time_ms: ((Time.current - @start_time) * 1000).to_i
      )
    end
  end
end
```

### Phase 3: Test Suite Runner (Week 2)

**Tasks:**
1. Create PromptTestSuiteRunner service
2. Implement parallel test execution
3. Handle suite-level reporting
4. Add progress tracking
5. Write comprehensive tests

**Files to Create:**
- `app/services/prompt_tracker/prompt_test_suite_runner.rb`
- `spec/services/prompt_tracker/prompt_test_suite_runner_spec.rb`

**Service Example:**
```ruby
# app/services/prompt_tracker/prompt_test_suite_runner.rb
module PromptTracker
  class PromptTestSuiteRunner
    attr_reader :suite, :metadata

    def initialize(suite, metadata = {})
      @suite = suite
      @metadata = metadata
      @start_time = nil
      @suite_run = nil
    end

    def run!
      @start_time = Time.current

      # Create suite run record
      @suite_run = create_suite_run

      begin
        # Get all enabled tests
        tests = suite.prompt_tests.enabled

        # Run each test
        tests.each do |test|
          run_test(test)
        end

        # Calculate final status
        calculate_suite_status

        # Finalize
        finalize_suite_run

        @suite_run
      rescue => e
        handle_error(e)
        @suite_run
      end
    end

    private

    def create_suite_run
      suite.prompt_test_suite_runs.create!(
        status: 'running',
        total_tests: suite.prompt_tests.enabled.count,
        triggered_by: metadata[:triggered_by] || 'manual',
        metadata: metadata
      )
    end

    def run_test(test)
      test_run = test.run!(metadata: { suite_run_id: @suite_run.id })

      # Update suite run counts
      case test_run.status
      when 'passed'
        @suite_run.passed_tests += 1
      when 'failed'
        @suite_run.failed_tests += 1
      when 'skipped'
        @suite_run.skipped_tests += 1
      end

      @suite_run.save!
    end

    def calculate_suite_status
      if @suite_run.failed_tests > 0
        @suite_run.status = 'failed'
      elsif @suite_run.passed_tests == @suite_run.total_tests
        @suite_run.status = 'passed'
      else
        @suite_run.status = 'partial'
      end
    end

    def finalize_suite_run
      duration = ((Time.current - @start_time) * 1000).to_i
      @suite_run.update!(
        total_duration_ms: duration,
        metadata: @suite_run.metadata.merge(
          finished_at: Time.current.iso8601
        )
      )
    end

    def handle_error(error)
      @suite_run.update!(
        status: 'error',
        metadata: @suite_run.metadata.merge(
          error: error.message,
          finished_at: Time.current.iso8601
        )
      )
    end
  end
end
```

### Phase 4: Web UI (Week 2-3)

**Tasks:**
1. Create controllers for tests and test runs
2. Create views for managing tests
3. Add test execution UI
4. Create test results dashboard
5. Add test history views

**Files to Create:**
- `app/controllers/prompt_tracker/prompt_tests_controller.rb`
- `app/controllers/prompt_tracker/prompt_test_runs_controller.rb`
- `app/controllers/prompt_tracker/prompt_test_suites_controller.rb`
- `app/views/prompt_tracker/prompt_tests/index.html.erb`
- `app/views/prompt_tracker/prompt_tests/show.html.erb`
- `app/views/prompt_tracker/prompt_tests/new.html.erb`
- `app/views/prompt_tracker/prompt_test_runs/index.html.erb`
- `app/views/prompt_tracker/prompt_test_runs/show.html.erb`
- `spec/controllers/prompt_tracker/prompt_tests_controller_spec.rb`

**Routes:**
```ruby
# config/routes.rb
resources :prompts do
  resources :prompt_tests, path: 'tests' do
    member do
      post :run
    end
  end
end

resources :prompt_test_suites, path: 'test-suites' do
  member do
    post :run
  end
  resources :prompt_test_suite_runs, path: 'runs', only: [:index, :show]
end

resources :prompt_test_runs, path: 'test-runs', only: [:index, :show]
```

### Phase 5: Background Jobs (Week 3)

**Tasks:**
1. Create job for async test execution
2. Create job for scheduled test runs
3. Add retry logic
4. Implement notifications

**Files to Create:**
- `app/jobs/prompt_tracker/prompt_test_job.rb`
- `app/jobs/prompt_tracker/prompt_test_suite_job.rb`
- `spec/jobs/prompt_tracker/prompt_test_job_spec.rb`

**Job Example:**
```ruby
# app/jobs/prompt_tracker/prompt_test_job.rb
module PromptTracker
  class PromptTestJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(test_id, version_id = nil, metadata = {})
      test = PromptTest.find(test_id)
      version = version_id ? PromptVersion.find(version_id) : test.prompt.active_version

      test.run!(version: version, metadata: metadata)
    end
  end
end
```

## 🧪 Testing Strategy

### Unit Tests
- All models with validations, associations, scopes
- PromptTestRunner with various scenarios
- PromptTestSuiteRunner with parallel execution

### Integration Tests
- Full test execution workflow
- Evaluator integration
- Suite execution

### System Tests
- Create test via UI
- Run test and view results
- Run suite and view dashboard

## 📝 User Stories

### Story 1: Create Regression Test
**As a** prompt engineer
**I want to** create a test case for my prompt
**So that** I can ensure future changes don't break existing functionality

**Acceptance Criteria:**
- Can create test with name, description, variables
- Can specify expected output or patterns
- Can configure which evaluators to run
- Can set pass/fail thresholds for evaluators

### Story 2: Run Tests on Demand
**As a** developer
**I want to** run tests against a specific prompt version
**So that** I can validate changes before deploying

**Acceptance Criteria:**
- Can run individual test
- Can run all tests for a prompt version
- See real-time progress
- View detailed results

### Story 3: Monitor Test History
**As a** team lead
**I want to** view test results over time
**So that** I can track prompt quality trends

**Acceptance Criteria:**
- View test pass/fail history
- See trends over time
- Filter by date range, status, tags
- Export results for reporting

## 🚀 CLI Interface

```bash
# Run all tests for a prompt
bundle exec rails prompt_tracker:test:run PROMPT=customer_support_greeting

# Run specific test
bundle exec rails prompt_tracker:test:run TEST=greeting_premium_user

# Run tests in CI
bundle exec rails prompt_tracker:test:ci --format=junit --output=test-results/
```

## 📊 Success Metrics

- **Test Coverage** - % of prompts with tests
- **Pass Rate** - % of tests passing
- **Execution Time** - Average test duration
- **Adoption** - Number of tests created per week
