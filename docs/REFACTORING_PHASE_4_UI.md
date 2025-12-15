# Phase 4: UI Restructuring

## 📋 Overview

Restructure UI to clearly separate:
- **Tests** (pre-deployment validation)
- **Monitoring** (production runtime evaluation)

## 🎨 UI Changes

### 1. Navigation Updates

**File:** `app/views/layouts/prompt_tracker/application.html.erb`

**Changes:**
```erb
<ul class="navbar-nav me-auto">
  <li class="nav-item">
    <%= link_to "Prompts", prompts_path, class: "nav-link" %>
  </li>
  <li class="nav-item">
    <%= link_to "Tests", prompt_test_suites_path, class: "nav-link" %>
  </li>
  <li class="nav-item">
    <%= link_to "Monitoring", monitoring_path, class: "nav-link" %>  <!-- NEW -->
  </li>
  <li class="nav-item">
    <%= link_to "A/B Tests", ab_tests_path, class: "nav-link" %>
  </li>
  <li class="nav-item">
    <%= link_to "Analytics", analytics_root_path, class: "nav-link" %>
  </li>
</ul>
```

### 2. Routes Updates

**File:** `config/routes.rb`

**Changes:**
```ruby
PromptTracker::Engine.routes.draw do
  root to: "prompts#index"

  resources :prompts, only: [:index, :show] do
    member do
      get :analytics
    end

    resources :prompt_versions, only: [:show], path: "versions" do
      member do
        get :compare
        post :activate
      end

      # Tests nested under versions
      resources :prompt_tests, only: [:index, :new, :create, :show, :edit, :update, :destroy], path: "tests" do
        collection do
          post :run_all
        end
        member do
          post :run
        end
      end

      # NEW: Monitoring configs nested under versions
      resources :evaluator_configs, only: [:index, :new, :create, :show, :edit, :update, :destroy], path: "monitoring" do
        member do
          post :enable
          post :disable
        end
      end
    end
  end

  # NEW: Monitoring section (top-level)
  namespace :monitoring do
    get "/", to: "dashboard#index", as: :root
    resources :llm_responses, only: [:index, :show], path: "responses"
    resources :evaluations, only: [:index, :show]
  end

  # Tests section (top-level)
  resources :prompt_test_runs, only: [:index, :show], path: "test-runs"

  # Keep existing routes for backwards compatibility
  resources :llm_responses, only: [:index, :show], path: "responses"
  resources :evaluations, only: [:index, :show, :create]

  # ... rest of routes
end
```

### 3. New Monitoring Controllers

**File:** `app/controllers/prompt_tracker/monitoring/dashboard_controller.rb`

```ruby
module PromptTracker
  module Monitoring
    class DashboardController < ApplicationController
      def index
        # Show production monitoring overview
        @total_responses = LlmResponse.production_calls.count
        @monitored_versions = PromptVersion.joins(:evaluator_configs)
                                          .where(prompt_tracker_evaluator_configs: { enabled: true })
                                          .distinct
                                          .count

        @recent_evaluations = Evaluation.production
                                       .includes(llm_response: { prompt_version: :prompt })
                                       .order(created_at: :desc)
                                       .limit(20)

        # Quality metrics
        @avg_score = Evaluation.production
                              .where("created_at >= ?", 7.days.ago)
                              .average(:score)

        # Alerts (low scores)
        @low_score_responses = LlmResponse.production_calls
                                         .joins(:evaluations)
                                         .where("prompt_tracker_evaluations.score < 50")
                                         .where("prompt_tracker_evaluations.created_at >= ?", 24.hours.ago)
                                         .distinct
      end
    end
  end
end
```

**File:** `app/controllers/prompt_tracker/monitoring/llm_responses_controller.rb`

```ruby
module PromptTracker
  module Monitoring
    class LlmResponsesController < ApplicationController
      def index
        @responses = LlmResponse.production_calls
                               .includes(prompt_version: :prompt, evaluations: [])
                               .order(created_at: :desc)

        # Filters
        if params[:prompt_id].present?
          @responses = @responses.joins(prompt_version: :prompt)
                                .where(prompt_tracker_prompts: { id: params[:prompt_id] })
        end

        if params[:has_evaluations] == 'true'
          @responses = @responses.joins(:evaluations).distinct
        elsif params[:has_evaluations] == 'false'
          @responses = @responses.left_joins(:evaluations)
                                .where(prompt_tracker_evaluations: { id: nil })
        end

        @responses = @responses.page(params[:page]).per(20)
      end

      def show
        @response = LlmResponse.production_calls.find(params[:id])
        @evaluations = @response.evaluations.production.order(created_at: :desc)
      end
    end
  end
end
```

**File:** `app/controllers/prompt_tracker/monitoring/evaluations_controller.rb`

```ruby
module PromptTracker
  module Monitoring
    class EvaluationsController < ApplicationController
      def index
        @evaluations = Evaluation.production
                                .includes(llm_response: { prompt_version: :prompt })
                                .order(created_at: :desc)

        # Filters
        if params[:evaluator_key].present?
          @evaluations = @evaluations.where("evaluator_id LIKE ?", "%#{params[:evaluator_key]}%")
        end

        if params[:score_range].present?
          case params[:score_range]
          when 'high'
            @evaluations = @evaluations.where("score >= 80")
          when 'medium'
            @evaluations = @evaluations.where("score >= 50 AND score < 80")
          when 'low'
            @evaluations = @evaluations.where("score < 50")
          end
        end

        @evaluations = @evaluations.page(params[:page]).per(20)
      end

      def show
        @evaluation = Evaluation.production.find(params[:id])
        @response = @evaluation.llm_response
      end
    end
  end
end
```

### 4. Update EvaluatorConfigsController

**File:** `app/controllers/prompt_tracker/evaluator_configs_controller.rb`

**Changes:**
```ruby
class EvaluatorConfigsController < ApplicationController
  before_action :set_prompt_version
  before_action :set_evaluator_config, only: [:show, :edit, :update, :destroy, :enable, :disable]

  def index
    @configs = @version.evaluator_configs.order(priority: :desc)
  end

  def new
    @config = @version.evaluator_configs.build(
      enabled: true,
      run_mode: 'async',
      priority: 0,
      weight: 1.0
    )
  end

  def create
    @config = @version.evaluator_configs.build(evaluator_config_params)

    if @config.save
      redirect_to prompt_prompt_version_evaluator_configs_path(@prompt, @version),
                  notice: "Monitoring evaluator configured successfully."
    else
      render :new
    end
  end

  # ... rest of CRUD actions

  def enable
    @config.update!(enabled: true)
    redirect_to prompt_prompt_version_evaluator_configs_path(@prompt, @version),
                notice: "Evaluator enabled."
  end

  def disable
    @config.update!(enabled: false)
    redirect_to prompt_prompt_version_evaluator_configs_path(@prompt, @version),
                notice: "Evaluator disabled."
  end

  private

  def set_prompt_version
    @version = PromptVersion.find(params[:prompt_version_id])
    @prompt = @version.prompt
  end

  def set_evaluator_config
    @config = @version.evaluator_configs.find(params[:id])
  end

  def evaluator_config_params
    params.require(:evaluator_config).permit(
      :evaluator_key, :enabled, :run_mode, :priority, :weight, :threshold,
      :depends_on, :min_dependency_score, config: {}
    )
  end
end
```

### 5. New Views Structure

**Directory Structure:**
```
app/views/prompt_tracker/
├── monitoring/
│   ├── dashboard/
│   │   └── index.html.erb          # Monitoring overview
│   ├── llm_responses/
│   │   ├── index.html.erb          # Production responses list
│   │   └── show.html.erb           # Response detail with evals
│   └── evaluations/
│       ├── index.html.erb          # Production evaluations list
│       └── show.html.erb           # Evaluation detail
├── evaluator_configs/
│   ├── index.html.erb              # Monitoring config for version
│   ├── new.html.erb                # Add monitoring evaluator
│   ├── edit.html.erb               # Edit monitoring evaluator
│   └── _form.html.erb              # Shared form
├── prompt_tests/
│   ├── index.html.erb              # Tests for version
│   ├── show.html.erb               # Test detail
│   ├── new.html.erb                # Create test
│   ├── edit.html.erb               # Edit test
│   └── _form.html.erb              # Test form
└── prompts/
    └── show.html.erb               # Updated to show both tabs
```

### 6. Prompt Show Page Updates

**File:** `app/views/prompt_tracker/prompts/show.html.erb`

**Changes:**
```erb
<div class="container mt-4">
  <h1><%= @prompt.name %></h1>

  <!-- Tabs for Tests vs Monitoring -->
  <ul class="nav nav-tabs mt-4" role="tablist">
    <li class="nav-item">
      <a class="nav-link active" data-bs-toggle="tab" href="#overview">Overview</a>
    </li>
    <li class="nav-item">
      <a class="nav-link" data-bs-toggle="tab" href="#tests">
        Tests
        <span class="badge bg-primary"><%= @active_version&.prompt_tests&.count || 0 %></span>
      </a>
    </li>
    <li class="nav-item">
      <a class="nav-link" data-bs-toggle="tab" href="#monitoring">
        Monitoring
        <% if @active_version&.has_monitoring_enabled? %>
          <span class="badge bg-success">Enabled</span>
        <% else %>
          <span class="badge bg-secondary">Disabled</span>
        <% end %>
      </a>
    </li>
    <li class="nav-item">
      <a class="nav-link" data-bs-toggle="tab" href="#versions">Versions</a>
    </li>
  </ul>

  <div class="tab-content mt-3">
    <!-- Overview Tab -->
    <div class="tab-pane fade show active" id="overview">
      <%= render 'overview', prompt: @prompt %>
    </div>

    <!-- Tests Tab -->
    <div class="tab-pane fade" id="tests">
      <% if @active_version %>
        <div class="d-flex justify-content-between align-items-center mb-3">
          <h3>Tests for Version <%= @active_version.version_number %></h3>
          <%= link_to "Manage Tests",
                      prompt_prompt_version_prompt_tests_path(@prompt, @active_version),
                      class: "btn btn-primary" %>
        </div>
        <%= render 'prompt_tests/summary', version: @active_version %>
      <% else %>
        <p class="text-muted">No active version</p>
      <% end %>
    </div>

    <!-- Monitoring Tab -->
    <div class="tab-pane fade" id="monitoring">
      <% if @active_version %>
        <div class="d-flex justify-content-between align-items-center mb-3">
          <h3>Production Monitoring for Version <%= @active_version.version_number %></h3>
          <%= link_to "Configure Monitoring",
                      prompt_prompt_version_evaluator_configs_path(@prompt, @active_version),
                      class: "btn btn-primary" %>
        </div>
        <%= render 'evaluator_configs/summary', version: @active_version %>
      <% else %>
        <p class="text-muted">No active version</p>
      <% end %>
    </div>

    <!-- Versions Tab -->
    <div class="tab-pane fade" id="versions">
      <%= render 'versions', versions: @versions %>
    </div>
  </div>
</div>
```

## ✅ Validation Checklist

- [ ] Navigation includes Tests and Monitoring links
- [ ] Routes separate monitoring from tests
- [ ] Monitoring controllers created
- [ ] Monitoring views created
- [ ] Prompt show page has tabs for Tests and Monitoring
- [ ] EvaluatorConfigs nested under PromptVersion
- [ ] Clear visual distinction between test and production data

## 🎨 UI/UX Guidelines

### Visual Distinctions

**Tests Section:**
- Color: Blue (`bg-primary`)
- Icon: `bi-clipboard-check`
- Focus: Pass/Fail, Thresholds, Pre-deployment

**Monitoring Section:**
- Color: Green (`bg-success`)
- Icon: `bi-activity`
- Focus: Real-time, Production, Alerts

### Key Differences in UI

| Feature | Tests | Monitoring |
|---------|-------|------------|
| **Badge** | "X tests" | "Enabled/Disabled" |
| **Metrics** | Pass rate, Last run | Avg score, Alert count |
| **Actions** | Run test, Edit test | Enable/Disable, View logs |
| **Data** | Test runs only | Production calls only |
| **Filters** | By status, tags | By score, time range |
