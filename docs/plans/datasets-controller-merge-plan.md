# Datasets Controller Merge Plan

## Overview
Merge `DatasetsController` and `AssistantDatasetsController` into a unified polymorphic implementation that works with both PromptVersion and Assistant testables **without type checking or branching**.

## Key Principles
1. **No type checking**: Avoid `if testable.is_a?(PromptVersion)` patterns
2. **Polymorphic helpers**: Use helper methods that work with any testable
3. **Schema-driven views**: Let the schema data drive the UI, not the testable type
4. **Unified card layout**: Use card layout for all testables (not table)
5. **Smart breadcrumbs**: Use polymorphic path helpers for navigation

---

## Phase 1: Create Polymorphic Helper Methods

### File: `app/helpers/prompt_tracker/datasets_helper.rb`

**Purpose**: Encapsulate all route generation logic to avoid branching in views.

**Methods to create**:
- `dataset_path(dataset, action: :show)` - Generate path for any dataset action
- `datasets_index_path(testable)` - Generate index path
- `new_dataset_path(testable)` - Generate new dataset path
- `dataset_row_path(dataset, row, action: :destroy)` - Generate row paths
- `testable_show_path(testable)` - Generate path back to testable
- `testable_name(testable)` - Get display name for testable
- `testable_badge(testable)` - Generate badge HTML for testable (e.g., version number)

**Key insight**: These helpers use `case testable` internally, but views never need to check types.

---

## Phase 2: Create Base Controller

### File: `app/controllers/prompt_tracker/testing/datasets_controller_base.rb`

**Purpose**: Share all common controller logic between the two controllers.

**Actions**: All CRUD + `generate_rows`

**Abstract methods** (to be implemented by subclasses):
- `set_testable` - Set `@testable` instance variable
- None! Everything else can be shared.

**Instance variables to set**:
- `@testable` - The polymorphic parent (PromptVersion or Assistant)
- `@dataset` - The dataset being operated on
- `@datasets` - Collection of datasets (for index)

---

## Phase 3: Update Existing Controllers

### File: `app/controllers/prompt_tracker/testing/datasets_controller.rb`

**Changes**:
1. Inherit from `DatasetsControllerBase`
2. Keep only `set_testable` method (sets `@version`, `@prompt`, `@testable`)
3. Remove all other methods (inherited from base)

### File: `app/controllers/prompt_tracker/testing/openai/assistant_datasets_controller.rb`

**Changes**:
1. Inherit from `DatasetsControllerBase` (not `ApplicationController`)
2. Keep only `set_testable` method (sets `@assistant`, `@testable`)
3. Remove all other methods (inherited from base)
4. Remove hardcoded schema logic (model handles this)

---

## Phase 4: Unify Views (No Branching!)

### Strategy: Schema-Driven Rendering

The key insight: **The schema already contains all the information we need!**

- PromptVersion: `schema = [{ name: "customer_name", type: "string", ... }]`
- Assistant: `schema = [{ name: "interlocutor_simulation_prompt", type: "string", description: "..." }]`

Views iterate over `dataset.schema` - they don't care about the testable type!

### Files to Unify

#### 1. `app/views/prompt_tracker/testing/datasets/index.html.erb`

**Current differences**:
- Breadcrumbs: Different paths
- Header: Different text and badges
- Layout: Card vs Table (→ **Use cards for both**)
- Links: Different route helpers

**Solution**:
```erb
<%# Breadcrumbs - use helper %>
<% content_for :breadcrumbs do %>
  <li class="breadcrumb-item"><%= link_to testable_name(@testable), testable_show_path(@testable) %></li>
  <li class="breadcrumb-item active">Datasets</li>
<% end %>

<%# Header - use helper for badge %>
<div class="page-header" style="background-color: #EFF6FF; border-left: 4px solid #3B82F6; padding: 1.5rem; margin-bottom: 2rem;">
  <div class="d-flex justify-content-between align-items-start">
    <div>
      <h1 style="color: #1E40AF; margin: 0;">
        <i class="bi bi-database"></i> Datasets
        <%= testable_badge(@testable) %>
      </h1>
      <p style="color: #1E40AF; margin: 0.5rem 0 0 0;">
        Reusable test data collections for <%= testable_name(@testable) %>
      </p>
    </div>
    <div class="d-flex gap-2">
      <%= link_to testable_show_path(@testable), class: "btn btn-outline-primary" do %>
        <i class="bi bi-arrow-left"></i> Back
      <% end %>
      <%= link_to new_dataset_path(@testable), class: "btn btn-primary" do %>
        <i class="bi bi-plus-circle"></i> New Dataset
      <% end %>
    </div>
  </div>
</div>

<%# Card layout for all testables %>
<% if @datasets.any? %>
  <div class="row">
    <% @datasets.each do |dataset| %>
      <%= render "dataset_card", dataset: dataset, testable: @testable %>
    <% end %>
  </div>
<% else %>
  <%= render "empty_state", testable: @testable %>
<% end %>
```

**No branching!** All differences handled by helpers.

#### 2. `app/views/prompt_tracker/testing/datasets/_dataset_card.html.erb` (NEW)

**Purpose**: Unified card partial for displaying a dataset.

**Key**: Uses `dataset.schema` to display variables - works for any testable!

```erb
<div class="col-md-6 col-lg-4 mb-4">
  <div class="card h-100">
    <div class="card-header d-flex justify-content-between align-items-center">
      <h5 class="mb-0">
        <i class="bi bi-database"></i> <%= dataset.name %>
      </h5>
      <% if !dataset.schema_valid? %>
        <span class="badge bg-danger" title="Schema no longer matches">
          <i class="bi bi-exclamation-triangle"></i> Invalid
        </span>
      <% end %>
    </div>
    <div class="card-body">
      <% if dataset.description.present? %>
        <p class="text-muted small"><%= dataset.description %></p>
      <% end %>

      <div class="mb-3">
        <div class="d-flex justify-content-between align-items-center mb-2">
          <span class="text-muted small">Rows</span>
          <span class="badge bg-primary"><%= dataset.row_count %></span>
        </div>
        <div class="d-flex justify-content-between align-items-center">
          <span class="text-muted small">Variables</span>
          <span class="badge bg-secondary"><%= dataset.variable_names.count %></span>
        </div>
      </div>

      <%# Schema-driven variable display %>
      <% if dataset.variable_names.any? %>
        <div class="mb-3">
          <small class="text-muted d-block mb-1">Variables:</small>
          <div class="d-flex flex-wrap gap-1">
            <% dataset.variable_names.first(5).each do |var_name| %>
              <span class="badge bg-light text-dark"><%= var_name %></span>
            <% end %>
            <% if dataset.variable_names.count > 5 %>
              <span class="badge bg-light text-dark">+<%= dataset.variable_names.count - 5 %> more</span>
            <% end %>
          </div>
        </div>
      <% end %>

      <small class="text-muted">
        Created <%= time_ago_in_words(dataset.created_at) %> ago
        <% if dataset.created_by.present? %>
          by <%= dataset.created_by %>
        <% end %>
      </small>
    </div>
    <div class="card-footer">
      <div class="d-flex gap-2">
        <%= link_to dataset_path(dataset), class: "btn btn-sm btn-primary flex-grow-1" do %>
          <i class="bi bi-eye"></i> View
        <% end %>
        <%= link_to dataset_path(dataset, action: :edit), class: "btn btn-sm btn-outline-secondary" do %>
          <i class="bi bi-pencil"></i>
        <% end %>
        <%= button_to dataset_path(dataset, action: :destroy),
                      method: :delete,
                      class: "btn btn-sm btn-outline-danger",
                      data: { confirm: "Delete this dataset? This will also delete all #{dataset.row_count} rows." } do %>
          <i class="bi bi-trash"></i>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

#### 3. `app/views/prompt_tracker/testing/datasets/_empty_state.html.erb` (NEW)

```erb
<div class="text-center py-5">
  <i class="bi bi-database text-muted" style="font-size: 3rem;"></i>
  <p class="text-muted mt-3">No datasets yet</p>
  <p class="text-muted">Datasets help you run tests at scale with multiple data rows.</p>
  <%= link_to new_dataset_path(testable), class: "btn btn-primary mt-2" do %>
    <i class="bi bi-plus-circle"></i> Create Your First Dataset
  <% end %>
</div>
```

#### 4. `app/views/prompt_tracker/testing/datasets/_form.html.erb`

**Current issue**: References `@version.variables_schema` directly.

**Solution**: Use `dataset.schema` instead!

```erb
<%= form_with(model: dataset, url: form_url, method: form_method, local: true) do |f| %>
  <%# Error messages %>
  <% if dataset.errors.any? %>
    <div class="alert alert-danger">
      <h6 class="alert-heading">Please fix the following errors:</h6>
      <ul class="mb-0">
        <% dataset.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%# Basic fields %>
  <div class="mb-3">
    <%= f.label :name, class: "form-label" %>
    <%= f.text_field :name, class: "form-control", placeholder: "e.g., Customer Support Scenarios", required: true %>
    <div class="form-text">A descriptive name for this dataset</div>
  </div>

  <div class="mb-3">
    <%= f.label :description, class: "form-label" %>
    <%= f.text_area :description, class: "form-control", rows: 3, placeholder: "Describe what this dataset contains..." %>
    <div class="form-text">Optional description to help others understand this dataset</div>
  </div>

  <%# Schema info - driven by dataset.schema %>
  <div class="mb-3">
    <label class="form-label">Schema</label>
    <div class="alert alert-info">
      <small>
        <i class="bi bi-info-circle"></i>
        <% if dataset.new_record? %>
          The schema will be automatically copied from the <%= testable.class.name.demodulize.downcase %>.
        <% end %>
        <% if dataset.schema.present? %>
          This dataset uses the following variables:
          <strong><%= dataset.schema.map { |v| v["name"] }.join(", ") %></strong>
        <% end %>
      </small>
    </div>
  </div>

  <%# Submit buttons %>
  <div class="d-flex gap-2">
    <%= f.submit submit_text, class: "btn btn-primary" %>
    <%= link_to "Cancel", cancel_path, class: "btn btn-outline-secondary" %>
  </div>
<% end %>
```

**Key**: No reference to `@version` or `@assistant` - only `dataset` and `testable`!

#### 5. `app/views/prompt_tracker/testing/datasets/new.html.erb`

```erb
<% content_for :breadcrumbs do %>
  <li class="breadcrumb-item"><%= link_to testable_name(@testable), testable_show_path(@testable) %></li>
  <li class="breadcrumb-item"><%= link_to "Datasets", datasets_index_path(@testable) %></li>
  <li class="breadcrumb-item active">New Dataset</li>
<% end %>

<div class="page-header" style="background-color: #EFF6FF; border-left: 4px solid #3B82F6; padding: 1.5rem; margin-bottom: 2rem;">
  <h1 style="color: #1E40AF; margin: 0;">
    <i class="bi bi-database"></i> New Dataset
    <%= testable_badge(@testable) %>
  </h1>
  <p style="color: #1E40AF; margin: 0.5rem 0 0 0;">
    Create a new test data collection for <%= testable_name(@testable) %>
  </p>
</div>

<div class="row">
  <div class="col-lg-8">
    <div class="card">
      <div class="card-body">
        <%= render "form",
                   dataset: @dataset,
                   testable: @testable,
                   form_url: datasets_index_path(@testable),
                   form_method: :post,
                   submit_text: "Create Dataset",
                   cancel_path: datasets_index_path(@testable) %>
      </div>
    </div>
  </div>

  <div class="col-lg-4">
    <div class="card">
      <div class="card-header">
        <h6 class="mb-0"><i class="bi bi-lightbulb"></i> Tips</h6>
      </div>
      <div class="card-body">
        <ul class="small mb-0">
          <li>After creating the dataset, you can add rows manually or generate them with AI</li>
          <li>Each row must match the schema</li>
          <li>Datasets become invalid if the schema changes</li>
        </ul>
      </div>
    </div>
  </div>
</div>
```

#### 6. `app/views/prompt_tracker/testing/datasets/edit.html.erb`

Similar pattern - use helpers, no branching.

#### 7. `app/views/prompt_tracker/testing/datasets/show.html.erb`

**Key changes**:
- Use `dataset_path` helper for all links
- Use `dataset.schema` to build modals dynamically
- Already mostly schema-driven!

---

## Phase 5: Delete Assistant-Specific Views

Once unified views are working, delete:
- `app/views/prompt_tracker/testing/openai/assistant_datasets/index.html.erb`
- `app/views/prompt_tracker/testing/openai/assistant_datasets/new.html.erb`
- `app/views/prompt_tracker/testing/openai/assistant_datasets/edit.html.erb`
- `app/views/prompt_tracker/testing/openai/assistant_datasets/show.html.erb`
- `app/views/prompt_tracker/testing/openai/assistant_datasets/_form.html.erb`
- `app/views/prompt_tracker/testing/openai/assistant_datasets/_dataset_row.html.erb` (use generic `_row.html.erb`)

**Keep**:
- `_add_row_modal.html.erb` (if different) or unify
- `_edit_row_modal.html.erb` (if different) or unify
- `_generate_rows_modal.html.erb` (likely identical, can unify)

---

## Phase 6: Update Routes (No Changes Needed!)

Routes stay exactly as they are:
```ruby
# PromptVersion datasets
resources :prompt_versions do
  resources :datasets  # → DatasetsController
end

# Assistant datasets
namespace :openai do
  resources :assistants do
    resources :datasets, controller: "assistant_datasets"  # → AssistantDatasetsController
  end
end
```

Both controllers inherit from the same base, both use the same views!

---

## Implementation Order

### Step 1: Create Helper (Safe)
1. Create `app/helpers/prompt_tracker/datasets_helper.rb`
2. Add all polymorphic path methods
3. Test manually in console

### Step 2: Create Base Controller (Safe)
1. Create `app/controllers/prompt_tracker/testing/datasets_controller_base.rb`
2. Extract all common logic
3. Don't change existing controllers yet

### Step 3: Update Controllers (Medium Risk)
1. Update `DatasetsController` to inherit from base
2. Update `AssistantDatasetsController` to inherit from base
3. Test both routes still work

### Step 4: Create Unified Partials (Safe)
1. Create `_dataset_card.html.erb`
2. Create `_empty_state.html.erb`
3. Don't use them yet

### Step 5: Update PromptVersion Views (Medium Risk)
1. Update `index.html.erb` to use helpers and new partials
2. Update `new.html.erb` to use helpers
3. Update `edit.html.erb` to use helpers
4. Update `show.html.erb` to use helpers
5. Update `_form.html.erb` to be schema-driven
6. Test thoroughly

### Step 6: Point Assistant Controller to Unified Views (High Risk)
1. Update `AssistantDatasetsController` to use `datasets` views (not `openai/assistant_datasets`)
2. Test thoroughly

### Step 7: Delete Old Views (Final)
1. Delete `app/views/prompt_tracker/testing/openai/assistant_datasets/` directory
2. Celebrate! 🎉

---

## Testing Strategy

### Manual Testing Checklist

**For PromptVersion Datasets**:
- [ ] Index page loads
- [ ] Can create new dataset
- [ ] Can edit dataset
- [ ] Can delete dataset
- [ ] Can view dataset
- [ ] Can add row manually
- [ ] Can generate rows with AI
- [ ] Breadcrumbs work
- [ ] All links work

**For Assistant Datasets**:
- [ ] Index page loads
- [ ] Can create new dataset
- [ ] Can edit dataset
- [ ] Can delete dataset
- [ ] Can view dataset
- [ ] Can add row manually
- [ ] Can generate rows with AI
- [ ] Breadcrumbs work
- [ ] All links work

### Automated Testing

Update controller specs:
- `spec/controllers/prompt_tracker/testing/datasets_controller_spec.rb`
- `spec/controllers/prompt_tracker/testing/openai/assistant_datasets_controller_spec.rb`

Both should test the same behavior (inherited from base).

---

## Key Files Summary

### New Files
- `app/helpers/prompt_tracker/datasets_helper.rb` - Polymorphic path helpers
- `app/controllers/prompt_tracker/testing/datasets_controller_base.rb` - Shared controller logic
- `app/views/prompt_tracker/testing/datasets/_dataset_card.html.erb` - Unified card partial
- `app/views/prompt_tracker/testing/datasets/_empty_state.html.erb` - Unified empty state

### Modified Files
- `app/controllers/prompt_tracker/testing/datasets_controller.rb` - Inherit from base
- `app/controllers/prompt_tracker/testing/openai/assistant_datasets_controller.rb` - Inherit from base
- `app/views/prompt_tracker/testing/datasets/index.html.erb` - Use helpers, no branching
- `app/views/prompt_tracker/testing/datasets/new.html.erb` - Use helpers
- `app/views/prompt_tracker/testing/datasets/edit.html.erb` - Use helpers
- `app/views/prompt_tracker/testing/datasets/show.html.erb` - Use helpers
- `app/views/prompt_tracker/testing/datasets/_form.html.erb` - Schema-driven, no branching

### Deleted Files
- `app/views/prompt_tracker/testing/openai/assistant_datasets/*.html.erb` (all views)

---

## Success Criteria

✅ **No type checking in views** - No `if testable.is_a?(PromptVersion)` anywhere
✅ **Single source of truth** - One set of views for all testables
✅ **DRY controllers** - 95% of logic in base class
✅ **Consistent UX** - Card layout for all testables
✅ **All tests pass** - Both controller specs green
✅ **Manual testing passes** - All features work for both testables

---

## Testing Plan

### Phase 1: Unit Testing (Helpers)

**Test File**: `spec/helpers/prompt_tracker/datasets_helper_spec.rb`

Test all helper methods with both testable types:

```ruby
RSpec.describe PromptTracker::DatasetsHelper do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt) }
  let(:assistant) { create(:assistant) }
  let(:version_dataset) { create(:dataset, testable: version) }
  let(:assistant_dataset) { create(:dataset, testable: assistant) }

  describe "#testable_name" do
    it "returns prompt name for PromptVersion" do
      expect(helper.testable_name(version)).to eq(prompt.name)
    end

    it "returns assistant name for Assistant" do
      expect(helper.testable_name(assistant)).to eq(assistant.name)
    end
  end

  describe "#testable_badge" do
    it "returns version badge for PromptVersion" do
      badge = helper.testable_badge(version)
      expect(badge).to include("v#{version.version_number}")
      expect(badge).to include("badge")
    end

    it "returns empty string for Assistant" do
      expect(helper.testable_badge(assistant)).to eq("")
    end
  end

  describe "#dataset_path" do
    it "generates correct path for PromptVersion dataset" do
      path = helper.dataset_path(version_dataset)
      expect(path).to eq(testing_prompt_prompt_version_dataset_path(prompt, version, version_dataset))
    end

    it "generates correct path for Assistant dataset" do
      path = helper.dataset_path(assistant_dataset)
      expect(path).to eq(testing_openai_assistant_dataset_path(assistant, assistant_dataset))
    end

    it "generates edit path when action: :edit" do
      path = helper.dataset_path(version_dataset, action: :edit)
      expect(path).to eq(edit_testing_prompt_prompt_version_dataset_path(prompt, version, version_dataset))
    end
  end

  describe "#datasets_index_path" do
    it "generates correct path for PromptVersion" do
      path = helper.datasets_index_path(version)
      expect(path).to eq(testing_prompt_prompt_version_datasets_path(prompt, version))
    end

    it "generates correct path for Assistant" do
      path = helper.datasets_index_path(assistant)
      expect(path).to eq(testing_openai_assistant_datasets_path(assistant))
    end
  end

  describe "#testable_show_path" do
    it "generates correct path for PromptVersion" do
      path = helper.testable_show_path(version)
      expect(path).to eq(testing_prompt_prompt_version_path(prompt, version))
    end

    it "generates correct path for Assistant" do
      path = helper.testable_show_path(assistant)
      expect(path).to eq(testing_openai_assistant_path(assistant))
    end
  end
end
```

### Phase 2: Controller Testing (Base + Subclasses)

**Test File**: `spec/controllers/prompt_tracker/testing/datasets_controller_spec.rb`

Test that PromptVersion datasets controller works:

```ruby
RSpec.describe PromptTracker::Testing::DatasetsController do
  let(:prompt) { create(:prompt) }
  let(:version) { create(:prompt_version, prompt: prompt) }
  let(:dataset) { create(:dataset, testable: version) }

  describe "GET #index" do
    it "sets @testable to the version" do
      get :index, params: { prompt_id: prompt.id, prompt_version_id: version.id }
      expect(assigns(:testable)).to eq(version)
    end

    it "loads datasets for the version" do
      dataset # create it
      get :index, params: { prompt_id: prompt.id, prompt_version_id: version.id }
      expect(assigns(:datasets)).to include(dataset)
    end
  end

  describe "POST #create" do
    it "creates dataset with testable set to version" do
      expect {
        post :create, params: {
          prompt_id: prompt.id,
          prompt_version_id: version.id,
          dataset: { name: "Test Dataset", description: "Test" }
        }
      }.to change(PromptTracker::Dataset, :count).by(1)

      expect(PromptTracker::Dataset.last.testable).to eq(version)
    end
  end

  # Test all CRUD actions...
end
```

**Test File**: `spec/controllers/prompt_tracker/testing/openai/assistant_datasets_controller_spec.rb`

Test that Assistant datasets controller works (same tests, different testable):

```ruby
RSpec.describe PromptTracker::Testing::Openai::AssistantDatasetsController do
  let(:assistant) { create(:assistant) }
  let(:dataset) { create(:dataset, testable: assistant) }

  describe "GET #index" do
    it "sets @testable to the assistant" do
      get :index, params: { assistant_id: assistant.id }
      expect(assigns(:testable)).to eq(assistant)
    end

    it "loads datasets for the assistant" do
      dataset # create it
      get :index, params: { assistant_id: assistant.id }
      expect(assigns(:datasets)).to include(dataset)
    end
  end

  describe "POST #create" do
    it "creates dataset with testable set to assistant" do
      expect {
        post :create, params: {
          assistant_id: assistant.id,
          dataset: { name: "Test Dataset", description: "Test" }
        }
      }.to change(PromptTracker::Dataset, :count).by(1)

      expect(PromptTracker::Dataset.last.testable).to eq(assistant)
    end
  end

  # Test all CRUD actions...
end
```

### Phase 3: Integration Testing (System Specs)

**Test File**: `spec/system/prompt_tracker/datasets_spec.rb`

Test the full user flow for both testable types:

```ruby
RSpec.describe "Datasets", type: :system do
  context "with PromptVersion testable" do
    let(:prompt) { create(:prompt) }
    let(:version) { create(:prompt_version, prompt: prompt) }

    it "allows creating, viewing, editing, and deleting datasets" do
      # Visit index
      visit testing_prompt_prompt_version_datasets_path(prompt, version)
      expect(page).to have_content("Datasets")
      expect(page).to have_content(prompt.name)

      # Create new dataset
      click_link "New Dataset"
      fill_in "Name", with: "Test Dataset"
      fill_in "Description", with: "Test description"
      click_button "Create Dataset"

      expect(page).to have_content("Dataset created successfully")
      expect(page).to have_content("Test Dataset")

      # View dataset
      click_link "View"
      expect(page).to have_content("Test Dataset")
      expect(page).to have_content("Test description")

      # Edit dataset
      click_link "Edit"
      fill_in "Name", with: "Updated Dataset"
      click_button "Update Dataset"

      expect(page).to have_content("Dataset updated successfully")
      expect(page).to have_content("Updated Dataset")

      # Delete dataset
      click_button "Delete"
      expect(page).to have_content("Dataset deleted successfully")
      expect(page).not_to have_content("Updated Dataset")
    end

    it "displays breadcrumbs correctly" do
      visit testing_prompt_prompt_version_datasets_path(prompt, version)

      within(".breadcrumb") do
        expect(page).to have_link(prompt.name)
        expect(page).to have_content("Datasets")
      end
    end

    it "uses card layout" do
      dataset = create(:dataset, testable: version, name: "Card Test")
      visit testing_prompt_prompt_version_datasets_path(prompt, version)

      expect(page).to have_css(".card", text: "Card Test")
      expect(page).not_to have_css("table")
    end
  end

  context "with Assistant testable" do
    let(:assistant) { create(:assistant) }

    it "allows creating, viewing, editing, and deleting datasets" do
      # Visit index
      visit testing_openai_assistant_datasets_path(assistant)
      expect(page).to have_content("Datasets")
      expect(page).to have_content(assistant.name)

      # Create new dataset
      click_link "New Dataset"
      fill_in "Name", with: "Test Dataset"
      fill_in "Description", with: "Test description"
      click_button "Create Dataset"

      expect(page).to have_content("Dataset created successfully")
      expect(page).to have_content("Test Dataset")

      # View dataset
      click_link "View"
      expect(page).to have_content("Test Dataset")
      expect(page).to have_content("Test description")

      # Edit dataset
      click_link "Edit"
      fill_in "Name", with: "Updated Dataset"
      click_button "Update Dataset"

      expect(page).to have_content("Dataset updated successfully")
      expect(page).to have_content("Updated Dataset")

      # Delete dataset
      click_button "Delete"
      expect(page).to have_content("Dataset deleted successfully")
      expect(page).not_to have_content("Updated Dataset")
    end

    it "displays breadcrumbs correctly" do
      visit testing_openai_assistant_datasets_path(assistant)

      within(".breadcrumb") do
        expect(page).to have_link(assistant.name)
        expect(page).to have_content("Datasets")
      end
    end

    it "uses card layout (not table)" do
      dataset = create(:dataset, testable: assistant, name: "Card Test")
      visit testing_openai_assistant_datasets_path(assistant)

      expect(page).to have_css(".card", text: "Card Test")
      expect(page).not_to have_css("table")
    end
  end
end
```

### Phase 4: Manual Testing Checklist

After implementation, manually test both flows:

#### PromptVersion Datasets
- [ ] Navigate to a prompt version
- [ ] Click "Datasets" link
- [ ] Verify breadcrumbs show: Testing > [Prompt Name] > Datasets
- [ ] Verify card layout (not table)
- [ ] Click "New Dataset"
- [ ] Create a dataset with name and description
- [ ] Verify schema info displays correctly
- [ ] Click "View" on the dataset
- [ ] Verify all dataset details display
- [ ] Click "Add Row" and add a manual row
- [ ] Click "Generate Rows" and generate AI rows
- [ ] Click "Edit" and update the dataset
- [ ] Click "Delete" and confirm deletion
- [ ] Verify no errors in browser console

#### Assistant Datasets
- [ ] Navigate to an assistant
- [ ] Click "Datasets" link
- [ ] Verify breadcrumbs show: Testing > OpenAI Assistants > [Assistant Name] > Datasets
- [ ] Verify card layout (not table)
- [ ] Click "New Dataset"
- [ ] Create a dataset with name and description
- [ ] Verify schema info displays correctly (interlocutor_simulation_prompt, max_turns)
- [ ] Click "View" on the dataset
- [ ] Verify all dataset details display
- [ ] Click "Add Row" and add a manual row
- [ ] Click "Generate Rows" and generate AI rows
- [ ] Click "Edit" and update the dataset
- [ ] Click "Delete" and confirm deletion
- [ ] Verify no errors in browser console

### Phase 5: Regression Testing

Run existing test suite to ensure nothing broke:

```bash
# Run all dataset-related specs
bundle exec rspec spec/models/prompt_tracker/dataset_spec.rb
bundle exec rspec spec/models/prompt_tracker/dataset_row_spec.rb
bundle exec rspec spec/controllers/prompt_tracker/testing/datasets_controller_spec.rb
bundle exec rspec spec/controllers/prompt_tracker/testing/openai/assistant_datasets_controller_spec.rb

# Run all system specs
bundle exec rspec spec/system/prompt_tracker/

# Run full suite
bundle exec rspec
```

### Testing Success Criteria

✅ All helper specs pass (100% coverage of helper methods)
✅ All controller specs pass (both PromptVersion and Assistant)
✅ All system specs pass (full user flows work)
✅ Manual testing checklist complete (no UI bugs)
✅ No regressions in existing tests
✅ No errors in browser console
✅ No type checking (`is_a?`, `kind_of?`) in views
✅ Both testable types use identical views

---

## Rollback Plan

If something goes wrong:
1. Revert controller changes (restore inheritance)
2. Revert view changes (git checkout)
3. Assistant views still exist as backup
4. No data migration needed - purely code changes

---

## Future Extensibility

This pattern makes it trivial to add new testable types:

```ruby
# Add a new testable type
class Workflow < ApplicationRecord
  has_many :datasets, as: :testable
end

# Create a controller
class WorkflowDatasetsController < DatasetsControllerBase
  private

  def set_testable
    @workflow = Workflow.find(params[:workflow_id])
    @testable = @workflow
  end
end

# Add routes
resources :workflows do
  resources :datasets, controller: "workflow_datasets"
end

# Add helper case
def testable_name(testable)
  case testable
  when PromptVersion then testable.prompt.name
  when Assistant then testable.name
  when Workflow then testable.name  # NEW
  end
end
```

**That's it!** No view changes needed. The schema-driven approach works for any testable.

---

## Estimated Time

- Phase 1 (Helper): 1 hour
- Phase 2 (Base Controller): 1 hour
- Phase 3 (Update Controllers): 30 minutes
- Phase 4 (Unified Views): 3 hours
- Phase 5 (Delete Old Views): 15 minutes
- Phase 6 (Testing): 2 hours

**Total: ~8 hours**

---

## Questions to Resolve

1. ✅ Card vs Table layout? → **Use cards for all**
2. ✅ Branching in views? → **No branching, use helpers**
3. ✅ Breadcrumbs? → **Polymorphic helpers**
4. ✅ Schema differences? → **Schema-driven rendering**

All resolved! Ready to implement. 🚀
