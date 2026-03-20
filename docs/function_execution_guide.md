# Function Execution Guide

## Overview

PromptTracker allows you to create, test, and deploy Ruby functions that execute on AWS Lambda. This guide explains the complete process from creation to execution.

## 🎯 The Complete Process

### 1. **Create a Function** (UI)

Navigate to **Functions** → **Create Function**

Fill in the form:
- **Name**: Unique identifier (e.g., `get_weather`)
- **Description**: What the function does
- **Category**: api, utility, validation, data_processing, external_service
- **Language**: Ruby (only option currently)
- **Tags**: Comma-separated tags for organization

**Function Code** (Monaco Editor with syntax highlighting):
```ruby
def execute(city:, units: "celsius")
  # Your code here
  api_key = ENV['OPENWEATHER_API_KEY']

  # Make API call
  response = HTTP.get("https://api.openweathermap.org/data/2.5/weather",
    params: { q: city, units: units, appid: api_key })

  JSON.parse(response.body)
end
```

**Parameters** (JSON Schema):
```json
{
  "type": "object",
  "properties": {
    "city": {
      "type": "string",
      "description": "City name"
    },
    "units": {
      "type": "string",
      "enum": ["celsius", "fahrenheit"],
      "description": "Temperature units"
    }
  },
  "required": ["city"]
}
```

**Environment Variables** (encrypted):
```json
{
  "OPENWEATHER_API_KEY": "your-api-key-here"
}
```

**Dependencies** (Ruby gems):
```json
["http"]
```

**Example Input/Output**:
- Input: `{"city": "Berlin", "units": "celsius"}`
- Output: `{"temp": 15, "conditions": "cloudy"}`

---

### 2. **What Happens When You Click "Create"**

1. ✅ **Validation**: Rails validates the function
   - Name is unique
   - Code is valid Ruby syntax
   - Parameters is valid JSON Schema

2. ✅ **Storage**: Function is saved to database
   - Code is stored as plain text
   - Environment variables are **encrypted**
   - Parameters and dependencies stored as JSONB
   - Deployment status set to `not_deployed`

3. ✅ **No Deployment Yet**: Function is NOT deployed to AWS Lambda yet
   - You must explicitly click "Publish to Lambda" to deploy
   - This gives you control over when functions go live

---

### 3. **Deploy to AWS Lambda** (UI)

On the function show page, you'll see a deployment status badge:

- 🔴 **Not Deployed** - Function exists only in database
- 🟡 **Deploying...** - Deployment in progress
- 🟢 **✓ Deployed** - Function is live on AWS Lambda
- 🔴 **✗ Failed** - Deployment error (see error message)

**To deploy:**

1. Click **"Publish to Lambda"** button
2. Wait for deployment (5-10 seconds)
3. Status changes to **"✓ Deployed"**

**What happens during deployment:**

1. ✅ **Package Creation**: Code + dependencies bundled into ZIP
2. ✅ **Lambda Creation**: Function created on AWS Lambda
   - Runtime: Ruby 3.2
   - Memory: 512 MB
   - Timeout: 30 seconds
   - Environment variables injected
3. ✅ **Database Update**:
   - `deployment_status` → `deployed`
   - `lambda_function_name` → stored
   - `deployed_at` → timestamp

**To unpublish:**

1. Click **"Unpublish from Lambda"** button
2. Function removed from AWS Lambda
3. Status changes back to **"Not Deployed"**

---

### 4. **Test the Function** (UI)

**⚠️ Important**: Function must be deployed before testing!

On the function show page, scroll to **"Test Function"** section:

1. **Enter Test Arguments** (Monaco Editor with JSON):
   ```json
   {
     "city": "San Francisco",
     "units": "celsius"
   }
   ```

2. **Click "Run Test"**

3. **What Happens Behind the Scenes**:

   **Step 1: Check Deployment Status**
   ```
   - If not deployed → Show warning: "Function must be deployed first"
   - If deployed → Continue to execution
   ```

   **Step 2: Invoke Lambda**
   ```
   - Send your test arguments as JSON payload
   - AWS Lambda starts a container
   - Installs dependencies (if needed)
   - Runs your code
   - Returns result or error
   ```

   **Step 4: Display Result**
   ```
   - Success: Shows result JSON + execution time
   - Error: Shows error message + debugging tips
   ```

4. **Test Result Display**:

   **Success**:
   ```
   ✅ Test Passed (234ms)
   Function executed successfully on AWS Lambda

   Result:
   {
     "temp": 15,
     "conditions": "cloudy",
     "humidity": 65
   }
   ```

   **Error**:
   ```
   ❌ Test Failed

   Error: NameError: undefined local variable or method `HTTP'

   Common issues:
   - Check that required gems are listed in dependencies
   - Verify your code syntax is valid Ruby
   - Ensure AWS credentials are configured correctly
   ```

---

### 4. **Execute the Function** (Programmatically)

Functions can also be executed programmatically (e.g., by deployed agents):

```ruby
function = FunctionDefinition.find_by(name: "get_weather")

# Test (does not track execution)
result = function.test(city: "Berlin", units: "celsius")
# => { success?: true, result: {...}, execution_time_ms: 234 }

# Execute (tracks execution in database)
result = function.execute(city: "Berlin", units: "celsius")
# => { success?: true, result: {...}, execution_time_ms: 234 }
# Also creates FunctionExecution record
```

---

## 🔧 Technical Details

### AWS Lambda Configuration

Functions are deployed with these settings:

| Setting | Value | Configurable? |
|---------|-------|---------------|
| Runtime | Ruby 3.2 | No |
| Memory | 512 MB | Yes (in code) |
| Timeout | 30 seconds | Yes (in code) |
| Handler | `lambda_function.lambda_handler` | No |
| Environment | Your env vars | Yes (in UI) |

### Function Naming

Lambda functions are named: `{prefix}-{function_name}-{version}`

Example: `prompt-tracker-get_weather-1`

### Caching

- **Deployment**: Lambda functions are cached by name
- **First run**: ~5-10 seconds (cold start + gem installation)
- **Subsequent runs**: ~200-500ms (warm container)

### Cost Estimation

AWS Lambda pricing (2024):
- **Free Tier**: 1M requests/month + 400,000 GB-seconds
- **After Free Tier**: $0.20 per 1M requests

For typical development usage:
- **Expected cost**: $0-2/month (well within free tier)

---

## 🐛 Troubleshooting

### "Missing credentials" error

**Problem**: AWS CLI not configured

**Solution**:
```bash
aws configure
# Enter your AWS Access Key ID and Secret Access Key
```

### "AccessDeniedException" error

**Problem**: IAM user lacks permissions

**Solution**: Run the setup script:
```bash
./scripts/setup_aws_lambda.sh
```

### "Gem not found" error

**Problem**: Dependency not listed

**Solution**: Add gem to dependencies field:
```json
["httparty", "json", "aws-sdk-s3"]
```

### Function timeout

**Problem**: Function takes > 30 seconds

**Solution**: Optimize your code or increase timeout in `LambdaAdapter::TIMEOUT`

### Cold start is slow

**Problem**: First execution takes 5-10 seconds

**Explanation**: AWS Lambda needs to:
1. Start a new container
2. Install Ruby gems
3. Load your code

**Solutions**:
- Use Lambda Layers for common gems (future enhancement)
- Enable Provisioned Concurrency (costs money)
- Accept cold starts as normal

---

## 📊 Execution History

Every execution is tracked in the database:

- **Arguments**: What was passed to the function
- **Result**: What the function returned
- **Success**: true/false
- **Error Message**: If failed
- **Execution Time**: Milliseconds
- **Executed At**: Timestamp

View execution history on the function show page.

---

## 🔐 Security

### Environment Variables

- Stored **encrypted** in database using Rails `encrypts`
- Transmitted **encrypted** to AWS Lambda via HTTPS
- Never displayed in UI (only keys shown, not values)

### Code Execution

- Runs in **isolated AWS Lambda container**
- No access to your Rails database
- No access to other functions
- Limited to 512MB memory and 30s timeout

### API Keys

- AWS credentials stored in `.env` file (never committed to git)
- IAM user has minimal permissions (only Lambda operations)

---

## 🚀 Next Steps

1. **Create your first function** using the UI
2. **Test it** with sample arguments
3. **Check execution history** to see stats
4. **Deploy an agent** that uses your function (Phase 4)
