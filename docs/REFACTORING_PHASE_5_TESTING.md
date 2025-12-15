# Phase 5: Testing Strategy (RSpec)

## 📋 Overview

Comprehensive RSpec test suite for the refactored architecture.

## 🧪 Test Structure

### 1. Model Specs

#### EvaluatorConfig Spec

**File:** `spec/models/prompt_tracker/evaluator_config_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::EvaluatorConfig, type: :model do
  describe 'associations' do
    it { should belong_to(:configurable) }

    context 'when configurable is PromptVersion' do
      let(:version) { create(:prompt_version) }
      let(:config) { create(:evaluator_config, configurable: version) }

      it 'associates with PromptVersion' do
        expect(config.configurable).to eq(version)
        expect(config.for_prompt_version?).to be true
        expect(config.for_prompt_test?).to be false
      end
    end

    context 'when configurable is PromptTest' do
      let(:test) { create(:prompt_test) }
      let(:config) { create(:evaluator_config, configurable: test) }

      it 'associates with PromptTest' do
        expect(config.configurable).to eq(test)
        expect(config.for_prompt_test?).to be true
        expect(config.for_prompt_version?).to be false
      end
    end
  end

  describe 'validations' do
    let(:version) { create(:prompt_version) }

    it { should validate_presence_of(:evaluator_key) }
    it { should validate_presence_of(:run_mode) }
    it { should validate_inclusion_of(:run_mode).in_array(%w[sync async]) }

    it 'validates uniqueness scoped to configurable' do
      create(:evaluator_config, configurable: version, evaluator_key: 'length_check')
      duplicate = build(:evaluator_config, configurable: version, evaluator_key: 'length_check')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:evaluator_key]).to include('has already been taken')
    end

    it 'validates threshold range' do
      config = build(:evaluator_config, threshold: 150)
      expect(config).not_to be_valid

      config.threshold = 80
      expect(config).to be_valid
    end
  end

  describe 'dependency validation' do
    let(:version) { create(:prompt_version) }

    it 'validates dependency exists' do
      config = build(:evaluator_config,
                     configurable: version,
                     depends_on: 'nonexistent')

      expect(config).not_to be_valid
      expect(config.errors[:depends_on]).to include(/must be configured/)
    end

    it 'detects circular dependencies' do
      config1 = create(:evaluator_config,
                       configurable: version,
                       evaluator_key: 'eval1')
      config2 = create(:evaluator_config,
                       configurable: version,
                       evaluator_key: 'eval2',
                       depends_on: 'eval1')
      config1.depends_on = 'eval2'

      expect(config1).not_to be_valid
      expect(config1.errors[:depends_on]).to include(/circular dependency/)
    end
  end

  describe '#normalized_weight' do
    let(:version) { create(:prompt_version) }

    it 'calculates normalized weight' do
      create(:evaluator_config, configurable: version, weight: 0.3, enabled: true)
      config = create(:evaluator_config, configurable: version, weight: 0.7, enabled: true)

      expect(config.normalized_weight).to eq(0.7)
    end
  end
end
```

#### PromptVersion Spec

**File:** `spec/models/prompt_tracker/prompt_version_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::PromptVersion, type: :model do
  describe 'associations' do
    it { should have_many(:evaluator_configs).dependent(:destroy) }
  end

  describe '#copy_evaluator_configs_from' do
    let(:source_version) { create(:prompt_version) }
    let(:target_version) { create(:prompt_version) }

    before do
      create(:evaluator_config,
             configurable: source_version,
             evaluator_key: 'length_check',
             weight: 0.5,
             threshold: 80)
      create(:evaluator_config,
             configurable: source_version,
             evaluator_key: 'keyword_check',
             weight: 0.5,
             threshold: 90)
    end

    it 'copies all evaluator configs' do
      expect {
        target_version.copy_evaluator_configs_from(source_version)
      }.to change { target_version.evaluator_configs.count }.from(0).to(2)

      expect(target_version.evaluator_configs.pluck(:evaluator_key))
        .to match_array(['length_check', 'keyword_check'])
    end
  end

  describe '#has_monitoring_enabled?' do
    let(:version) { create(:prompt_version) }

    it 'returns false when no configs' do
      expect(version.has_monitoring_enabled?).to be false
    end

    it 'returns true when has enabled configs' do
      create(:evaluator_config, configurable: version, enabled: true)
      expect(version.has_monitoring_enabled?).to be true
    end

    it 'returns false when all configs disabled' do
      create(:evaluator_config, configurable: version, enabled: false)
      expect(version.has_monitoring_enabled?).to be false
    end
  end
end
```

#### LlmResponse Spec

**File:** `spec/models/prompt_tracker/llm_response_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::LlmResponse, type: :model do
  describe 'scopes' do
    let!(:production_response) { create(:llm_response, is_test_run: false) }
    let!(:test_response) { create(:llm_response, is_test_run: true) }

    it 'filters production calls' do
      expect(described_class.production_calls).to include(production_response)
      expect(described_class.production_calls).not_to include(test_response)
    end

    it 'filters test calls' do
      expect(described_class.test_calls).to include(test_response)
      expect(described_class.test_calls).not_to include(production_response)
    end
  end

  describe 'callbacks' do
    let(:version) { create(:prompt_version) }

    before do
      create(:evaluator_config,
             configurable: version,
             enabled: true,
             run_mode: 'sync',
             evaluator_key: 'length_check')
    end

    it 'triggers auto-evaluation for production calls' do
      expect {
        create(:llm_response, prompt_version: version, is_test_run: false)
      }.to change { PromptTracker::Evaluation.count }.by(1)
    end

    it 'does not trigger auto-evaluation for test runs' do
      expect {
        create(:llm_response, prompt_version: version, is_test_run: true)
      }.not_to change { PromptTracker::Evaluation.count }
    end
  end
end
```

#### Evaluation Spec

**File:** `spec/models/prompt_tracker/evaluation_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::Evaluation, type: :model do
  describe 'enums' do
    it { should define_enum_for(:evaluation_context).with_values(
      tracked_call: 'tracked_call',
      test_run: 'test_run',
      manual: 'manual'
    )}
  end

  describe 'scopes' do
    let!(:tracked_eval) { create(:evaluation, evaluation_context: 'tracked_call') }
    let!(:test_eval) { create(:evaluation, evaluation_context: 'test_run') }
    let!(:manual_eval) { create(:evaluation, evaluation_context: 'manual') }

    it 'filters tracked evaluations' do
      expect(described_class.tracked).to include(tracked_eval)
      expect(described_class.tracked).not_to include(test_eval, manual_eval)
    end

    it 'filters test evaluations' do
      expect(described_class.from_tests).to include(test_eval)
      expect(described_class.from_tests).not_to include(tracked_eval, manual_eval)
    end
  end
end
```

### 2. Service Specs

#### AutoEvaluationService Spec

**File:** `spec/services/prompt_tracker/auto_evaluation_service_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::AutoEvaluationService do
  let(:version) { create(:prompt_version) }
  let(:response) { create(:llm_response, prompt_version: version, is_test_run: false) }

  describe '.evaluate' do
    context 'with enabled evaluators' do
      before do
        create(:evaluator_config,
               configurable: version,
               evaluator_key: 'length_check',
               enabled: true,
               run_mode: 'sync',
               config: { min_length: 10, max_length: 100 })
      end

      it 'creates evaluations with tracked_call context' do
        described_class.evaluate(response)

        evaluation = response.evaluations.first
        expect(evaluation).to be_present
        expect(evaluation.evaluation_context).to eq('tracked_call')
      end
    end

    context 'with disabled evaluators' do
      before do
        create(:evaluator_config,
               configurable: version,
               enabled: false)
      end

      it 'does not create evaluations' do
        expect {
          described_class.evaluate(response)
        }.not_to change { response.evaluations.count }
      end
    end

    context 'with dependencies' do
      before do
        create(:evaluator_config,
               configurable: version,
               evaluator_key: 'length_check',
               enabled: true,
               run_mode: 'sync')
        create(:evaluator_config,
               configurable: version,
               evaluator_key: 'keyword_check',
               enabled: true,
               run_mode: 'sync',
               depends_on: 'length_check',
               min_dependency_score: 80)
      end

      it 'runs dependent evaluators when dependency met' do
        # Mock length_check to return high score
        allow_any_instance_of(PromptTracker::Evaluators::LengthCheckEvaluator)
          .to receive(:evaluate).and_return(
            double(score: 90, evaluator_type: 'automated', evaluator_id: 'length_check_v1',
                   score_min: 0, score_max: 100, feedback: 'Good', metadata: {}, criteria_scores: {})
          )

        described_class.evaluate(response)

        expect(response.evaluations.count).to eq(2)
      end
    end
  end
end
```

#### PromptTestRunner Spec

**File:** `spec/services/prompt_tracker/prompt_test_runner_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::PromptTestRunner do
  let(:version) { create(:prompt_version) }
  let(:test) { create(:prompt_test, prompt_version: version) }

  before do
    create(:evaluator_config,
           configurable: test,
           evaluator_key: 'length_check',
           threshold: 80,
           config: { min_length: 10 })
  end

  describe '#run!' do
    it 'creates test run with is_test_run flag' do
      runner = described_class.new(test, version)
      test_run = runner.run! { |_| "Mock response" }

      expect(test_run.llm_response.is_test_run?).to be true
    end

    it 'creates evaluations with test_run context' do
      runner = described_class.new(test, version)
      test_run = runner.run! { |_| "Mock response" }

      evaluation = test_run.llm_response.evaluations.first
      expect(evaluation.evaluation_context).to eq('test_run')
    end

    it 'uses EvaluatorConfig records not JSONB' do
      runner = described_class.new(test, version)

      expect(test.evaluator_configs).to be_a(ActiveRecord::Relation)
      expect(test.evaluator_configs.first).to be_a(PromptTracker::EvaluatorConfig)
    end
  end
end
```

### 3. Controller Specs

#### Monitoring::DashboardController Spec

**File:** `spec/controllers/prompt_tracker/monitoring/dashboard_controller_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe PromptTracker::Monitoring::DashboardController, type: :controller do
  routes { PromptTracker::Engine.routes }

  describe 'GET #index' do
    let!(:production_response) { create(:llm_response, is_test_run: false) }
    let!(:test_response) { create(:llm_response, is_test_run: true) }

    it 'shows only production responses' do
      get :index

      expect(assigns(:total_responses)).to eq(1)
    end

    it 'shows tracked evaluations' do
      create(:evaluation,
             llm_response: production_response,
             evaluation_context: 'tracked_call')
      create(:evaluation,
             llm_response: test_response,
             evaluation_context: 'test_run')

      get :index

      expect(assigns(:recent_evaluations).count).to eq(1)
      expect(assigns(:recent_evaluations).first.evaluation_context).to eq('tracked_call')
    end
  end
end
```

### 4. Factory Updates

**File:** `spec/factories/prompt_tracker/evaluator_configs.rb`

```ruby
FactoryBot.define do
  factory :evaluator_config, class: 'PromptTracker::EvaluatorConfig' do
    association :configurable, factory: :prompt_version

    evaluator_key { 'length_check' }
    enabled { true }
    run_mode { 'sync' }
    priority { 0 }
    weight { 1.0 }
    threshold { 80 }
    config { { min_length: 10, max_length: 500 } }

    trait :for_prompt_version do
      association :configurable, factory: :prompt_version
    end

    trait :for_prompt_test do
      association :configurable, factory: :prompt_test
    end

    trait :async do
      run_mode { 'async' }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_dependency do
      depends_on { 'length_check' }
      min_dependency_score { 80 }
    end
  end
end
```

**File:** `spec/factories/prompt_tracker/llm_responses.rb`

```ruby
FactoryBot.define do
  factory :llm_response, class: 'PromptTracker::LlmResponse' do
    association :prompt_version

    rendered_prompt { "Test prompt" }
    response_text { "Test response" }
    variables_used { { name: "Test" } }
    provider { "openai" }
    model { "gpt-4" }
    status { "success" }
    is_test_run { false }

    trait :production_call do
      is_test_run { false }
    end

    trait :test_call do
      is_test_run { true }
    end
  end
end
```

**File:** `spec/factories/prompt_tracker/evaluations.rb`

```ruby
FactoryBot.define do
  factory :evaluation, class: 'PromptTracker::Evaluation' do
    association :llm_response

    evaluator_type { 'automated' }
    evaluator_id { 'length_check_v1' }
    score { 85 }
    score_min { 0 }
    score_max { 100 }
    evaluation_context { 'tracked_call' }

    trait :tracked do
      evaluation_context { 'tracked_call' }
    end

    trait :test_run do
      evaluation_context { 'test_run' }
    end

    trait :manual do
      evaluation_context { 'manual' }
      evaluator_type { 'human' }
    end
  end
end
```

## ✅ Test Coverage Goals

- [ ] Model specs: 100% coverage
- [ ] Service specs: 95%+ coverage
- [ ] Controller specs: 90%+ coverage
- [ ] Integration specs: Key user flows
- [ ] All edge cases covered

## 🚀 Running Tests

```bash
# Run all specs
bundle exec rspec

# Run specific phase tests
bundle exec rspec spec/models/prompt_tracker/evaluator_config_spec.rb
bundle exec rspec spec/services/prompt_tracker/auto_evaluation_service_spec.rb
bundle exec rspec spec/controllers/prompt_tracker/monitoring/

# Run with coverage
COVERAGE=true bundle exec rspec
```
