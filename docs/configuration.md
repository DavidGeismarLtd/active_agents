# PromptTracker Configuration Guide

This guide explains how to configure PromptTracker for your application.

## Configuration File

PromptTracker is configured via an initializer file:

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # Configuration goes here
end
```

## Environment Variables

Sensitive values (API keys, AWS credentials) should be stored in environment variables, not committed to git.

### For Development

1. **Copy the example file**:
   ```bash
   cp test/dummy/.env.example test/dummy/.env
   ```

2. **Edit `.env`** with your actual values:
   ```bash
   # LLM Provider API Keys
   OPENAI_LOUNA_API_KEY=sk-...
   ANTHROPIC_API_KEY=sk-ant-...

   # AWS Lambda (only if using Functions feature)
   AWS_REGION=us-east-1
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   LAMBDA_EXECUTION_ROLE_ARN=arn:aws:iam::123456789012:role/...
   ```

3. **Load environment variables** in your application:
   - Use `dotenv-rails` gem (recommended)
   - Or manually load in `config/application.rb`

### For Production

Set environment variables in your deployment platform:
- **Heroku**: `heroku config:set AWS_REGION=us-east-1`
- **AWS**: Use Parameter Store or Secrets Manager
- **Docker**: Use environment variables in docker-compose.yml

## Configuration Sections

### 1. Core Settings

```ruby
config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]
```

**Optional**: Protect the PromptTracker UI with HTTP Basic Auth.

---

### 2. LLM Providers

```ruby
config.providers = {
  openai: { api_key: ENV["OPENAI_API_KEY"] },
  anthropic: { api_key: ENV["ANTHROPIC_API_KEY"] },
  google: { api_key: ENV["GOOGLE_API_KEY"] }
}
```

**Required**: At least one provider must have an `api_key` configured.

**How it works**:
- Provider names and APIs are auto-populated from `ProviderDefaults`
- Models are auto-populated from RubyLLM's model registry
- A provider is only enabled if `api_key` is present

---

### 3. Contexts

```ruby
config.contexts = {
  playground: {
    default_provider: :openai,
    default_api: :chat_completions,
    default_model: "gpt-4o"
  },
  llm_judge: {
    default_provider: :openai,
    default_api: :chat_completions,
    default_model: "gpt-4o"
  }
}
```

**Optional**: Define default selections for different usage scenarios.

**Available contexts**:
- `playground` - Prompt version testing
- `llm_judge` - LLM-as-judge evaluation
- `dataset_generation` - Generating test data
- `prompt_generation` - AI-assisted prompt creation
- `test_generation` - AI-powered test case generation
- `interlocutor_simulation` - Simulating user responses

---

### 4. Function Execution Providers

```ruby
config.function_providers = {
  aws_lambda: {
    region: ENV.fetch("AWS_REGION", "us-east-1"),
    access_key_id: ENV["AWS_ACCESS_KEY_ID"],
    secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    execution_role_arn: ENV["LAMBDA_EXECUTION_ROLE_ARN"],
    function_prefix: ENV.fetch("LAMBDA_FUNCTION_PREFIX", "prompt-tracker")
  }
}
```

**Required only if** `config.features[:functions] = true`

**How it works**:
- Similar to LLM providers, but for code execution backends
- A provider is only enabled if all required credentials are present
- Currently supports AWS Lambda; future providers (GCP, local Docker) can be added

See [AWS Lambda Setup Guide](aws_lambda_setup.md) for detailed instructions.

---

### 5. Feature Flags

```ruby
config.features = {
  monitoring: true,            # Enable Monitoring section
  openai_assistant_sync: true, # Show "Sync OpenAI Assistants" button
  functions: false             # Enable Functions section (requires AWS Lambda)
}
```

**Feature flags**:

| Flag | Default | Description |
|------|---------|-------------|
| `monitoring` | `true` | Enable the Monitoring section (tracked calls, auto-evaluations) |
| `openai_assistant_sync` | `true` | Show "Sync OpenAI Assistants" button in Testing Dashboard |
| `functions` | `false` | Enable the Functions section (code-based agent functions) |

**Note**: Setting `functions: true` requires AWS Lambda configuration (see above).

---

## Complete Example

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # 1. Core Settings
  config.basic_auth_username = ENV["PROMPT_TRACKER_USERNAME"]
  config.basic_auth_password = ENV["PROMPT_TRACKER_PASSWORD"]

  # 2. LLM Providers
  config.providers = {
    openai: { api_key: ENV["OPENAI_API_KEY"] },
    anthropic: { api_key: ENV["ANTHROPIC_API_KEY"] }
  }

  # 3. Contexts
  config.contexts = {
    playground: {
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    },
    llm_judge: {
      default_provider: :openai,
      default_api: :chat_completions,
      default_model: "gpt-4o"
    }
  }

  # 4. Function Execution Providers (only if using Functions)
  config.function_providers = {
    aws_lambda: {
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      execution_role_arn: ENV["LAMBDA_EXECUTION_ROLE_ARN"],
      function_prefix: ENV.fetch("LAMBDA_FUNCTION_PREFIX", "prompt-tracker")
    }
  }

  # 5. Feature Flags
  config.features = {
    monitoring: true,
    openai_assistant_sync: true,
    functions: true  # Enable if you've set up AWS Lambda
  }
end
```

## Checking Configuration

You can check your configuration in the Rails console:

```ruby
# Check if a provider is configured
PromptTracker.configuration.provider_configured?(:openai)
# => true

# Get enabled providers
PromptTracker.configuration.enabled_providers
# => [:openai, :anthropic]

# Check if a feature is enabled
PromptTracker.configuration.feature_enabled?(:functions)
# => true

# Get API key for a provider
PromptTracker.configuration.api_key_for(:openai)
# => "sk-..."

# Check if a function provider is configured
PromptTracker.configuration.function_provider_configured?(:aws_lambda)
# => true

# Get function provider configuration
PromptTracker.configuration.function_provider_config(:aws_lambda)
# => { region: "us-east-1", access_key_id: "AKIA...", ... }
```

## Troubleshooting

### "No providers configured" error
- Ensure at least one provider has an `api_key` set
- Check that environment variables are loaded correctly

### Functions navigation link not showing
- Verify `config.features[:functions] = true` in initializer
- Restart your Rails server after changing configuration

### AWS Lambda errors
- Verify all AWS environment variables are set
- Check that IAM role and user have correct permissions
- See [AWS Lambda Setup Guide](aws_lambda_setup.md)
