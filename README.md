# PromptTracker

A comprehensive Rails 7.2 engine for managing, tracking, and analyzing LLM prompts with a "prompts as code" philosophy.

## Features

✅ **Prompt Management** - Version control for prompts with file-based storage
✅ **Response Tracking** - Track all LLM responses with metrics (tokens, cost, latency)
✅ **Evaluation System** - Automated and manual evaluation with multiple evaluator types
✅ **A/B Testing** - Built-in A/B testing with statistical analysis
✅ **Analytics Dashboard** - Comprehensive analytics and visualizations
✅ **Background Jobs** - Async evaluation processing with retry logic
✅ **Web UI** - Bootstrap 5.3 interface for managing prompts and viewing analytics

## Test Coverage

- **~683 tests** across Minitest and RSpec
- **89.64% line coverage**, 69.64% branch coverage
- **100% coverage** of controllers, models, services, and jobs
- See [TESTING.md](TESTING.md) for details

## Quick Start

### Option 1: Docker (Recommended for Quick Setup)

The easiest way to get started - no local dependencies required!

```bash
# Start everything with one command
docker-compose up --build

# Access the app at http://localhost:3000
```

See [DOCKER_QUICKSTART.md](DOCKER_QUICKSTART.md) for a quick guide or [DOCKER_SETUP.md](DOCKER_SETUP.md) for detailed documentation.

### Option 2: Local Development Setup (with Sidekiq + Redis)

For full async support with parallel job execution and real-time updates:

```bash
# 1. Start Redis
redis-server

# 2. Start Sidekiq + Rails (in another terminal)
bin/dev
```

Or start services separately:
```bash
# Terminal 1: Redis
redis-server

# Terminal 2: Sidekiq
bundle exec sidekiq

# Terminal 3: Rails
bin/rails server
```

See [SIDEKIQ_SETUP.md](SIDEKIQ_SETUP.md) for detailed setup instructions.

### Run All Tests

```bash
bin/test_all
```

### View Coverage Report

```bash
open coverage/index.html
```

## Documentation

### Getting Started
- [DOCKER_QUICKSTART.md](DOCKER_QUICKSTART.md) - **Quick Docker setup (recommended)**
- [DOCKER_SETUP.md](DOCKER_SETUP.md) - **Detailed Docker documentation**
- [SIDEKIQ_SETUP.md](SIDEKIQ_SETUP.md) - Local development setup with Sidekiq + Redis

### Development
- [TESTING.md](TESTING.md) - Testing guide
- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) - Implementation details
- [docs/EVALUATOR_SYSTEM_DESIGN.md](docs/EVALUATOR_SYSTEM_DESIGN.md) - Evaluator system design

## Installation
Add this line to your application's Gemfile:

```ruby
gem "prompt_tracker"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install prompt_tracker
```

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
