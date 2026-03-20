# Explicit Deployment Flow

## Overview

Functions now require explicit deployment to AWS Lambda before they can be tested or executed. This gives users visibility and control over when their functions go live.

## Database Schema

### New Columns in `function_definitions`

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `lambda_function_name` | string | null | AWS Lambda function name (e.g., "prompt-tracker-abc123") |
| `deployment_status` | string | "not_deployed" | Current deployment state |
| `deployed_at` | datetime | null | Timestamp of last successful deployment |
| `deployment_error` | text | null | Error message if deployment failed |

### Deployment Statuses

- **`not_deployed`** - Function exists only in database, not on AWS
- **`deploying`** - Deployment in progress
- **`deployed`** - Function is live on AWS Lambda
- **`deployment_failed`** - Deployment encountered an error

## User Flow

### 1. Create Function
```
User fills form → Click "Create" → Function saved to DB
Status: not_deployed ❌
```

### 2. Deploy to Lambda
```
User clicks "Publish to Lambda" → LambdaAdapter.deploy() → AWS Lambda created
Status: deploying → deployed ✅
```

### 3. Test Function
```
User clicks "Run Test" → Check if deployed → Invoke Lambda → Show results
If not deployed: Show warning ⚠️
```

### 4. Undeploy (Optional)
```
User clicks "Unpublish from Lambda" → LambdaAdapter.undeploy() → Lambda deleted
Status: deployed → not_deployed
```

## UI Components

### Function Show Page

**Deployment Status Badge:**
- 🔴 Not Deployed (secondary badge)
- 🟡 Deploying... (warning badge with spinner)
- 🟢 ✓ Deployed (success badge)
- 🔴 ✗ Failed (danger badge)

**Deployment Buttons:**
- **"Publish to Lambda"** - Visible when `not_deployed` or `deployment_failed`
- **"Unpublish from Lambda"** - Visible when `deployed`
- **Disabled spinner button** - Visible when `deploying`

**Deployment Error Alert:**
- Shows if `deployment_failed` with error details

### Function Index Page

**Status Column:**
- Shows deployment status badge for each function
- Allows quick overview of which functions are deployed

## API Endpoints

### POST /functions/:id/deploy
Deploys function to AWS Lambda.

**Response (success):**
```json
{
  "success": true,
  "function_name": "prompt-tracker-abc123"
}
```

**Response (error):**
```json
{
  "success": false,
  "error": "Lambda error: ..."
}
```

### DELETE /functions/:id/undeploy
Removes function from AWS Lambda.

**Response:**
Redirects to function show page with flash message.

### POST /functions/:id/test
Tests deployed function.

**Response (not deployed):**
```json
{
  "success?": false,
  "error": "Function must be deployed to AWS Lambda before testing...",
  "deployment_status": "not_deployed"
}
```

## Code Architecture

### LambdaAdapter Changes

**New Methods:**
- `LambdaAdapter.deploy(function_definition:, code:, ...)` - Explicit deployment
- `LambdaAdapter.undeploy(function_name)` - Remove from AWS
- `LambdaAdapter.build_lambda_client_static` - Static client builder

**Behavior:**
- `deploy()` uses stored `lambda_function_name` if available
- Falls back to generating name from code hash
- Returns `{ success:, function_name:, error: }`

### FunctionDefinition Model

**New Methods:**
- `deployed?` - Check if status is "deployed"
- `not_deployed?` - Check if status is "not_deployed"
- `deploying?` - Check if status is "deploying"
- `deployment_failed?` - Check if status is "deployment_failed"
- `deployment_status_badge_class` - Bootstrap class for badge
- `deployment_status_text` - Human-readable status text

**New Scopes:**
- `FunctionDefinition.deployed` - Only deployed functions
- `FunctionDefinition.not_deployed` - Only non-deployed functions
- `FunctionDefinition.deployment_failed` - Only failed deployments

## Benefits

✅ **Visibility** - Users know exactly when functions are deployed
✅ **Control** - Explicit deployment prevents accidental AWS costs
✅ **Debugging** - Deployment errors are captured and displayed
✅ **Tracking** - Database stores deployment history and status
✅ **Safety** - Test flow prevents execution of non-deployed functions

