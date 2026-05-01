# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this project?

PromptTracker is a **mountable Rails 7.2 engine** (not a standalone app) for managing, tracking, and evaluating LLM prompts. It provides version control for prompts, A/B testing, automated evaluation, dataset/test management, a playground, and analytics dashboards. It supports OpenAI, Anthropic, Google, and 6 other LLM providers via the `ruby_llm` gem.

## Development Commands

### Running the dummy app (for development)

```bash
cd test/dummy
bin/rails db:create && bin/rails db:migrate && bin/rails db:seed
bin/rails server          # http://localhost:3000/prompt_tracker
bundle exec sidekiq       # separate terminal for background jobs
```

### Testing

```bash
# Both suites (Minitest + RSpec)
bin/test_all

# Individual suites
bundle exec rails test              # Minitest
bundle exec rspec                   # RSpec

# Single test file
bundle exec rails test test/models/prompt_tracker/prompt_test.rb
bundle exec rspec spec/models/prompt_tracker/evaluator_config_spec.rb

# Single test by line
bundle exec rails test test/models/prompt_tracker/prompt_test.rb:10
```

### Linting

```bash
bin/rubocop -f github
```

### Docker (alternative)

```bash
make help       # list all commands
make up         # start services
make test       # run all tests
make console    # Rails console
```

## Architecture

### Engine structure

This is an **isolated Rails engine** under the `PromptTracker` namespace. The engine is mounted in host apps at a configurable path (typically `/prompt_tracker`). The test/dummy app serves as the development host.

### Three main UI sections (defined in config/routes.rb)

1. **Testing** (`/testing/`) - Pre-deployment: playground, agent/version management, datasets, test runs
2. **Monitoring** (`/monitoring/`) - Runtime: tracked LLM calls, evaluations, performance metrics
3. **Functions** (`/functions/`) - Code-based agent functions with AWS Lambda deployment

### Key domain model chain

`Agent` -> `AgentVersion` (system_prompt, model_config, variables_schema) -> `LlmResponse` (tracked API call) -> `Evaluation` (score/feedback)

Supporting models: `AbTest`, `Test`/`TestRun`, `Dataset`/`DatasetRow`, `EvaluatorConfig`, `DeployedAgent`, `FunctionDefinition`

### Services layer (`app/services/prompt_tracker/`)

- `LlmCallService` - main orchestrator for tracking LLM calls
- `LlmClientService` - provider-agnostic LLM client
- `EvaluatorRegistry` - discovers and runs evaluators
- `AutoEvaluationService` - automatic evaluation after responses
- 13 evaluator types in `services/evaluators/` (ExactMatch, LlmJudge, PatternMatch, JsonSchema, etc.)
- Test runners in `services/test_runners/`

### Frontend

- Hotwire stack: Turbo Streams + Stimulus controllers (40+ controllers in `app/javascript/prompt_tracker/`)
- Importmap for JS module loading (also supports Webpacker)
- ERB views with ActionCable for real-time updates

### Configuration

The engine is configured via `PromptTracker.configure` in a host app initializer. Supports both static config and dynamic per-request configuration (multi-tenant). See `lib/prompt_tracker/configuration.rb`.

### Task agent execution: two modes

Task agents (autonomous, multi-iteration agents — distinct from conversational agents) can run in either of two modes, gated by `PromptTracker.configuration.containerized_execution_enabled`:

- **In-process (default)** — `app/services/prompt_tracker/task_agent_runtime_service.rb` runs inside the Sidekiq worker. Direct ActiveRecord access, full Rails environment.
- **Containerized** — `app/services/prompt_tracker/container_orchestrator.rb` spawns a Docker container per `TaskRun`. The container reports execution events back to Rails via `app/controllers/prompt_tracker/internal/task_run_events_controller.rb`, authenticated by a per-run `CallbackTokenStore` token (Redis-backed). Files written to `/workspace/output/` are auto-attached to the `TaskRun` via Active Storage.

The containerized mode is **always disabled in `Rails.env.test?`** (so existing job specs that mock `TaskAgentRuntimeService` don't accidentally route through Docker + Redis). Opt in locally with `CONTAINERIZED_EXECUTION_ENABLED=true`.

#### Shared agent-runtime modules — `lib/prompt_tracker/agent_runtime/`

Pure-Ruby modules used by **both** execution modes:

- `Planning` — plan state machine (create/update/add/complete/force_failure). Operates on a plain Hash; no ActiveRecord.
- `PlanningFunctions` — function-call schemas (`create_plan`, `get_plan`, `update_step`, `add_step`, `mark_task_complete`).
- `PromptEnhancer` — appends planning-phase / execution-phase / iteration-budget instructions to a base system prompt.

When changing planning behavior, prompt copy, or function schemas, edit these modules — `PlanningService` (the in-process Rails wrapper) and `docker/agent-runtime-entrypoint.rb` (the container entrypoint) both delegate. Do not duplicate logic.

**Don't add Rails-y dependencies (ActiveRecord, `Rails.logger`, ActiveSupport beyond what's commonly available) to anything in `lib/prompt_tracker/agent_runtime/`** — the container loads these without booting Rails.

#### Container runtime — `docker/`

- `Dockerfile.agent-runtime` — minimal Ruby 3.3 image; copies `lib/`, `app/services/`, `app/models/`, plus the entrypoint and bootstrap.
- `docker/agent-runtime-entrypoint.rb` — autonomous loop. Routes by `model_config.api`: `responses` → `LlmClients::OpenaiResponseService` (with manual function-call loop and `tool_choice: "required"` for planning); everything else → `LlmClients::RubyLlmService`.
- `docker/runtime_bootstrap.rb` — loaded before any service from `app/services/`. Provides ActiveSupport, a `Rails.logger` stub, a `PromptTracker.configuration` stub (only `dynamic_configuration?` and `api_key_for`), and a configured `RubyLLM` client. **If you add a new in-process service that the container needs to reuse, audit it for AR access and `PromptTracker.configuration` calls beyond what the bootstrap stubs.**

#### Security

- **Never log env-var VALUES** when launching containers — they include `CALLBACK_TOKEN`, provider API keys (`OPENAI_API_KEY`, etc.), and `AWS_SECRET_ACCESS_KEY`. `ContainerOrchestrator#safe_spawn_log_message` logs keys-only metadata. Don't `Rails.logger.info "Command: #{cmd}"`.
- Container has only the API key for the agent's configured provider, not all env vars.
- Output volume size/file-count limits enforced in `ContainerOrchestrator` (100MB total, 25MB per file, 50 files max).

### CI

GitHub Actions runs RuboCop lint + RSpec against PostgreSQL 14 on Ruby 3.3.5.

## Coding Guidelines

### Small, testable classes
- Create small classes with a single responsibility
- Create tests for all classes using RSpec

### No defensive programming
- Do not rescue `StandardError` broadly — let errors surface
- Do not use defensive hash access patterns with fallbacks to string keys:
  ```ruby
  # Bad
  provider = model_config[:provider] || model_config["provider"] || "openai"

  # Good — use only symbol keys
  provider = model_config[:provider]
  ```

### No backward compatibility code
- Do not maintain backward compatibility for legacy data formats
- If data format changes, migrate the data — don't add dual-read logic

## Naming convention in progress

The codebase is being renamed from `Prompt`/`PromptVersion` to `Agent`/`AgentVersion`. Both terms may appear; the canonical names going forward are Agent/AgentVersion.
