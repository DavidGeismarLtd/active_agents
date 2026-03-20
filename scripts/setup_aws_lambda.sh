#!/bin/bash

# AWS Lambda Setup Script for PromptTracker
# This script automates the AWS setup process

set -e  # Exit on error

echo "🚀 PromptTracker AWS Lambda Setup"
echo "=================================="
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
  echo "❌ AWS CLI is not configured."
  echo ""
  echo "Please run: aws configure"
  echo ""
  echo "You'll need:"
  echo "  1. AWS Access Key ID (from AWS Console → IAM → Users → Security credentials)"
  echo "  2. AWS Secret Access Key"
  echo "  3. Default region (e.g., us-east-1)"
  echo "  4. Default output format (json)"
  echo ""
  exit 1
fi

echo "✅ AWS CLI is configured"
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "📋 AWS Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Create Lambda Execution Role
echo "📝 Step 1: Creating Lambda Execution Role..."
if aws iam get-role --role-name PromptTrackerLambdaExecutionRole &> /dev/null; then
  echo "   ℹ️  Role already exists, skipping..."
else
  aws iam create-role \
    --role-name PromptTrackerLambdaExecutionRole \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' > /dev/null
  echo "   ✅ Role created"
fi
echo ""

# Step 2: Attach Basic Lambda Execution Policy
echo "📝 Step 2: Attaching Lambda Execution Policy..."
aws iam attach-role-policy \
  --role-name PromptTrackerLambdaExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2> /dev/null || echo "   ℹ️  Policy already attached"
echo "   ✅ Policy attached"
echo ""

# Step 3: Get Role ARN
echo "📝 Step 3: Getting Role ARN..."
ROLE_ARN=$(aws iam get-role --role-name PromptTrackerLambdaExecutionRole --query 'Role.Arn' --output text)
echo "   ✅ Role ARN: $ROLE_ARN"
echo ""

# Step 4: Create IAM User
echo "📝 Step 4: Creating IAM User for PromptTracker..."
if aws iam get-user --user-name prompt-tracker-lambda-manager &> /dev/null; then
  echo "   ℹ️  User already exists, skipping..."
else
  aws iam create-user --user-name prompt-tracker-lambda-manager > /dev/null
  echo "   ✅ User created"
fi
echo ""

# Step 5: Create Access Keys
echo "📝 Step 5: Creating Access Keys..."
echo "   ⚠️  Checking for existing access keys..."

# List existing access keys
EXISTING_KEYS=$(aws iam list-access-keys --user-name prompt-tracker-lambda-manager --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -n "$EXISTING_KEYS" ]; then
  echo "   ℹ️  Access keys already exist:"
  echo "   $EXISTING_KEYS"
  echo ""
  echo "   ⚠️  Skipping key creation. If you need new keys, delete the old ones first:"
  echo "   aws iam delete-access-key --user-name prompt-tracker-lambda-manager --access-key-id <KEY_ID>"
  echo ""
  ACCESS_KEY_ID=$(echo $EXISTING_KEYS | awk '{print $1}')
  SECRET_ACCESS_KEY="<EXISTING_KEY_SECRET_NOT_RETRIEVABLE>"
else
  KEY_OUTPUT=$(aws iam create-access-key --user-name prompt-tracker-lambda-manager)
  ACCESS_KEY_ID=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
  SECRET_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')
  echo "   ✅ Access keys created"
  echo ""
  echo "   🔑 ACCESS KEY ID: $ACCESS_KEY_ID"
  echo "   🔐 SECRET ACCESS KEY: $SECRET_ACCESS_KEY"
  echo ""
  echo "   ⚠️  SAVE THESE CREDENTIALS NOW! You won't be able to retrieve the secret key again."
  echo ""
fi

# Step 6: Attach Lambda Management Policy
echo "📝 Step 6: Creating and attaching Lambda Management Policy..."

# Create policy JSON
cat > /tmp/lambda-manager-policy.json <<EOF
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
        "lambda:GetFunctionConfiguration",
        "lambda:InvokeFunction",
        "lambda:DeleteFunction",
        "lambda:ListFunctions",
        "lambda:PublishVersion",
        "lambda:TagResource",
        "lambda:UntagResource",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name prompt-tracker-lambda-manager \
  --policy-name LambdaManagementPolicy \
  --policy-document file:///tmp/lambda-manager-policy.json

echo "   ✅ Policy attached"
echo ""

# Step 7: Generate .env file
echo "📝 Step 7: Generating .env file..."

ENV_FILE="test/dummy/.env"

if [ -f "$ENV_FILE" ]; then
  echo "   ⚠️  $ENV_FILE already exists. Creating backup..."
  cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$ENV_FILE" <<EOF
# AWS Lambda Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
LAMBDA_EXECUTION_ROLE_ARN=$ROLE_ARN
LAMBDA_FUNCTION_PREFIX=prompt-tracker
EOF

echo "   ✅ .env file created at $ENV_FILE"
echo ""

# Summary
echo "=================================="
echo "✅ AWS Lambda Setup Complete!"
echo "=================================="
echo ""
echo "📋 Summary:"
echo "  - Lambda Execution Role: PromptTrackerLambdaExecutionRole"
echo "  - IAM User: prompt-tracker-lambda-manager"
echo "  - Role ARN: $ROLE_ARN"
echo "  - Access Key ID: $ACCESS_KEY_ID"
echo "  - .env file: $ENV_FILE"
echo ""
echo "🎯 Next Steps:"
echo "  1. Enable functions feature in config/initializers/prompt_tracker.rb"
echo "  2. Restart your Rails server"
echo "  3. Navigate to Functions and create a test function"
echo ""
