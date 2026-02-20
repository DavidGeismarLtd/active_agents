# Version Management PRD

## Overview

This PRD defines improvements to PromptTracker's version management system. The goal is to ensure version integrity while providing clear UX feedback about when and why new versions are created.

## Current Problems

1. **Only `user_prompt` is protected from changes** once LLM responses exist
2. **FileSyncService is unused** - YAML file syncing is not needed
3. **No UI feedback** about version management rules
4. **Structural changes can silently break** datasets and tests

## Design Principles

### Version States

A PromptVersion can be in one of three states based on its associations:

| State | Condition | Behavior |
|-------|-----------|----------|
| **Development** | No tests, no datasets, no llm_responses | Free editing of all fields |
| **Testing** | Has tests OR datasets (no llm_responses) | Structural changes force new version |
| **Production** | Has llm_responses | All changes force new version (immutable) |

### Field Categories

| Category | Fields | Can Edit in Development? | Can Edit in Testing? | Can Edit in Production? |
|----------|--------|-------------------------|---------------------|------------------------|
| **Content** | `user_prompt`, `system_prompt`, `notes` | ✅ Yes | ✅ Yes | ❌ No (new version) |
| **Structural** | `model_config.provider`, `model_config.api`, `model_config.model`, `model_config.tool_config`, `variables_schema`, `response_schema` | ✅ Yes | ❌ No (new version) | ❌ No (new version) |
| **Tuning** | `model_config.temperature`, `model_config.max_tokens` | ✅ Yes | ✅ Yes | ❌ No (new version) |

### Rationale

- **Content fields** (prompts): These are what we're iterating on. Tests exist to validate prompt changes.
- **Structural fields**: Break dataset compatibility (variables), change API behavior (provider/api/model/tools), or change expected output format (response_schema).
- **Tuning fields**: Don't break compatibility, just affect output quality.

---

## Task 1: Remove FileSyncService and Related Code

### Files to Delete

1. `app/services/prompt_tracker/file_sync_service.rb`

### Files to Modify

#### `lib/tasks/prompt_tracker_tasks.rake`

Remove these tasks:
- `prompt_tracker:sync`
- `prompt_tracker:sync:force`
- `prompt_tracker:validate`
- `prompt_tracker:list`

Keep:
- `prompt_tracker:stats` (useful, doesn't depend on FileSyncService)

#### `lib/prompt_tracker/configuration.rb`

Remove:
- `prompts_path` accessor
- `default_prompts_path` method

#### `spec/services/prompt_tracker/file_sync_service_spec.rb` (if exists)

Delete the spec file.

---

## Task 2: Add Version State Helper Methods to PromptVersion

Add these methods to `app/models/prompt_tracker/prompt_version.rb`:

```ruby
# Constants for structural fields that force new version in testing state
STRUCTURAL_MODEL_CONFIG_KEYS = %w[provider api model tool_config].freeze

# Check if version is in development state (no tests, datasets, or responses)
def development_state?
  !has_responses? && !has_tests? && !has_datasets?
end

# Check if version is in testing state (has tests or datasets, no responses)
def testing_state?
  !has_responses? && (has_tests? || has_datasets?)
end

# Check if version is in production state (has responses)
def production_state?
  has_responses?
end

# Check if version has any tests
def has_tests?
  tests.exists?
end

# Check if version has any datasets
def has_datasets?
  datasets.exists?
end

# Check if structural fields have changed
def structural_fields_changed?
  return true if variables_schema_changed?
  return true if response_schema_changed?
  return true if structural_model_config_changed?
  false
end

# Check if structural model_config keys have changed
def structural_model_config_changed?
  return false unless model_config_changed?

  old_config = model_config_was || {}
  new_config = model_config || {}

  STRUCTURAL_MODEL_CONFIG_KEYS.any? do |key|
    old_config[key] != new_config[key]
  end
end
```

---

## Task 3: Add Validation for Immutability Rules

Add to `app/models/prompt_tracker/prompt_version.rb`:

```ruby
validate :enforce_version_immutability, on: :update

private

def enforce_version_immutability
  if production_state?
    # Production: no changes to any significant field
    if user_prompt_changed? || system_prompt_changed? ||
       model_config_changed? || variables_schema_changed? || response_schema_changed?
      errors.add(:base, "Cannot modify version with production responses. Create a new version instead.")
    end
  elsif testing_state?
    # Testing: only structural fields are blocked
    if structural_fields_changed?
      errors.add(:base, "Cannot modify structural fields (provider, api, model, tools, variables, response_schema) when tests or datasets exist. Create a new version instead.")
    end
  end
  # Development state: all changes allowed
end
```

Remove the old validation:
```ruby
# DELETE THIS:
validate :user_prompt_immutable_if_responses_exist, on: :update

# AND DELETE THIS METHOD:
def user_prompt_immutable_if_responses_exist
  ...
end
```

---

## Task 4: Update PlaygroundSaveService

Modify `app/services/prompt_tracker/playground_save_service.rb` to handle version management:

```ruby
class PlaygroundSaveService
  Result = Data.define(:success?, :action, :prompt, :version, :errors, :version_created_reason)

  def call
    if prompt
      determine_save_action
    else
      create_new_prompt
    end
  end

  private

  def determine_save_action
    if prompt_version.nil?
      create_new_version(reason: nil)
    elsif must_create_new_version?
      create_new_version(reason: version_creation_reason)
    else
      update_existing_version
    end
  end

  def must_create_new_version?
    return true if prompt_version.production_state?
    return true if prompt_version.testing_state? && structural_fields_changing?
    false
  end

  def structural_fields_changing?
    old_config = prompt_version.model_config || {}
    new_config = params[:model_config] || {}

    # Check structural model_config keys
    %w[provider api model tool_config].any? { |key| old_config[key] != new_config[key] } ||
      prompt_version.variables_schema != params[:variables_schema] ||
      prompt_version.response_schema != params[:response_schema]
  end

  def version_creation_reason
    if prompt_version.production_state?
      :production_immutable
    elsif prompt_version.testing_state?
      :structural_change_with_tests
    end
  end

  def create_new_version(reason:)
    version = prompt.prompt_versions.build(version_attributes.merge(status: "draft"))

    if version.save
      Result.new(
        success?: true,
        action: :created,
        prompt: prompt,
        version: version,
        errors: [],
        version_created_reason: reason
      )
    else
      failure_result(version.errors.full_messages)
    end
  end
end
```

---

## Task 5: UI Feedback in Playground

### 5.1 Add Version State Badge

In `app/views/prompt_tracker/testing/playground/_header.html.erb` or similar, show version state:

```erb
<% if version %>
  <span class="badge <%= version_state_badge_class(version) %>">
    <%= version_state_label(version) %>
  </span>

  <% if version.testing_state? %>
    <small class="text-muted ms-2">
      <i class="bi bi-info-circle"></i>
      Structural changes will create a new version
    </small>
  <% elsif version.production_state? %>
    <small class="text-muted ms-2">
      <i class="bi bi-lock"></i>
      Any changes will create a new version
    </small>
  <% end %>
<% end %>
```

### 5.2 Add Helper Methods

In `app/helpers/prompt_tracker/playground_helper.rb`:

```ruby
def version_state_label(version)
  if version.production_state?
    "Production"
  elsif version.testing_state?
    "Testing"
  else
    "Development"
  end
end

def version_state_badge_class(version)
  if version.production_state?
    "bg-danger"
  elsif version.testing_state?
    "bg-warning text-dark"
  else
    "bg-success"
  end
end
```

### 5.3 Add Save Confirmation Modal

When saving would create a new version, show a confirmation modal explaining why.

Create `app/views/prompt_tracker/testing/playground/_version_alert_modal.html.erb`:

```erb
<div class="modal fade" id="versionAlertModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">
          <i class="bi bi-exclamation-triangle text-warning"></i>
          New Version Will Be Created
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
      </div>
      <div class="modal-body">
        <div id="version-alert-production" class="d-none">
          <p>This version has <strong>production responses</strong> and cannot be modified.</p>
          <p>Saving will create a <strong>new draft version</strong> with your changes.</p>
        </div>
        <div id="version-alert-structural" class="d-none">
          <p>This version has <strong>tests or datasets</strong> attached.</p>
          <p>You're changing <strong>structural fields</strong> (provider, API, model, tools, variables, or response schema) which would break existing tests/datasets.</p>
          <p>Saving will create a <strong>new draft version</strong> with your changes.</p>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
        <button type="button" class="btn btn-primary" id="confirmNewVersion">
          Create New Version
        </button>
      </div>
    </div>
  </div>
</div>
```

### 5.4 Update Stimulus Controller for Save

In the playground Stimulus controller, add logic to check if save would create new version:

```javascript
// Before saving, check if we need to show the modal
async checkVersionImpact() {
  const response = await fetch(this.checkVersionImpactUrlValue, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
    },
    body: JSON.stringify(this.buildSaveParams())
  })

  const result = await response.json()

  if (result.will_create_new_version) {
    this.showVersionAlertModal(result.reason)
  } else {
    this.performSave()
  }
}

showVersionAlertModal(reason) {
  // Show appropriate message based on reason
  document.getElementById('version-alert-production').classList.toggle('d-none', reason !== 'production_immutable')
  document.getElementById('version-alert-structural').classList.toggle('d-none', reason !== 'structural_change_with_tests')

  const modal = new bootstrap.Modal(document.getElementById('versionAlertModal'))
  modal.show()
}
```

### 5.5 Add Check Endpoint

Add to `app/controllers/prompt_tracker/testing/playground_controller.rb`:

```ruby
# POST /playground/check_version_impact
def check_version_impact
  will_create = false
  reason = nil

  if @prompt_version
    if @prompt_version.production_state?
      will_create = true
      reason = 'production_immutable'
    elsif @prompt_version.testing_state? && structural_fields_changing?
      will_create = true
      reason = 'structural_change_with_tests'
    end
  end

  render json: { will_create_new_version: will_create, reason: reason }
end

private

def structural_fields_changing?
  old_config = @prompt_version.model_config || {}
  new_config = playground_params[:model_config] || {}

  %w[provider api model tool_config].any? { |key| old_config[key] != new_config[key] } ||
    @prompt_version.variables_schema != playground_params[:variables_schema] ||
    @prompt_version.response_schema != playground_params[:response_schema]
end
```

---

## Task 6: Flash Message After Save

When a new version is created due to version management rules, show an explanatory flash message.

In the save action response:

```ruby
if result.version_created_reason == :production_immutable
  flash[:notice] = "Created new version v#{result.version.version_number} because the previous version has production responses."
elsif result.version_created_reason == :structural_change_with_tests
  flash[:notice] = "Created new version v#{result.version.version_number} because structural fields changed while tests/datasets existed."
else
  flash[:notice] = "Version saved successfully."
end
```

---

## Implementation Order

1. **Task 1**: Remove FileSyncService (cleanup)
2. **Task 2**: Add version state helper methods
3. **Task 3**: Add immutability validations
4. **Task 4**: Update PlaygroundSaveService
5. **Task 5**: UI feedback (badge, modal, controller)
6. **Task 6**: Flash messages

---

## Testing Requirements

### Unit Tests

1. `spec/models/prompt_tracker/prompt_version_spec.rb`
   - Test `development_state?`, `testing_state?`, `production_state?`
   - Test `structural_fields_changed?`
   - Test immutability validations block correctly
   - Test immutability validations allow correctly

2. `spec/services/prompt_tracker/playground_save_service_spec.rb`
   - Test creates new version when production state
   - Test creates new version when testing state + structural change
   - Test updates existing when testing state + content change only
   - Test updates existing when development state

### Integration Tests

1. Playground save flow with version states
2. UI displays correct state badges
3. Modal appears when appropriate

---

## Summary

| Change Type | Development | Testing | Production |
|-------------|-------------|---------|------------|
| Content (prompts) | ✅ Update | ✅ Update | 🆕 New Version |
| Structural (api, model, vars) | ✅ Update | 🆕 New Version | 🆕 New Version |
| Tuning (temperature) | ✅ Update | ✅ Update | 🆕 New Version |

**User always knows what will happen before saving.**
