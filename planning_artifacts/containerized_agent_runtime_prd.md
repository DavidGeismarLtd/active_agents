# Containerized Agent Runtime - Product Requirements Document

**Version:** 1.0
**Date:** 2026-04-15
**Status:** Draft
**Related:** Task Agent System PRD, Agent Deployment PRD, Task Agent Planning System PRD

---

## Executive Summary

Move task agent execution from the Sidekiq process (shared host) into **isolated Docker containers**. Each `TaskRun` spawns a dedicated container with its own filesystem, scoped network access, and resource limits. Output files created by the agent are automatically attached to the `TaskRun` via Active Storage and accessible from the UI.

### Problem Statement

Currently, task agents execute inside the Sidekiq worker process via `ExecuteTaskAgentJob`. This means:

1. **MCP filesystem tools operate on the host** — The `@modelcontextprotocol/server-filesystem` subprocess runs with the same OS user as Sidekiq. It has access to `Rails.root` and `/tmp`, meaning the LLM can read/write/delete any file in those directories — including application code, credentials, and config files.

2. **No isolation between agent and infrastructure** — The agent runtime has full access to the database (ActiveRecord), environment variables (API keys), and network. A prompt injection could instruct the agent to perform destructive operations.

3. **No resource limits** — A runaway agent loop can exhaust server CPU, memory, or disk. There are only soft limits (max_iterations, timeout_seconds) enforced in Ruby, which can be bypassed by long-running tool calls.

4. **No cleanup guarantees** — Temporary files created by MCP tools persist on the host filesystem after the task run completes.

### Solution

Run the entire agent runtime (LLM calls + MCP servers + tool execution) inside a Docker container per task run. The container:

- Has its own ephemeral filesystem (only `/workspace` is writable)
- Gets only the API keys it needs (not the full environment)
- Has network access restricted to LLM API endpoints and a callback URL
- Is destroyed after execution, cleaning up all temporary files
- Mounts an output volume so files can be collected and attached to the TaskRun

---

## Goals

1. **Security isolation** — Agent cannot access host filesystem, database, or credentials beyond what's explicitly provided
2. **Resource limits** — CPU, memory, and disk enforced at container level
3. **Output file collection** — Any file the agent writes to `/workspace/output/` is attached to the TaskRun via Active Storage
4. **Clean state** — Each task run gets a fresh container; no state leakage between runs
5. **Observability** — All LLM calls, function executions, and status updates are reported back to Rails via callback API
6. **Single Docker image** — One `prompt-tracker-agent-runtime` image for all agents; agent-specific behavior comes from runtime configuration

### Non-Goals

- Per-agent custom Docker images (not needed — all agents use the same Ruby/Node runtime)
- Running conversational agents in containers (they need low-latency request/response; containerization is for async task agents only)
- Multi-language agent runtimes (Python, Go, etc.) — future consideration
- Container orchestration (Kubernetes, ECS) — start with local Docker, add orchestration later

---

## Architecture Overview

### Current Architecture (Before)

```
┌──────────────────────────────────────────────────────┐
│  Server (Rails + Sidekiq)                            │
│                                                      │
│  ExecuteTaskAgentJob#perform                         │
│    └─ TaskAgentRuntimeService.call(...)              │
│         ├─ LLM calls (HTTP to OpenAI/Anthropic) ✅   │
│         ├─ MCP filesystem (host filesystem!)    ⚠️   │
│         ├─ Lambda functions (isolated)          ✅   │
│         ├─ DB writes (LlmResponse, etc.)        ⚠️   │
│         └─ Turbo Stream broadcasts              ✅   │
│                                                      │
│  Risks:                                              │
│  - MCP tools can read/write Rails.root               │
│  - Agent has full DB access via ActiveRecord         │
│  - Agent sees all ENV vars (API keys, DB creds)      │
│  - No CPU/memory limits beyond OS process limits     │
└──────────────────────────────────────────────────────┘
```

### New Architecture (After)

```
┌──────────────────────────────────────────────────────┐
│  Server (Rails + Sidekiq)                            │
│                                                      │
│  ExecuteTaskAgentJob#perform                         │
│    ├─ 1. Load agent config from DB                   │
│    ├─ 2. Prepare host directories:                   │
│    │      /tmp/task_runs/{id}/input/  (read-only)    │
│    │      /tmp/task_runs/{id}/output/ (read-write)   │
│    ├─ 3. Spawn Docker container ─────────────┐       │
│    │                                         ▼       │
│    │   ┌─────────────────────────────────────────┐   │
│    │   │  Docker: prompt-tracker-agent-runtime    │   │
│    │   │                                         │   │
│    │   │  /workspace/input/  (mounted, read-only)│   │
│    │   │  /workspace/output/ (mounted, writable) │   │
│    │   │  /workspace/tmp/    (internal, scratch)  │   │
│    │   │                                         │   │
│    │   │  MCP filesystem → /workspace only       │   │
│    │   │                                         │   │
│    │   │  AgentContainerRunner                   │   │
│    │   │   ├─ LLM calls (HTTP)                   │   │
│    │   │   ├─ MCP tools (scoped to /workspace)   │   │
│    │   │   ├─ Lambda functions (HTTP to AWS)      │   │
│    │   │   └─ Reports events via callback API    │   │
│    │   │                                         │   │
│    │   │  Network: LLM APIs + callback URL only  │   │
│    │   │  Resources: 1 CPU, 512MB RAM, 30min max │   │
│    │   └─────────────────────────────────────────┘   │
│    │                                         │       │
│    ├─ 4. Wait for container exit             │       │
│    ├─ 5. Collect output files from           │       │
│    │      /tmp/task_runs/{id}/output/        │       │
│    ├─ 6. Attach files to TaskRun via         │       │
│    │      Active Storage                     │       │
│    └─ 7. Cleanup host temp directories       │       │
│                                                      │
│  Callback API (internal, not public):                │
│    POST /internal/task_runs/:id/events               │
│    ├─ event: "status_update" → update TaskRun        │
│    ├─ event: "llm_response"  → create LlmResponse    │
│    ├─ event: "function_execution" → create record    │
│    ├─ event: "plan_update"   → update planning steps │
│    └─ event: "log"           → append to task log    │
└──────────────────────────────────────────────────────┘
```

---

## Detailed Design

### 1. Docker Image: `prompt-tracker-agent-runtime`

A single Docker image used for all task agent executions. Contains the minimal runtime needed.

#### Dockerfile.agent-runtime

```dockerfile
FROM ruby:3.3.0-slim

# Install minimal dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    ca-certificates \
    curl \

#### What's in the image vs. what's NOT

| Included | NOT included |
|----------|-------------|
| Ruby 3.3 + bundled gems | Views / ERB templates |
| PromptTracker services (LLM clients, MCP manager, etc.) | Asset pipeline / JS controllers |
| PromptTracker models (for serialization, not DB access) | Database migrations |
| Node.js + MCP server packages | Sidekiq / background job infra |
| `agent-runtime-entrypoint.rb` | Rails server / Puma |
| `ca-certificates` for HTTPS | Dev/test dependencies |

#### Why one image is enough

All variation between agents is **runtime configuration**, not code:

- System prompt, model, temperature → passed as `AGENT_CONFIG` env var (JSON)
- Which MCP servers to connect → passed in `AGENT_CONFIG`
- Which Lambda functions to call → function names in config, executed via HTTP
- Planning enabled/disabled → config flag
- Max iterations, timeout → config values

No agent needs different Ruby gems, Node packages, or system libraries. If that changes in the future (e.g., an agent needs `ffmpeg`), we can add per-agent image support then.

---

### 2. Container Lifecycle (ContainerOrchestrator Service)

New service: `PromptTracker::ContainerOrchestrator`

Responsible for the full lifecycle of a container-based task run.

```ruby
module PromptTracker
  # Orchestrates Docker container lifecycle for task agent execution.
  #
  # This service:
  # 1. Prepares host directories (input/output volumes)
  # 2. Builds container configuration (env vars, volumes, resource limits)
  # 3. Spawns and monitors the container
  # 4. Collects output files after container exits
  # 5. Attaches output files to TaskRun via Active Storage
  # 6. Cleans up host temp directories
  #
  class ContainerOrchestrator
    CONTAINER_IMAGE = "prompt-tracker-agent-runtime:latest"
    DEFAULT_MEMORY_LIMIT = "512m"
    DEFAULT_CPU_LIMIT = "1.0"
    DEFAULT_TIMEOUT = 1800 # 30 minutes
    HOST_WORKSPACE_ROOT = "/tmp/prompt_tracker/task_runs"

    def initialize(task_run:)
      @task_run = task_run
      @task_agent = task_run.deployed_agent
      @container_id = nil
      @host_workspace = File.join(HOST_WORKSPACE_ROOT, task_run.id.to_s)
    end

    def execute
      prepare_workspace
      container_config = build_container_config
      @container_id = spawn_container(container_config)
      wait_for_completion
      collect_output_files
    ensure
      cleanup_container
      cleanup_workspace
    end

    private

    def prepare_workspace
      FileUtils.mkdir_p(input_dir)
      FileUtils.mkdir_p(output_dir)
      # Copy any input files if provided in task_run.variables_used
      copy_input_files if task_run_has_input_files?
    end

    def build_container_config
      {
        image: CONTAINER_IMAGE,
        name: "task-run-#{@task_run.id}",
        environment: build_environment,
        volumes: build_volumes,
        memory: memory_limit,
        cpus: cpu_limit,
        network: "prompt-tracker-agent-network",
        # Auto-remove on exit
        remove: true
      }
    end

    def build_environment
      agent_config = serialize_agent_config
      {
        "TASK_RUN_ID" => @task_run.id.to_s,
        "AGENT_CONFIG" => agent_config.to_json,
        "CALLBACK_URL" => callback_url,
        "CALLBACK_TOKEN" => generate_callback_token
      }.merge(scoped_api_keys)
    end

    def build_volumes
      {
        input_dir => { target: "/workspace/input", read_only: true },
        output_dir => { target: "/workspace/output", read_only: false }
      }
    end

    def scoped_api_keys
      # Only pass the API key for the provider this agent uses
      provider = @task_agent.agent_version.model_config["provider"]
      key_name = "#{provider.upcase}_API_KEY"
      { key_name => ENV[key_name] }.compact
    end

    def collect_output_files
      Dir.glob(File.join(output_dir, "**", "*")).select { |f| File.file?(f) }.each do |file_path|
        relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(output_dir))
        @task_run.output_files.attach(
          io: File.open(file_path),
          filename: relative_path.to_s,
          content_type: Marcel::MimeType.for(Pathname.new(file_path))
        )
      end
    end

    def cleanup_workspace
      FileUtils.rm_rf(@host_workspace)
    end

    def input_dir = File.join(@host_workspace, "input")
    def output_dir = File.join(@host_workspace, "output")
  end
end
```

---

### 3. Callback API (Internal Events Endpoint)

The container has no database access. Instead, it reports all events back to Rails via an internal HTTP endpoint. This endpoint is **not public** — it is authenticated with a per-run token generated by `ContainerOrchestrator`.

#### Route

```ruby
# config/routes.rb (inside engine)
namespace :internal do
  resources :task_run_events, only: [:create]
end
```

#### Controller

```ruby
module PromptTracker
  module Internal
    # Receives execution events from containerized agent runtimes.
    #
    # Events are authenticated with a per-run callback token.
    # This endpoint is NOT part of the public API.
    #
    class TaskRunEventsController < ActionController::API
      before_action :authenticate_callback

      # POST /internal/task_run_events
      #
      # Accepts events from the agent container:
      # - status_update: { status: "running" | "completed" | "failed", output: "...", error: "..." }
      # - llm_response: { model:, prompt_tokens:, completion_tokens:, cost_usd:, text:, ... }
      # - function_execution: { function_name:, arguments:, result:, success:, execution_time_ms: }
      # - plan_update: { plan: { steps: [...] } }
      # - log: { level: "info" | "error", message: "..." }
      #
      def create
        task_run = TaskRun.find(params[:task_run_id])

        case params[:event_type]
        when "status_update"
          handle_status_update(task_run, params[:data])
        when "llm_response"
          handle_llm_response(task_run, params[:data])
        when "function_execution"
          handle_function_execution(task_run, params[:data])
        when "plan_update"
          handle_plan_update(task_run, params[:data])
        when "log"
          handle_log(task_run, params[:data])
        end

        head :ok
      end

      private

      def authenticate_callback
        token = request.headers["X-Callback-Token"]
        expected = CallbackTokenStore.get(params[:task_run_id])
        head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(token, expected)
      end
    end
  end
end
```

#### Event Types

| Event | Purpose | DB Record Created |
|-------|---------|-------------------|
| `status_update` | Update TaskRun status (running/completed/failed) | Updates `TaskRun` |
| `llm_response` | Track an LLM API call | Creates `LlmResponse` |
| `function_execution` | Track a function/MCP tool call | Creates `FunctionExecution` |
| `plan_update` | Update planning steps | Updates `TaskRun.metadata["plan"]` |
| `log` | Append to execution log | Updates `TaskRun.metadata["logs"]` |

#### Turbo Stream Broadcasting

The event handlers broadcast Turbo Stream updates exactly as the current in-process code does, so the UI stays real-time:

```ruby
def handle_status_update(task_run, data)
  case data[:status]
  when "completed"
    task_run.complete!(output: data[:output])
  when "failed"
    task_run.fail!(error: data[:error])
  end

  # Broadcast UI updates via Turbo Streams (same as current implementation)
  Turbo::StreamsChannel.broadcast_replace_to(
    "task_run_#{task_run.id}",
    target: "summary_cards",
    partial: "prompt_tracker/task_runs/summary_cards",
    locals: { task_run: task_run, llm_responses: task_run.llm_responses, function_executions: task_run.function_executions }
  )
end
```

---

### 4. Output File Collection & Active Storage

#### Model Changes

Add `has_many_attached :output_files` to `TaskRun`:

```ruby
class TaskRun < ApplicationRecord
  # Existing associations...

  # Output files produced by the agent during execution.
  # These are collected from /workspace/output/ after the container exits
  # and attached via Active Storage.
  has_many_attached :output_files
end
```

#### How Files Get Attached

The flow is:

1. **During execution** — The agent writes files to `/workspace/output/` inside the container. This directory is mounted from the host at `/tmp/prompt_tracker/task_runs/{id}/output/`.

2. **After container exits** — `ContainerOrchestrator#collect_output_files` scans the host output directory and attaches every file found:

```ruby
def collect_output_files
  output_path = Pathname.new(output_dir)
  files_attached = 0

  Dir.glob(File.join(output_dir, "**", "*")).select { |f| File.file?(f) }.each do |file_path|
    relative_path = Pathname.new(file_path).relative_path_from(output_path)

    @task_run.output_files.attach(
      io: File.open(file_path),
      filename: relative_path.to_s,
      content_type: Marcel::MimeType.for(Pathname.new(file_path))
    )

    files_attached += 1
  end

  # Update task run metadata with file count
  @task_run.update!(
    metadata: (@task_run.metadata || {}).merge("output_files_count" => files_attached)
  )

  Rails.logger.info "[ContainerOrchestrator] Attached #{files_attached} output files to TaskRun #{@task_run.id}"
end
```

3. **After attachment** — The host temp directory is deleted. Files now live in Active Storage (disk in dev, S3/GCS in production).

#### File Size Limits

To prevent agents from filling the disk, the output volume has limits:

| Limit | Value | Enforcement |
|-------|-------|-------------|
| Max total output size | 100MB | Docker volume quota or post-collection check |
| Max single file size | 25MB | Post-collection check before attachment |
| Max file count | 50 | Post-collection check |

```ruby
MAX_OUTPUT_SIZE_BYTES = 100.megabytes
MAX_SINGLE_FILE_BYTES = 25.megabytes
MAX_OUTPUT_FILES = 50

def validate_output_files
  files = Dir.glob(File.join(output_dir, "**", "*")).select { |f| File.file?(f) }

  if files.count > MAX_OUTPUT_FILES
    Rails.logger.warn "[ContainerOrchestrator] Too many output files (#{files.count}). Only first #{MAX_OUTPUT_FILES} will be attached."
    files = files.first(MAX_OUTPUT_FILES)
  end

  total_size = files.sum { |f| File.size(f) }
  if total_size > MAX_OUTPUT_SIZE_BYTES
    Rails.logger.warn "[ContainerOrchestrator] Total output size #{total_size} exceeds limit. Skipping large files."
    files = files.reject { |f| File.size(f) > MAX_SINGLE_FILE_BYTES }
  end

  files
end
```

#### UI: Displaying Output Files on TaskRun Show

Add an "Output Files" card to the task run show page, between the Result and Error sections:

```erb
<%# app/views/prompt_tracker/task_runs/show.html.erb %>

<!-- Output Files -->
<% if @task_run.output_files.attached? %>
  <div class="card mb-4">
    <div class="card-header">
      <h5 class="mb-0">
        <i class="bi bi-paperclip"></i> Output Files
        <span class="badge bg-secondary"><%= @task_run.output_files.count %></span>
      </h5>
    </div>
    <div class="card-body">
      <div class="table-responsive">
        <table class="table table-sm table-hover mb-0">
          <thead>
            <tr>
              <th>Filename</th>
              <th>Type</th>
              <th>Size</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <% @task_run.output_files.each do |file| %>
              <tr>
                <td>
                  <i class="bi bi-file-earmark"></i>
                  <%= file.filename %>
                </td>
                <td><code><%= file.content_type %></code></td>
                <td><%= number_to_human_size(file.byte_size) %></td>
                <td>
                  <%= link_to "Download", rails_blob_path(file, disposition: :attachment),
                      class: "btn btn-sm btn-outline-primary" %>
                  <% if file.content_type&.start_with?("text/", "application/json") %>
                    <%= link_to "Preview", rails_blob_path(file, disposition: :inline),
                        class: "btn btn-sm btn-outline-secondary", target: "_blank" %>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  </div>
<% end %>
```

#### API: Output Files via TaskRun API

The public task agent API should also expose output files:

```json
// GET /api/task_agents/:slug/runs/:id
{
  "id": 123,
  "status": "completed",
  "output_summary": "Generated 3 reports",
  "output_files": [
    {
      "filename": "report_2026-04-15.csv",
      "content_type": "text/csv",
      "byte_size": 45230,
      "download_url": "/rails/active_storage/blobs/redirect/xxx/report_2026-04-15.csv"
    },
    {
      "filename": "summary.md",
      "content_type": "text/markdown",
      "byte_size": 1204,
      "download_url": "/rails/active_storage/blobs/redirect/yyy/summary.md"
    }
  ]
}
```


---

### 5. Security Model

#### Container Isolation Boundaries

```
┌─────────────────────────────────────────────────────────┐
│                    HOST SERVER                          │
│                                                         │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │ Rails + Sidekiq  │    │  Docker Container           │ │
│  │                  │    │                             │ │
│  │ Full DB access   │    │  ❌ No DB access            │ │
│  │ All ENV vars     │    │  ✅ Only scoped API key     │ │
│  │ Host filesystem  │    │  ❌ No host filesystem      │ │
│  │ Full network     │    │  ✅ Restricted network      │ │
│  │ Unlimited CPU/   │    │  ✅ 1 CPU, 512MB RAM        │ │
│  │   memory         │    │  ✅ 30min timeout           │ │
│  │                  │    │                             │ │
│  │  Communicates    │◄───│  Reports via callback API   │ │
│  │  via internal    │    │                             │ │
│  │  HTTP endpoint   │    │  /workspace/input  (r/o)    │ │
│  │                  │    │  /workspace/output (r/w)    │ │
│  │                  │    │  /workspace/tmp    (r/w)    │ │
│  └─────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

#### What the Container CAN Access

| Resource | Access | How |
|----------|--------|-----|
| LLM APIs (OpenAI, Anthropic, Google) | ✅ Outbound HTTPS | Docker network allows specific endpoints |
| AWS Lambda (for function execution) | ✅ Outbound HTTPS | Docker network allows AWS endpoints |
| Callback API (Rails internal endpoint) | ✅ Outbound HTTP | Docker network allows host callback URL |
| `/workspace/input/` | ✅ Read-only | Mounted volume |
| `/workspace/output/` | ✅ Read-write | Mounted volume |
| `/workspace/tmp/` | ✅ Read-write | Internal container directory (ephemeral) |
| Scoped API key (e.g., `OPENAI_API_KEY`) | ✅ Env var | Only the key for the agent's provider |

#### What the Container CANNOT Access

| Resource | Access | Why |
|----------|--------|-----|
| PostgreSQL database | ❌ Blocked | No `DATABASE_URL`, no network route |
| Redis | ❌ Blocked | No `REDIS_URL`, no network route |
| Host filesystem (Rails.root, /etc, etc.) | ❌ Blocked | Not mounted, container filesystem is isolated |
| Other containers | ❌ Blocked | Dedicated Docker network with no inter-container routing |
| Other API keys | ❌ Blocked | Only the provider-specific key is passed |
| `SECRET_KEY_BASE` | ❌ Blocked | Not passed to container |
| `AWS_SECRET_ACCESS_KEY` (for Lambda) | ⚠️ Conditional | Only passed if agent has Lambda functions |

#### Callback Token Authentication

Each task run gets a unique, time-limited callback token:

```ruby
module PromptTracker
  # Manages per-run callback tokens for container → host authentication.
  #
  # Tokens are stored in Redis with a TTL matching the task timeout.
  # This prevents replay attacks and ensures tokens expire with the task.
  #
  class CallbackTokenStore
    PREFIX = "prompt_tracker:callback_token:"

    def self.generate(task_run_id, ttl_seconds: 3600)
      token = SecureRandom.hex(32)
      redis.setex("#{PREFIX}#{task_run_id}", ttl_seconds, token)
      token
    end

    def self.get(task_run_id)
      redis.get("#{PREFIX}#{task_run_id}")
    end

    def self.revoke(task_run_id)
      redis.del("#{PREFIX}#{task_run_id}")
    end

    def self.redis
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end
  end
end
```

#### Network Isolation

Create a dedicated Docker network for agent containers:

```bash
# One-time setup
docker network create prompt-tracker-agent-network \
  --driver bridge \
  --internal  # No outbound internet by default
```

For LLM API access, use a proxy or iptables rules to allow only specific endpoints:

```bash
# Allow outbound to OpenAI, Anthropic, Google, AWS Lambda
# Block everything else
iptables -A DOCKER-USER -s 172.20.0.0/16 -d api.openai.com -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -d api.anthropic.com -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -d generativelanguage.googleapis.com -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -d lambda.*.amazonaws.com -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -d <host-callback-ip> -p tcp --dport 3000 -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -j DROP
```

**Alternative (simpler for dev):** Use `--network host` in development and restrict in production only.

---

### 6. MCP Filesystem Scoping Inside Container

Inside the container, the MCP filesystem server is hardcoded to `/workspace`:

```ruby
# Container-side MCP configuration (built by agent-runtime-entrypoint.rb)
mcp_servers = {
  filesystem: {
    transport: "stdio",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
    env: {}
  }
}
```

The agent can read from `/workspace/input/`, write scratch files to `/workspace/tmp/`, and write deliverables to `/workspace/output/`. It cannot access anything outside `/workspace` — the MCP server enforces this, AND the container filesystem isolation provides a second layer of protection.

#### Directory Structure Inside Container

```
/workspace/
├── input/          # Mounted read-only from host. Input files for the task.
├── output/         # Mounted read-write to host. Files here get attached to TaskRun.
└── tmp/            # Internal to container. Scratch space. Destroyed with container.
```

The agent's system prompt is enhanced to explain this:

```
You have access to a filesystem workspace:
- /workspace/input/ — Read-only input files provided for this task
- /workspace/output/ — Write any files you want to deliver as output here
- /workspace/tmp/ — Temporary scratch space for intermediate work

Files in /workspace/output/ will be automatically saved and made available
to the user after task completion. Use descriptive filenames.
```

---

### 7. Input Files

Task agents can receive input files in two ways:

#### A. Via Variables (URL reference)

The task's `variables_used` can reference files by URL. The `ContainerOrchestrator` downloads them to the host input directory before spawning the container:

```ruby
def copy_input_files
  input_files = @task_run.variables_used["input_files"] || []
  input_files.each do |file_ref|
    case file_ref["type"]
    when "url"
      download_file(file_ref["url"], File.join(input_dir, file_ref["filename"]))
    when "active_storage"
      blob = ActiveStorage::Blob.find_signed(file_ref["signed_id"])
      blob.download { |chunk| File.open(File.join(input_dir, blob.filename.to_s), "ab") { |f| f.write(chunk) } }
    end
  end
end
```

#### B. Via Active Storage (uploaded files)

Future: Add `has_many_attached :input_files` to `TaskRun`. When triggering a task run via the API, users can upload files that get mounted into the container.

```json
// POST /api/task_agents/:slug/trigger
// Content-Type: multipart/form-data
{
  "variables": { "topic": "quarterly report" },
  "input_files": [file1.csv, file2.pdf]
}
```

---

### 8. Updated ExecuteTaskAgentJob

The job changes from calling `TaskAgentRuntimeService` in-process to spawning a container:

```ruby
module PromptTracker
  class ExecuteTaskAgentJob < ApplicationJob
    queue_as :default

    def perform(task_agent_id, task_run_id = nil, options = {})
      task_agent = DeployedAgent.find(task_agent_id)

      unless task_agent.agent_type_task?
        Rails.logger.error "[ExecuteTaskAgentJob] Agent #{task_agent_id} is not a task agent"
        return
      end

      task_run = find_or_create_task_run(task_agent, task_run_id, options)

      if containerized_execution_enabled?
        # New: Execute in isolated Docker container
        ContainerOrchestrator.new(task_run: task_run).execute
      else
        # Legacy: Execute in-process (for development or when Docker unavailable)
        TaskAgentRuntimeService.call(
          task_agent: task_agent,
          task_run: task_run,
          variables: options[:variables]
        )
      end
    end

    private

    def containerized_execution_enabled?
      PromptTracker.configuration.containerized_execution_enabled
    end
  end
end
```

#### Configuration

```ruby
# lib/prompt_tracker/configuration.rb
# Whether to run task agents in isolated Docker containers.
# When false, agents run in the Sidekiq process (legacy behavior).
# @return [Boolean]
attr_accessor :containerized_execution_enabled

# Docker image for agent runtime containers.
# @return [String]
attr_accessor :agent_runtime_image

# Resource limits for agent containers.
# @return [Hash]
attr_accessor :container_resource_limits

def initialize
  # ... existing defaults ...
  @containerized_execution_enabled = false  # Opt-in, enable when ready
  @agent_runtime_image = "prompt-tracker-agent-runtime:latest"
  @container_resource_limits = {
    memory: "512m",
    cpus: "1.0",
    timeout_seconds: 1800
  }
end
```

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # Enable containerized execution (requires Docker)
  config.containerized_execution_enabled = Rails.env.production?

  # Custom resource limits
  config.container_resource_limits = {
    memory: "1g",        # 1GB for production workloads
    cpus: "2.0",         # 2 CPUs
    timeout_seconds: 3600 # 1 hour max
  }
end
```



---

### 9. Agent Container Entrypoint

The container's entrypoint is a Ruby script that:
1. Reads `AGENT_CONFIG` from env
2. Initializes the agent runtime (without Rails/ActiveRecord)
3. Runs the autonomous loop
4. Reports all events via HTTP callbacks
5. Exits when done

```ruby
#!/usr/bin/env ruby
# docker/agent-runtime-entrypoint.rb
#
# Entrypoint for containerized agent runtime.
# Reads configuration from environment, executes the agent loop,
# and reports events via HTTP callbacks to the host Rails app.

require "json"
require "net/http"
require "uri"

class AgentContainerRunner
  def initialize
    @config = JSON.parse(ENV.fetch("AGENT_CONFIG"))
    @task_run_id = ENV.fetch("TASK_RUN_ID")
    @callback_url = ENV.fetch("CALLBACK_URL")
    @callback_token = ENV.fetch("CALLBACK_TOKEN")
  end

  def run
    report_event("status_update", { status: "running" })

    # Initialize MCP manager with container-scoped filesystem
    setup_mcp_servers

    # Run the autonomous agent loop
    # (Uses the same TaskAgentRuntimeService logic but with
    #  a callback-based reporter instead of direct DB writes)
    execute_agent_loop

    report_event("status_update", {
      status: "completed",
      output: @final_output
    })
  rescue => e
    report_event("status_update", {
      status: "failed",
      error: e.message
    })
    exit(1)
  end

  private

  def report_event(event_type, data)
    uri = URI("#{@callback_url}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["X-Callback-Token"] = @callback_token
    request.body = {
      task_run_id: @task_run_id,
      event_type: event_type,
      data: data
    }.to_json
    http.request(request)
  end

  def setup_mcp_servers
    # MCP filesystem is always scoped to /workspace inside the container
    # Additional MCP servers from agent config are also initialized
  end
end

AgentContainerRunner.new.run
```

---

### 10. Database Migration

```ruby
class AddOutputFilesToTaskRuns < ActiveRecord::Migration[7.2]
  def change
    # Active Storage handles file attachment via its own tables
    # (active_storage_blobs, active_storage_attachments)
    # No additional columns needed on task_runs for file storage.

    # Add container execution metadata
    add_column :prompt_tracker_task_runs, :container_id, :string
    add_column :prompt_tracker_task_runs, :execution_mode, :string,
               default: "in_process", null: false
    # execution_mode: "in_process" (legacy) or "containerized" (new)
  end
end
```

---

### 11. Docker Compose Updates

Add the agent runtime image build and agent network to docker-compose:

```yaml
# docker-compose.yml additions

services:
  # ... existing db, redis, web, sidekiq ...

  # Build agent runtime image (not a running service)
  agent-runtime-builder:
    build:
      context: .
      dockerfile: Dockerfile.agent-runtime
    image: prompt-tracker-agent-runtime:latest
    # This service only builds the image; it doesn't run
    profiles: ["build"]

networks:
  # Isolated network for agent containers
  agent-network:
    driver: bridge
    name: prompt-tracker-agent-network
```

Build the image:

```bash
docker compose build agent-runtime-builder
# Or directly:
docker build -f Dockerfile.agent-runtime -t prompt-tracker-agent-runtime:latest .
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

- [ ] Create `Dockerfile.agent-runtime` with minimal Ruby + Node image
- [ ] Implement `ContainerOrchestrator` service (spawn, wait, cleanup)
- [ ] Implement `CallbackTokenStore` (Redis-based token management)
- [ ] Create internal callback API endpoint (`TaskRunEventsController`)
- [ ] Create `AgentContainerRunner` entrypoint script
- [ ] Add `containerized_execution_enabled` configuration flag
- [ ] Update `ExecuteTaskAgentJob` with feature flag for container vs in-process
- [ ] Add `execution_mode` and `container_id` columns to `task_runs`
- [ ] Write specs for `ContainerOrchestrator` (with Docker mocks)
- [ ] Write specs for `TaskRunEventsController`
- [ ] Write specs for `CallbackTokenStore`

### Phase 2: Output Files & Active Storage (Week 2-3)

- [ ] Add `has_many_attached :output_files` to `TaskRun`
- [ ] Implement `collect_output_files` in `ContainerOrchestrator`
- [ ] Add file size/count validation
- [ ] Create "Output Files" UI card on task run show page
- [ ] Add output files to public task agent API response
- [ ] Write specs for output file collection
- [ ] Write specs for file size limits

### Phase 3: Security & Network Isolation (Week 3-4)

- [ ] Create `prompt-tracker-agent-network` Docker network
- [ ] Implement scoped API key passing (only the provider's key)
- [ ] Set up network rules (iptables or proxy) for LLM API access
- [ ] Add resource limits (memory, CPU, timeout) to container config
- [ ] Implement container timeout enforcement (kill after max time)
- [ ] Security audit: verify no host filesystem/DB/Redis leakage
- [ ] Write integration tests with real Docker containers

### Phase 4: Input Files & Polish (Week 4-5)

- [ ] Implement input file downloading/mounting in `ContainerOrchestrator`
- [ ] Add input file support to task trigger API
- [ ] Add `has_many_attached :input_files` to `TaskRun` (optional)
- [ ] Update MCP filesystem system prompt injection
- [ ] Add container status monitoring (health checks)
- [ ] Handle container crash/OOM scenarios gracefully
- [ ] Add container execution metrics (startup time, peak memory)
- [ ] Update docker-compose.yml and docker-compose.prod.yml
- [ ] Documentation: setup guide for enabling containerized execution
- [ ] End-to-end testing with real task agents

---

## Risks & Mitigation

### Docker Availability

**Risk:** Docker may not be installed or available on the deployment target (e.g., Render, Heroku).

**Mitigation:** The `containerized_execution_enabled` flag defaults to `false`. In-process execution remains the fallback. Containerized execution is opt-in for environments that support Docker (self-hosted, VPS, AWS EC2).

### Container Startup Latency

**Risk:** Spawning a Docker container adds 2-5 seconds of latency before the agent starts executing.

**Mitigation:** This is acceptable for task agents (which run for minutes/hours, not milliseconds). Pre-pulling the image and using `--rm` for automatic cleanup minimizes overhead. Container pooling (warm containers) can be added later if needed.

### Callback API Reliability

**Risk:** If the host Rails app is temporarily unavailable, the container can't report events.

**Mitigation:** The `AgentContainerRunner` should implement retry with exponential backoff for callback failures. Events can be buffered in-memory and retried. If all retries fail, the container writes events to a file in `/workspace/output/events.json` as a last resort, which `ContainerOrchestrator` reads after container exit.

### Output File Security

**Risk:** Agent could write malicious files (e.g., executable scripts, symlinks to host paths).

**Mitigation:**
- File size limits (25MB per file, 100MB total, 50 files max)
- Symlinks are not followed during collection (use `File.file?` which returns false for broken symlinks)
- Files are served via Active Storage with `Content-Disposition: attachment` by default
- Content-type is detected by file content, not extension

### Resource Exhaustion

**Risk:** Many concurrent task runs could exhaust Docker resources on the host.

**Mitigation:**
- Queue-based execution via Sidekiq limits concurrency naturally
- Add a configuration for `max_concurrent_containers` (default: 5)
- Monitor Docker resource usage with container metrics
- Containers are auto-removed on exit (`--rm`)

---

## Summary of New Components

| Component | Type | Purpose |
|-----------|------|---------|
| `Dockerfile.agent-runtime` | Docker | Minimal runtime image for agent execution |
| `docker/agent-runtime-entrypoint.rb` | Script | Container entrypoint that runs the agent loop |
| `ContainerOrchestrator` | Service | Manages container lifecycle (spawn → collect → cleanup) |
| `CallbackTokenStore` | Service | Redis-based per-run authentication tokens |
| `Internal::TaskRunEventsController` | Controller | Receives events from containers |
| `TaskRun#output_files` | Association | Active Storage attachment for output files |
| `TaskRun#execution_mode` | Column | "in_process" or "containerized" |
| `TaskRun#container_id` | Column | Docker container ID for debugging |
| Output Files UI card | View partial | Displays downloadable files on task run page |
| `containerized_execution_enabled` | Config | Feature flag for opt-in container execution |

---

## Comparison: Before vs After

| Aspect | Before (In-Process) | After (Containerized) |
|--------|--------------------|-----------------------|
| MCP filesystem scope | `Rails.root` + `/tmp` | `/workspace` only |
| Database access | Full ActiveRecord | None (callback API only) |
| Environment variables | All ENV vars visible | Only scoped API key |
| Network access | Unrestricted | LLM APIs + callback only |
| Resource limits | None (Ruby-level only) | Docker-enforced CPU/memory/time |
| File cleanup | Manual (often missed) | Automatic (container destroyed) |
| Output files | Not supported | Active Storage attachments |
| Blast radius of prompt injection | Full server compromise | Isolated to `/workspace` |
| State isolation between runs | Shared Sidekiq process | Fresh container per run |
