# PromptTracker Documentation

Welcome to the PromptTracker documentation! This guide will help you get started and make the most of PromptTracker.

## 🚀 Quick Start

- **[Installation Guide](../README.md#installation)** - Get started with PromptTracker
- **[Quick Fix: Webpacker Error](QUICK_FIX_WEBPACKER.md)** ⚡ - Fix `javascript_importmap_tags` error (30 seconds)
- **[Migration Guide](MIGRATION_GUIDE.md)** - Upgrade from previous versions

## 📦 Installation & Setup

### For Different Asset Pipelines

- **[Webpacker Setup Guide](webpacker_setup.md)** - Install PromptTracker in Webpacker/Shakapacker projects (with importmap - recommended)
- **[Pure Webpacker Setup](client_webpacker_setup.md)** - Advanced: Use Webpacker only (without importmap)
- **[Webpacker Example](examples/webpacker_rails_app_setup.md)** - Complete step-by-step example

### Configuration

- **[Configuration Guide](configuration.md)** - Configure providers, features, and settings
- **[Dynamic Configuration](dynamic_configuration.md)** - Multi-tenant and dynamic configuration
- **[Assistants Configuration Example](examples/assistants_configuration_example.rb)** - OpenAI Assistants API setup

## 🔧 Features & Guides

### Core Features

- **[Function Execution Guide](function_execution_guide.md)** - Create and deploy custom functions
- **[Deployment Flow](deployment_flow.md)** - Deploy agents and manage deployments
- **[Monaco Editor Integration](monaco_editor_integration.md)** - Code editor features

### Infrastructure

- **[AWS Lambda Setup](aws_lambda_setup.md)** - Deploy functions to AWS Lambda

## 🐛 Troubleshooting

### Common Issues

- **[Webpacker/Importmap Conflict](troubleshooting/webpacker_importmap_conflict.md)** - Fix asset pipeline conflicts
- **[Quick Fix: Webpacker](QUICK_FIX_WEBPACKER.md)** - 30-second fix for the most common error

### Getting Help

If you encounter issues:

1. Check the troubleshooting guides above
2. Search [GitHub Issues](https://github.com/DavidGeismarLtd/PromptTracker/issues)
3. Open a new issue with:
   - Your Rails version
   - Your asset pipeline (importmap/Webpacker/Shakapacker)
   - Full error message
   - Steps to reproduce

## 📖 LLM Provider Documentation

Comprehensive API documentation for all supported LLM providers:

- **[OpenAI](llm_providers/openai/)** - Chat Completions, Assistants API, Responses API
- **[Anthropic](llm_providers/anthropic/)** - Messages API, Tool Use
- **[Google](llm_providers/google/)** - Gemini API

See [LLM Providers README](llm_providers/README.md) for the complete list.

## 📚 Additional Resources

### Architecture & Design

- **[PRD: Evaluator and Normalizer Refactoring](prd_evaluator_and_normalizer_refactoring.md)**
- **[PRD: Message Normalization](prd_message_normalization.md)**

### Development

- **[Contributing Guide](../README.md#development-setup-local)** - Set up local development environment
- **[Changelog](../CHANGELOG.md)** - Version history and changes

## 🎯 Common Use Cases

### I'm getting a `javascript_importmap_tags` error

→ See [Quick Fix: Webpacker](QUICK_FIX_WEBPACKER.md) (30 seconds to fix)

### I'm using Webpacker and want to install PromptTracker

→ See [Webpacker Setup Guide](webpacker_setup.md) or [Complete Example](examples/webpacker_rails_app_setup.md)

### I want to configure OpenAI Assistants API

→ See [Assistants Configuration Example](examples/assistants_configuration_example.rb)

### I want to deploy custom functions

→ See [Function Execution Guide](function_execution_guide.md) and [AWS Lambda Setup](aws_lambda_setup.md)

### I need to support multiple tenants

→ See [Dynamic Configuration](dynamic_configuration.md)

## 📝 Documentation Index

```
docs/
├── README.md (this file)
├── QUICK_FIX_WEBPACKER.md          # Quick fix for common error
├── MIGRATION_GUIDE.md              # Upgrade guide
├── webpacker_setup.md              # Webpacker installation
├── configuration.md                # Configuration guide
├── dynamic_configuration.md        # Multi-tenant setup
├── function_execution_guide.md     # Custom functions
├── deployment_flow.md              # Agent deployment
├── aws_lambda_setup.md             # AWS Lambda setup
├── monaco_editor_integration.md    # Code editor
├── examples/
│   ├── webpacker_rails_app_setup.md
│   └── assistants_configuration_example.rb
├── troubleshooting/
│   └── webpacker_importmap_conflict.md
└── llm_providers/
    ├── README.md
    ├── openai/
    ├── anthropic/
    └── google/
```

## 🤝 Contributing

Found an error in the documentation? Want to add more examples?

1. Fork the repository
2. Make your changes
3. Submit a pull request

We welcome contributions! 🎉

---

**Need help?** Open an issue on [GitHub](https://github.com/DavidGeismarLtd/PromptTracker/issues) or check the [Troubleshooting](#-troubleshooting) section above.
