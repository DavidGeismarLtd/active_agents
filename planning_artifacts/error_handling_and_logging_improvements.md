# Error Handling and Logging Improvements

## Problems Fixed

### Problem 1: Validation Error (Task Run #53)
```
Validation failed: Function executions is invalid
```

This error occurred when trying to create a `FunctionExecution` record, but the error message was not clear about what validation failed.

### Problem 2: Unknown Attribute Error (Task Run #54)
```
unknown attribute 'context' for PromptTracker::FunctionExecution.
```

The code was trying to set a `context` attribute that doesn't exist in the database schema.

### Problem 3: NOT NULL Constraint Violation (Task Run #55)
```
PG::NotNullViolation: ERROR:  null value in column "function_definition_id" of relation "prompt_tracker_function_executions" violates not-null constraint
```

The database had a `NOT NULL` constraint on `function_definition_id`, but planning functions don't have a corresponding `FunctionDefinition` record (they're virtual functions).

## Root Cause Analysis

### Problem 1: Arguments Validation
The `FunctionExecution` model had a validation:
```ruby
validates :arguments, presence: true
```

This validation treats empty hashes `{}` as "blank" and rejects them. However, when functions are called with no parameters (especially planning functions like `get_plan`), the `arguments` should be an empty hash `{}`, not `nil`.

The validation error was happening silently, and when the task run tried to save at the end, it failed because it had invalid associated `function_executions`.

### Problem 2: Non-existent Context Column
The code was trying to set a `context:` attribute when creating `FunctionExecution` records:
```ruby
PromptTracker::FunctionExecution.create!(
  # ... other attributes ...
  context: {
    function_type: "planning",
    function_name: function_name,
    iteration: @iteration_count
  }
)
```

However, the `function_executions` table does NOT have a `context` column. The available columns are:
- `function_definition_id`, `arguments`, `result`, `success`, `error_message`
- `execution_time_ms`, `executed_at`, `deployed_agent_id`, `agent_conversation_id`
- `task_run_id`, `planning_step_id`

### Problem 3: Database Constraint Mismatch
The model marked `function_definition` as optional:
```ruby
belongs_to :function_definition, optional: true  # Optional for virtual/planning functions
```

But the database schema had a `NOT NULL` constraint:
```ruby
t.bigint :function_definition_id, null: false
```

This meant that even though the model allowed `nil`, the database rejected it when trying to save planning function executions.

## Solutions Implemented

### 1. Enhanced Logging in Function Execution

**File: `app/services/prompt_tracker/task_agent_runtime_service.rb`**

#### A. Executor Lambda (lines 324-328)
Added logging when the executor is called:
```ruby
@logger.info "[TaskAgentRuntimeService] 🔧 Executor called for: #{function_name}"
@logger.info "[TaskAgentRuntimeService] 🔧 Arguments received: #{arguments.inspect}"
@logger.info "[TaskAgentRuntimeService] 🔧 Arguments class: #{arguments.class}"
```

#### B. Planning Function Execution (lines 473-544)
Added detailed logging:
- Arguments inspection (value, class, blank?)
- FunctionExecution creation parameters
- Validation errors if any

```ruby
@logger.info "[TaskAgentRuntimeService] 🎯 Arguments: #{arguments.inspect}"
@logger.info "[TaskAgentRuntimeService] 🎯 Arguments class: #{arguments.class}"
@logger.info "[TaskAgentRuntimeService] 🎯 Arguments blank?: #{arguments.blank?}"

# ... after creating FunctionExecution ...

unless function_execution.valid?
  @logger.error "[TaskAgentRuntimeService] ❌ FunctionExecution validation failed!"
  @logger.error "[TaskAgentRuntimeService] ❌ Errors: #{function_execution.errors.full_messages.inspect}"
  function_execution.errors.details.each do |field, errors|
    @logger.error "[TaskAgentRuntimeService] ❌   #{field}: #{errors.inspect}"
  end
end
```

#### C. Regular Function Execution (lines 402-444)
Same logging pattern for regular functions.

#### D. Arguments Normalization
Ensure `arguments` is always a Hash:
```ruby
# Ensure arguments is always a Hash (never nil)
normalized_arguments = arguments.is_a?(Hash) ? arguments : {}
```

This prevents validation errors by guaranteeing `arguments` is always a Hash (even if empty).

#### E. Removed Non-existent `context` Attribute
Changed from:
```ruby
PromptTracker::FunctionExecution.new(
  # ... other attributes ...
  context: {
    function_type: "planning",
    function_name: function_name,
    iteration: @iteration_count
  }
)
```

To:
```ruby
PromptTracker::FunctionExecution.new(
  # ... other attributes ...
  planning_step_id: nil  # Will be populated when we link to specific plan steps
)
```

The `context` column doesn't exist in the schema. We use `planning_step_id` instead to link executions to plan steps.

#### F. Made `function_definition_id` Nullable in Database

**Migration Created:**
`db/migrate/20260324084310_make_function_definition_id_nullable_in_function_executions.rb`

**SQL Executed:**
```sql
ALTER TABLE prompt_tracker_function_executions
ALTER COLUMN function_definition_id DROP NOT NULL;
```

This allows planning functions (which don't have a `FunctionDefinition` record) to be saved with `function_definition_id = NULL`.

#### G. Removed `presence: true` Validation on Arguments

**File: `app/models/prompt_tracker/function_execution.rb`**

Changed from:
```ruby
validates :arguments, presence: true
```

To:
```ruby
# Note: arguments can be an empty hash {} for functions with no parameters
# We only validate that it's not nil (which is handled by the database default)
```

And updated the custom validation:
```ruby
def arguments_must_be_hash
  # Arguments cannot be nil (database has NOT NULL constraint with default {})
  # But it can be an empty hash {} for functions with no parameters
  if arguments.nil?
    errors.add(:arguments, "cannot be nil")
    return
  end

  unless arguments.is_a?(Hash)
    errors.add(:arguments, "must be a Hash")
  end
end
```

This allows functions with no parameters to have `arguments = {}` without triggering a validation error.

#### H. Added `display_name` Helper Method to FunctionExecution

**File: `app/models/prompt_tracker/function_execution.rb`**

Added a helper method to get the function name for display purposes:
```ruby
def display_name
  return function_definition.name if function_definition.present?

  # For planning functions, infer from result structure
  if result.is_a?(Hash)
    return "create_plan" if result.key?("plan") && result["plan"].is_a?(Hash) && result["plan"].key?("goal")
    return "get_plan" if result.key?("plan") && result["plan"].is_a?(Hash)
    return "update_step" if result.key?("step_id")
    return "mark_task_complete" if result.key?("summary")
  end

  "planning_function"
end
```

**File: `app/views/prompt_tracker/task_runs/_function_execution_card.html.erb`**

Updated the view to use the helper method instead of the non-existent `context` attribute:
```erb
<% if execution.function_definition.present? %>
  <i class="bi bi-code-square"></i> Function: <%= execution.function_definition.name %>
<% else %>
  <i class="bi bi-lightbulb text-primary"></i> Planning: <%= execution.display_name %>
<% end %>
```

### 2. Improved Error Handling in TaskAgentRuntimeService

**File: `app/services/prompt_tracker/task_agent_runtime_service.rb` (lines 103-126)**

Enhanced the rescue block:
```ruby
rescue StandardError => e
  @logger.error "[TaskAgentRuntimeService] ❌ Task run #{task_run.id} failed with exception: #{e.class.name}"
  @logger.error "[TaskAgentRuntimeService] ❌ Error message: #{e.message}"
  @logger.error "[TaskAgentRuntimeService] ❌ Backtrace:"
  e.backtrace.first(20).each do |line|
    @logger.error "[TaskAgentRuntimeService] ❌   #{line}"
  end

  # Mark task as failed (don't re-raise - we want to handle gracefully)
  begin
    task_run.fail!(error: e.message)
  rescue StandardError => fail_error
    @logger.error "[TaskAgentRuntimeService] ❌ Failed to mark task as failed: #{fail_error.message}"
    # Try to update status directly without validation
    task_run.update_columns(
      status: "failed",
      error_message: e.message,
      completed_at: Time.current
    )
  end

  { success: false, error: e.message }
end
```

**Key improvements:**
- Log exception class name (not just message)
- Log 20 lines of backtrace (was 10)
- Gracefully handle case where `task_run.fail!` itself fails
- Use `update_columns` as fallback to bypass validations
- **Do NOT re-raise** - return error hash instead

### 3. No Retries in ExecuteTaskAgentJob

**File: `app/jobs/prompt_tracker/execute_task_agent_job.rb` (lines 77-111)**

**REMOVED** the `raise` statement that was causing Sidekiq to retry:

```ruby
rescue StandardError => e
  # ... logging ...

  # Mark task run as failed if it exists and isn't already in a terminal state
  if task_run && !task_run.finished?
    begin
      task_run.fail!(error: e.message)
    rescue StandardError => fail_error
      # ... handle failure to mark as failed ...
    end
  end

  # DO NOT re-raise - we want to handle errors gracefully without retries
  # The task run is already marked as failed, no need to retry
ensure
  close_task_logger
end
```

**Key changes:**
- Removed `raise` statement (line 90 in old code)
- Added nested rescue for `task_run.fail!` failures
- Added comment explaining why we don't retry
- Enhanced logging with exception class name and more backtrace lines

## Benefits

1. ✅ **Detailed Logging**: See exactly what arguments are being passed to functions
2. ✅ **Validation Visibility**: See which validations fail and why
3. ✅ **No Silent Failures**: All errors are logged with full context
4. ✅ **No Retries**: Failed tasks are marked as failed immediately without retry attempts
5. ✅ **Graceful Degradation**: If marking as failed fails, use `update_columns` as fallback
6. ✅ **Arguments Normalization**: Prevent nil arguments from causing validation errors
7. ✅ **Database Schema Fixed**: `function_definition_id` is now nullable, allowing planning functions to be saved

## Testing

Run a task execution and check the logs:

```bash
rails runner test_responses_api_tracking.rb
```

Or manually:
```ruby
pv = PromptTracker::PromptVersion.find(67)
agent = PromptTracker::DeployedAgent.find_by(prompt_version: pv)
PromptTracker::ExecuteTaskAgentJob.perform_now(agent.id)
```

Check the logs at:
- `log/task_executions/task_run_XX.log` (detailed task execution log)
- Sidekiq logs (for job-level errors)

Look for:
- 🔧 Executor logs showing function calls and arguments
- 🎯 Planning function logs showing argument normalization
- ❌ Validation error logs if any validations fail
- ✅ Success logs when FunctionExecution is saved

## Related Files

- `app/services/prompt_tracker/task_agent_runtime_service.rb`
- `app/jobs/prompt_tracker/execute_task_agent_job.rb`
- `app/models/prompt_tracker/function_execution.rb` (validation rules)
