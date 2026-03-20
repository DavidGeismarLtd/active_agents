# AWS Lambda Setup for Function Execution

PromptTracker uses AWS Lambda to execute user-defined Ruby functions in a secure, sandboxed environment. This guide explains how to set up AWS Lambda for your PromptTracker installation.

## Why AWS Lambda?

- **Zero Infrastructure**: No Docker daemon or container orchestration needed
- **Built-in Security**: AWS handles sandboxing, isolation, and security patches
- **Automatic Scaling**: Handles 1 or 10,000 concurrent executions seamlessly
- **Pay-per-Use**: Only pay for actual execution time
- **Easy Testing**: Use SAM or LocalStack for local development

## Prerequisites

1. AWS Account
2. AWS CLI installed and configured
3. IAM permissions to create Lambda functions and IAM roles

## Setup Steps

### 1. Create Lambda Execution Role

Create an IAM role that Lambda functions will assume when executing:

```bash
aws iam create-role \
  --role-name PromptTrackerLambdaExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

### 2. Attach Basic Lambda Execution Policy

```bash
aws iam attach-role-policy \
  --role-name PromptTrackerLambdaExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### 3. Get the Role ARN

```bash
aws iam get-role --role-name PromptTrackerLambdaExecutionRole --query 'Role.Arn' --output text
```

Copy the ARN (it will look like `arn:aws:iam::123456789012:role/PromptTrackerLambdaExecutionRole`).

### 4. Create IAM User for PromptTracker

Create an IAM user that PromptTracker will use to manage Lambda functions:

```bash
aws iam create-user --user-name prompt-tracker-lambda-manager
```

### 5. Create Access Keys

```bash
aws iam create-access-key --user-name prompt-tracker-lambda-manager
```

Save the `AccessKeyId` and `SecretAccessKey` from the output.

### 6. Attach Lambda Management Policy

Create a policy file `lambda-manager-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:InvokeFunction",
        "lambda:DeleteFunction",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

Apply the policy:

```bash
aws iam put-user-policy \
  --user-name prompt-tracker-lambda-manager \
  --policy-name LambdaManagementPolicy \
  --policy-document file://lambda-manager-policy.json
```

### 7. Configure Environment Variables

Create a `.env` file in your application root (or `test/dummy/.env` for the dummy app):

```bash
# Copy from .env.example
cp test/dummy/.env.example test/dummy/.env
```

Then edit `.env` and add your AWS credentials:

```bash
# AWS Lambda Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIA...  # From step 5
AWS_SECRET_ACCESS_KEY=...  # From step 5
LAMBDA_EXECUTION_ROLE_ARN=arn:aws:iam::123456789012:role/PromptTrackerLambdaExecutionRole  # From step 3
LAMBDA_FUNCTION_PREFIX=prompt-tracker  # Optional: customize function naming
```

### 8. Enable Functions Feature Flag

In your PromptTracker initializer (`config/initializers/prompt_tracker.rb`), enable the functions feature:

```ruby
PromptTracker.configure do |config|
  # ... other config ...

  # Enable Functions feature
  config.features = {
    monitoring: true,
    openai_assistant_sync: true,
    functions: true  # Enable this!
  }
end
```

**Note**: The Functions navigation link will only appear when `functions: true` is set.

## Testing the Setup

1. Start your Rails server
2. Navigate to the Functions page
3. Create a test function:

```ruby
def execute(name:)
  { greeting: "Hello, #{name}!" }
end
```

4. Click "Test" with arguments: `{ "name": "World" }`
5. You should see the result: `{ "greeting": "Hello, World!" }`

## Cost Estimation

AWS Lambda pricing (as of 2024):
- **Free Tier**: 1M requests/month + 400,000 GB-seconds of compute time
- **After Free Tier**: $0.20 per 1M requests + $0.0000166667 per GB-second

For typical PromptTracker usage (testing functions during development):
- **Expected cost**: $0-5/month (well within free tier)

## Troubleshooting

### "Missing credentials" error
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
- Check that the IAM user has the correct permissions

### "AccessDeniedException" error
- Verify the IAM user has `lambda:CreateFunction` and `lambda:InvokeFunction` permissions
- Check that `LAMBDA_EXECUTION_ROLE_ARN` is correct

### Function timeout
- Default timeout is 30 seconds
- For longer-running functions, you may need to adjust the timeout in `LambdaAdapter::TIMEOUT`

## Security Considerations

- **API Keys**: Store AWS credentials securely (use environment variables, never commit to git)
- **IAM Permissions**: Follow principle of least privilege
- **Function Isolation**: Each function runs in its own Lambda execution environment
- **Network Access**: Lambda functions have internet access by default (can be restricted via VPC)

## Local Development (Optional)

For local testing without AWS costs, you can use LocalStack:

```bash
# Install LocalStack
pip install localstack

# Start LocalStack
localstack start

# Configure PromptTracker to use LocalStack
AWS_ENDPOINT_URL=http://localhost:4566
```

Note: LocalStack support is not yet implemented but can be added easily.
