# MCP Integration Phase 1: Static Credentials PRD

**Status:** Draft
**Created:** 2026-03-24
**Owner:** Engineering Team
**Phase:** 1 of 2 (Static Credentials Only)

---

## Executive Summary

This PRD defines Phase 1 of integrating the Model Context Protocol (MCP) into the PromptTracker Rails engine. Phase 1 focuses on **local (stdio) and private remote (HTTP with static API keys) MCP servers**, enabling agents to use external tools without requiring per-user OAuth flows.

**Key Deliverables:**
- Configuration system for MCP servers in initializers
- MCP client manager service for connection lifecycle
- Dynamic tool discovery and execution
- UI for selecting MCP servers in PromptVersion editor
- Runtime integration with TaskAgentRuntimeService and AgentRuntimeService

**Out of Scope (Phase 2):**
- OAuth 2.1 flows for user-specific authorization
- Multi-tenant SaaS MCP servers (Slack, GitHub, etc.)
- Database-backed MCP connection management

---

## Background

### What is MCP?

The Model Context Protocol (MCP) is an open standard that enables AI applications to connect to external tools and data sources through a unified interface. Instead of building custom integrations for each tool (Slack, GitHub, databases, etc.), MCP provides:

- **Standardized protocol** for tool discovery (`tools/list`)
- **Standardized execution** for tool calls (`tools/call`)
- **Two transport types:**
  - **stdio:** Local subprocess (e.g., filesystem access, local scripts)
  - **HTTP/SSE:** Remote servers (e.g., internal APIs, third-party services)

### Why MCP?

**Current State:**
- Custom functions are stored in the database (`FunctionDefinition` model)
- Each new integration requires custom code
- No standard way to connect to external tools

**With MCP:**
- Agents can use any MCP-compatible tool without custom code
- Tools are discovered dynamically at runtime
- Standard protocol reduces integration complexity

### Architecture Decision

**Phase 1 focuses on static credentials** because:
1. **Simpler implementation** - No OAuth flows, no database changes
2. **Immediate value** - Enables local tools and internal APIs
3. **Foundation for Phase 2** - OAuth builds on this infrastructure
4. **Lower risk** - Fewer moving parts, easier to test

---

## Goals & Non-Goals

### Goals

1. **Enable local MCP servers** via stdio transport
   - Filesystem access, local scripts, command-line tools
   - Configured with environment variables

2. **Enable private remote MCP servers** via HTTP transport
   - Internal company APIs, private third-party services
   - Authenticated with static API keys from config

3. **Dynamic tool discovery**
   - Fetch available tools from MCP servers at runtime
   - Present tools to LLM alongside database functions

4. **Seamless execution**
   - Route tool calls to appropriate MCP server
   - Handle errors and return results to LLM

5. **User-friendly configuration**
   - Configure MCP servers in Rails initializer
   - Select MCP servers in PromptVersion editor UI

### Non-Goals (Deferred to Phase 2)

- ❌ OAuth 2.1 authorization flows
- ❌ Per-user MCP connections
- ❌ Multi-tenant SaaS MCP servers (Slack, GitHub, Google Drive)
- ❌ Database-backed credential storage
- ❌ MCP server health monitoring/retry logic
- ❌ MCP server version negotiation

---

## User Stories

### Story 1: Configure Local MCP Server
**As a** developer
**I want to** configure a local filesystem MCP server in the initializer
**So that** agents can read/write files during task execution

**Acceptance Criteria:**
- [ ] Can define stdio MCP server in `test/dummy/config/initializers/prompt_tracker.rb`
- [ ] Can specify command, args, and environment variables
- [ ] Configuration is validated on Rails boot
- [ ] Invalid configuration raises clear error message

---

### Story 2: Configure Private Remote MCP Server
**As a** developer
**I want to** configure a private HTTP MCP server with a static API key
**So that** agents can call internal company APIs

**Acceptance Criteria:**
- [ ] Can define HTTP MCP server with URL and API key
- [ ] API key can be loaded from environment variable
- [ ] Configuration supports multiple remote servers
- [ ] Connection is tested on first use (not at boot)

---

### Story 3: Select MCP Servers in PromptVersion
**As a** prompt engineer
**I want to** select which MCP servers are available to a PromptVersion
**So that** I can control which tools the agent can use

**Acceptance Criteria:**
- [ ] PromptVersion editor shows list of configured MCP servers
- [ ] Can select/deselect MCP servers via checkboxes
- [ ] Selection is saved in `model_config[:mcp_servers]`
- [ ] Only shows servers with valid credentials configured

---

### Story 4: Execute MCP Tools in TaskRun
**As a** task agent
**I want to** automatically discover and execute MCP tools
**So that** I can accomplish tasks using external tools

**Acceptance Criteria:**
- [ ] MCP tools appear in LLM's tool list alongside database functions
- [ ] LLM can call MCP tools by name
- [ ] Tool calls are routed to correct MCP server
- [ ] Results are returned to LLM in standard format
- [ ] Errors are handled gracefully with clear messages

---

### Story 5: Execute MCP Tools in Conversation
**As a** conversational agent
**I want to** use MCP tools during chat interactions
**So that** I can provide dynamic responses using external data

**Acceptance Criteria:**
- [ ] Same tool discovery/execution as TaskRun
- [ ] Works with both streaming and non-streaming responses
- [ ] Tool calls are logged in conversation history

---

## Technical Design

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Configuration Layer                                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ test/dummy/config/initializers/prompt_tracker.rb        │ │
│ │                                                           │ │
│ │ PromptTracker.configure do |config|                      │ │
│ │   config.mcp_servers = {                                 │ │
│ │     "filesystem" => {                                    │ │
│ │       transport: "stdio",                                │ │
│ │       command: "npx",                                    │ │
│ │       args: ["-y", "@modelcontextprotocol/server-fs"],  │ │
│ │       env: { "ALLOWED_PATHS" => "/tmp" }                │ │
│ │     },                                                    │ │
│ │     "internal_api" => {                                  │ │
│ │       transport: "http",                                 │ │
│ │       url: "https://mcp.company.com",                   │ │
│ │       api_key: ENV["INTERNAL_MCP_KEY"]                  │ │
│ │     }                                                     │ │
│ │   }                                                       │ │
│ │ end                                                       │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Model Layer                                                 │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ PromptVersion                                            │ │
│ │                                                           │ │
│ │ model_config: {                                          │ │
│ │   model: "gpt-4",                                        │ │
│ │   temperature: 0.7,                                      │ │
│ │   mcp_servers: ["filesystem", "internal_api"]           │ │
│ │ }                                                         │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Service Layer                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ McpClientManager                                         │ │
│ │                                                           │ │
│ │ - connect(server_name)                                   │ │
│ │ - list_tools(server_name)                                │ │
│ │ - call_tool(server_name, tool_name, arguments)          │ │
│ │ - disconnect(server_name)                                │ │
│ │ - disconnect_all                                         │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ McpConnection (stdio or HTTP)                            │ │
│ │                                                           │ │
│ │ - send_request(method, params)                           │ │
│ │ - receive_response                                       │ │
│ │ - close                                                  │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Runtime Layer                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ TaskAgentRuntimeService / AgentRuntimeService            │ │
│ │                                                           │ │
│ │ 1. Initialize McpClientManager                           │ │
│ │ 2. Connect to selected MCP servers                       │ │
│ │ 3. Fetch tools from MCP + database                       │ │
│ │ 4. Send tools to LLM                                     │ │
│ │ 5. Route tool calls:                                     │ │
│ │    - MCP tools → McpClientManager                        │ │
│ │    - DB functions → existing executor                    │ │
│ │ 6. Return results to LLM                                 │ │
│ │ 7. Disconnect MCP servers on completion                  │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### Component Details

#### 1. Configuration (`lib/prompt_tracker/configuration.rb`)

**New attribute:**
```ruby
attr_accessor :mcp_servers
```

**Schema:**
```ruby
{
  "server_name" => {
    transport: "stdio" | "http",

    # For stdio transport:
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-fs"],
    env: { "ENV_VAR" => "value" },

    # For HTTP transport:
    url: "https://mcp.example.com",
    api_key: "static_key_or_env_var"
  }
}
```

**Validation:**
- Each server must have a unique name
- `transport` must be "stdio" or "http"
- stdio servers must have `command` (string)
- HTTP servers must have `url` (string)
- `args` and `env` are optional for stdio
- `api_key` is optional for HTTP (some servers may be public)

---

#### 2. McpClientManager Service

**Location:** `app/services/prompt_tracker/mcp_client_manager.rb`

**Responsibilities:**
- Manage lifecycle of multiple MCP connections
- Provide unified interface for tool discovery and execution
- Handle connection pooling and cleanup
- Convert MCP tool schemas to OpenAI/Anthropic format

**Key Methods:**

```ruby
class McpClientManager
  def initialize(server_names)
    # server_names: Array of server names from PromptVersion config
    # Looks up server configs from PromptTracker.configuration.mcp_servers
  end

  def connect_all
    # Establish connections to all configured servers
    # Returns hash of { server_name => connection_status }
  end

  def list_all_tools
    # Fetch tools from all connected servers
    # Returns array of tool definitions in OpenAI/Anthropic format
    # Each tool is prefixed with server name (e.g., "filesystem__read_file")
  end

  def call_tool(tool_name, arguments)
    # Parse server name from tool_name prefix
    # Route to appropriate MCP server
    # Return result or raise error
  end

  def disconnect_all
    # Close all connections gracefully
    # Clean up subprocess handles
  end
end
```

**Tool Name Prefixing:**
To avoid conflicts between MCP tools and database functions, MCP tools are prefixed:
- Original MCP tool: `read_file`
- Exposed to LLM: `filesystem__read_file`
- When LLM calls `filesystem__read_file`, manager routes to `filesystem` server's `read_file` tool

---

#### 3. McpConnection Classes

**Base Class:** `app/services/prompt_tracker/mcp_connection/base.rb`

```ruby
module PromptTracker
  module McpConnection
    class Base
      def initialize(config)
        @config = config
      end

      def connect
        raise NotImplementedError
      end

      def send_request(method, params = {})
        # Send JSON-RPC 2.0 request
        # { jsonrpc: "2.0", id: 1, method: method, params: params }
      end

      def receive_response
        # Read and parse JSON-RPC response
      end

      def close
        raise NotImplementedError
      end
    end
  end
end
```

**Stdio Implementation:** `app/services/prompt_tracker/mcp_connection/stdio.rb`

```ruby
class Stdio < Base
  def connect
    # Use Open3.popen3 to spawn subprocess
    # Pass env vars from config
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(
      @config[:env] || {},
      @config[:command],
      *@config[:args]
    )
  end

  def send_request(method, params = {})
    request = { jsonrpc: "2.0", id: next_id, method: method, params: params }
    @stdin.puts(request.to_json)
  end

  def receive_response
    line = @stdout.gets
    JSON.parse(line)
  end

  def close
    @stdin.close
    @stdout.close
    @stderr.close
    @wait_thr.join
  end
end
```

**HTTP Implementation:** `app/services/prompt_tracker/mcp_connection/http.rb`

```ruby
class Http < Base
  def connect
    # Establish SSE connection to server
    # Send Authorization header if api_key present
    @uri = URI(@config[:url])
    @http = Net::HTTP.new(@uri.host, @uri.port)
    @http.use_ssl = @uri.scheme == "https"
  end

  def send_request(method, params = {})
    request = Net::HTTP::Post.new(@uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@config[:api_key]}" if @config[:api_key]
    request.body = { jsonrpc: "2.0", id: next_id, method: method, params: params }.to_json

    @response = @http.request(request)
  end

  def receive_response
    JSON.parse(@response.body)
  end

  def close
    @http.finish if @http.started?
  end
end
```

---

#### 4. Runtime Integration

**Changes to `TaskAgentRuntimeService` and `AgentRuntimeService`:**

**Step 1: Initialize MCP Manager**
```ruby
def initialize(task_run_or_conversation, prompt_version)
  @prompt_version = prompt_version
  @mcp_manager = initialize_mcp_manager if mcp_enabled?
  # ... existing initialization
end

private

def mcp_enabled?
  @prompt_version.model_config.dig(:mcp_servers).present?
end

def initialize_mcp_manager
  server_names = @prompt_version.model_config[:mcp_servers]
  McpClientManager.new(server_names).tap(&:connect_all)
end
```

**Step 2: Merge MCP Tools with Database Functions**
```ruby
def build_tools_payload
  tools = []

  # Existing database functions
  tools += @prompt_version.function_definitions.map(&:to_openai_format)

  # MCP tools (if enabled)
  tools += @mcp_manager.list_all_tools if @mcp_manager

  tools
end
```

**Step 3: Route Tool Calls**
```ruby
def execute_tool_call(tool_name, arguments)
  # Check if it's an MCP tool (has __ prefix)
  if tool_name.include?("__") && @mcp_manager
    @mcp_manager.call_tool(tool_name, arguments)
  else
    # Existing database function execution
    execute_regular_function(tool_name, arguments)
  end
end
```

**Step 4: Cleanup**
```ruby
def cleanup
  @mcp_manager&.disconnect_all
  # ... existing cleanup
end
```

---

#### 5. UI Changes

**PromptVersion Editor (`app/views/prompt_tracker/prompt_versions/_form.html.erb`)**

Add new section for MCP server selection:

```erb
<div class="form-group">
  <label>MCP Servers</label>
  <p class="text-muted">Select external tool servers for this prompt</p>

  <% PromptTracker.configuration.mcp_servers.each do |server_name, config| %>
    <div class="form-check">
      <%= check_box_tag(
        "prompt_version[model_config][mcp_servers][]",
        server_name,
        @prompt_version.model_config.dig(:mcp_servers)&.include?(server_name),
        id: "mcp_server_#{server_name}",
        class: "form-check-input"
      ) %>
      <label class="form-check-label" for="mcp_server_<%= server_name %>">
        <strong><%= server_name %></strong>
        <span class="badge badge-secondary"><%= config[:transport] %></span>
        <% if config[:transport] == "stdio" %>
          <small class="text-muted"><%= config[:command] %></small>
        <% else %>
          <small class="text-muted"><%= config[:url] %></small>
        <% end %>
      </label>
    </div>
  <% end %>
</div>
```

---

### Data Flow Example

**Scenario:** Agent needs to read a file during task execution

1. **Configuration** (initializer):
   ```ruby
   config.mcp_servers = {
     "filesystem" => {
       transport: "stdio",
       command: "npx",
       args: ["-y", "@modelcontextprotocol/server-filesystem"],
       env: { "ALLOWED_PATHS" => "/tmp" }
     }
   }
   ```

2. **PromptVersion** (model_config):
   ```ruby
   { mcp_servers: ["filesystem"] }
   ```

3. **Runtime Initialization**:
   ```ruby
   manager = McpClientManager.new(["filesystem"])
   manager.connect_all
   # Spawns: npx -y @modelcontextprotocol/server-filesystem
   # with env: ALLOWED_PATHS=/tmp
   ```

4. **Tool Discovery**:
   ```ruby
   tools = manager.list_all_tools
   # Sends: { method: "tools/list" }
   # Receives: { tools: [{ name: "read_file", ... }] }
   # Returns: [{ type: "function", function: { name: "filesystem__read_file", ... } }]
   ```

5. **LLM Receives Tools**:
   ```json
   {
     "tools": [
       {
         "type": "function",
         "function": {
           "name": "filesystem__read_file",
           "description": "Read contents of a file",
           "parameters": {
             "type": "object",
             "properties": {
               "path": { "type": "string" }
             }
           }
         }
       }
     ]
   }
   ```

6. **LLM Calls Tool**:
   ```json
   {
     "tool_calls": [{
       "function": {
         "name": "filesystem__read_file",
         "arguments": "{\"path\":\"/tmp/data.txt\"}"
       }
     }]
   }
   ```

7. **Runtime Routes Call**:
   ```ruby
   result = manager.call_tool("filesystem__read_file", { path: "/tmp/data.txt" })
   # Parses server name: "filesystem"
   # Sends to filesystem server: { method: "tools/call", params: { name: "read_file", arguments: {...} } }
   # Receives: { result: { content: "file contents..." } }
   ```

8. **Result Returned to LLM**:
   ```json
   {
     "role": "tool",
     "tool_call_id": "call_123",
     "content": "file contents..."
   }
   ```

---

## Implementation Plan

### Phase 1.1: Foundation (Week 1)

**Tasks:**
- [ ] Add `mcp_servers` attribute to `Configuration` class
- [ ] Create `McpClientManager` service skeleton
- [ ] Create `McpConnection::Base` abstract class
- [ ] Implement `McpConnection::Stdio` with basic JSON-RPC
- [ ] Write unit tests for stdio connection

**Deliverable:** Can spawn local MCP server and send/receive JSON-RPC messages

---

### Phase 1.2: Tool Discovery (Week 1-2)

**Tasks:**
- [ ] Implement `McpClientManager#list_all_tools`
- [ ] Convert MCP tool schema to OpenAI/Anthropic format
- [ ] Add tool name prefixing logic
- [ ] Write tests for tool discovery and conversion

**Deliverable:** Can fetch tools from MCP server and convert to LLM format

---

### Phase 1.3: Runtime Integration (Week 2)

**Tasks:**
- [ ] Integrate `McpClientManager` into `TaskAgentRuntimeService`
- [ ] Integrate `McpClientManager` into `AgentRuntimeService`
- [ ] Modify tool payload building to include MCP tools
- [ ] Implement tool call routing logic
- [ ] Add cleanup/disconnect logic
- [ ] Write integration tests

**Deliverable:** TaskRuns and Conversations can execute MCP tools

---

### Phase 1.4: HTTP Transport (Week 2-3)

**Tasks:**
- [ ] Implement `McpConnection::Http` class
- [ ] Add Authorization header support
- [ ] Handle SSE streaming (if needed)
- [ ] Write tests for HTTP connection
- [ ] Test with real HTTP MCP server

**Deliverable:** Can connect to remote MCP servers with static API keys

---

### Phase 1.5: UI & Polish (Week 3)

**Tasks:**
- [ ] Add MCP server selection UI to PromptVersion editor
- [ ] Add visual indicators for MCP vs database functions
- [ ] Add error handling and user-friendly messages
- [ ] Write system tests for end-to-end flow
- [ ] Update documentation

**Deliverable:** Complete Phase 1 ready for production

---

## Testing Strategy

### Unit Tests

**McpConnection::Stdio:**
- ✅ Spawns subprocess with correct command/args
- ✅ Passes environment variables
- ✅ Sends valid JSON-RPC requests
- ✅ Parses JSON-RPC responses
- ✅ Handles subprocess errors
- ✅ Cleans up resources on close

**McpConnection::Http:**
- ✅ Establishes HTTP connection
- ✅ Sends Authorization header when api_key present
- ✅ Handles SSL/TLS
- ✅ Parses JSON responses
- ✅ Handles network errors

**McpClientManager:**
- ✅ Initializes connections for multiple servers
- ✅ Fetches tools from all servers
- ✅ Prefixes tool names correctly
- ✅ Routes tool calls to correct server
- ✅ Handles missing servers gracefully
- ✅ Disconnects all connections

---

### Integration Tests

**TaskAgentRuntimeService:**
- ✅ Initializes MCP manager when `mcp_servers` configured
- ✅ Includes MCP tools in LLM payload
- ✅ Routes MCP tool calls correctly
- ✅ Routes database function calls correctly
- ✅ Returns MCP results to LLM
- ✅ Disconnects MCP on task completion

**AgentRuntimeService:**
- ✅ Same as TaskAgentRuntimeService for conversations

---

### System Tests

**End-to-End Flow:**
1. Configure filesystem MCP server in initializer
2. Create PromptVersion with filesystem server selected
3. Create TaskRun that requires reading a file
4. Verify file is read via MCP
5. Verify task completes successfully

---

## Error Handling

### Connection Errors

**Scenario:** MCP server fails to start or connect

**Handling:**
- Log error with server name and config
- Raise `McpConnectionError` with user-friendly message
- Do NOT fail silently - surface to user

**Example:**
```ruby
raise McpConnectionError, "Failed to connect to MCP server 'filesystem': Command 'npx' not found"
```

---

### Tool Execution Errors

**Scenario:** MCP server returns error for tool call

**Handling:**
- Parse error from JSON-RPC response
- Return error to LLM as tool result
- LLM can retry or handle gracefully

**Example:**
```ruby
{
  role: "tool",
  tool_call_id: "call_123",
  content: "Error: File not found: /tmp/missing.txt"
}
```

---

### Configuration Errors

**Scenario:** Invalid MCP server configuration

**Handling:**
- Validate on Rails boot
- Raise clear error with fix instructions

**Example:**
```ruby
raise ConfigurationError, "MCP server 'filesystem' missing required 'command' field"
```

---

## Security Considerations

### Stdio Servers

**Risk:** Arbitrary command execution

**Mitigation:**
- Only allow configured commands (no user input)
- Validate command exists before spawning
- Use `Open3.popen3` (safer than `system` or backticks)
- Set resource limits on subprocess (future enhancement)

---

### HTTP Servers

**Risk:** API key exposure

**Mitigation:**
- Store API keys in environment variables (not in code)
- Use HTTPS for all remote connections
- Validate SSL certificates
- Never log API keys

---

### Tool Arguments

**Risk:** Injection attacks via tool arguments

**Mitigation:**
- MCP servers are responsible for validating arguments
- Our app passes arguments as-is (JSON)
- Trust MCP server to sanitize (same as trusting database functions)

---

## Monitoring & Observability

### Logging

**What to log:**
- MCP connection lifecycle (connect, disconnect)
- Tool discovery results (number of tools found)
- Tool execution (tool name, server, duration)
- Errors (connection failures, tool errors)

**Log Level:**
- INFO: Connection lifecycle, tool discovery
- DEBUG: Individual tool calls, JSON-RPC messages
- ERROR: Connection failures, tool errors

**Example:**
```
[INFO] McpClientManager: Connected to 2 servers: filesystem, internal_api
[INFO] McpClientManager: Discovered 15 tools from 2 servers
[DEBUG] McpClientManager: Calling tool filesystem__read_file with args: {"path":"/tmp/data.txt"}
[ERROR] McpConnection::Stdio: Failed to spawn process: Command not found: npx
```

---

### Metrics (Future Enhancement)

- MCP connection success/failure rate
- Tool execution latency by server
- Tool usage frequency
- Error rate by server/tool

---

## Documentation

### Developer Documentation

**Files to create:**
- `docs/mcp_integration.md` - Overview and architecture
- `docs/mcp_configuration.md` - How to configure MCP servers
- `docs/mcp_custom_servers.md` - How to build custom MCP servers

**Content:**
- Architecture diagrams
- Configuration examples
- Troubleshooting guide
- FAQ

---

### User Documentation

**Files to update:**
- `README.md` - Add MCP section
- PromptVersion editor help text

**Content:**
- What is MCP?
- How to select MCP servers
- Available MCP servers
- Example use cases

---

## Success Criteria

### Phase 1 Complete When:

- ✅ Can configure local stdio MCP servers in initializer
- ✅ Can configure remote HTTP MCP servers with static API keys
- ✅ Can select MCP servers in PromptVersion editor
- ✅ MCP tools appear in LLM tool list
- ✅ LLM can successfully call MCP tools
- ✅ Tool results are returned to LLM correctly
- ✅ Works in both TaskRuns and Conversations
- ✅ All tests passing (unit, integration, system)
- ✅ Documentation complete
- ✅ No regressions in existing functionality

---

## Future Enhancements (Phase 2)

### OAuth 2.1 Support

- Add `McpConnection` model to database
- Implement OAuth authorization flow
- Store access/refresh tokens per user
- Handle token refresh automatically
- Support multi-tenant SaaS MCPs (Slack, GitHub, etc.)

### Advanced Features

- MCP server health checks
- Automatic reconnection on failure
- Tool result caching
- Parallel tool execution
- MCP server version negotiation
- Resource and prompt support (beyond tools)

---

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| MCP spec changes | High | Medium | Pin to specific MCP version, monitor spec updates |
| Subprocess management complexity | Medium | High | Use battle-tested `Open3`, add resource limits |
| HTTP connection reliability | Medium | Medium | Add retry logic, timeout handling |
| Tool name conflicts | Low | Low | Use prefixing, validate uniqueness |
| Performance impact | Medium | Low | Lazy connection, connection pooling |

---

## Appendix

### MCP Protocol Reference

**JSON-RPC 2.0 Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "read_file",
        "description": "Read contents of a file",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": { "type": "string" }
          },
          "required": ["path"]
        }
      }
    ]
  }
}
```

---

### Example MCP Servers

**Local (stdio):**
- `@modelcontextprotocol/server-filesystem` - File operations
- `@modelcontextprotocol/server-sqlite` - SQLite database access
- `@modelcontextprotocol/server-git` - Git operations
- Custom scripts (Python, Node.js, etc.)

**Remote (HTTP with static keys):**
- Internal company APIs
- Private third-party services
- Self-hosted MCP servers

---

### Configuration Examples

**Minimal stdio:**
```ruby
config.mcp_servers = {
  "filesystem" => {
    transport: "stdio",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem"]
  }
}
```

**With environment variables:**
```ruby
config.mcp_servers = {
  "database" => {
    transport: "stdio",
    command: "python",
    args: ["mcp_servers/database_server.py"],
    env: {
      "DB_HOST" => ENV["DB_HOST"],
      "DB_PASSWORD" => ENV["DB_PASSWORD"]
    }
  }
}
```

**Remote HTTP:**
```ruby
config.mcp_servers = {
  "internal_api" => {
    transport: "http",
    url: "https://mcp.company.com",
    api_key: ENV["INTERNAL_MCP_KEY"]
  }
}
```

---

## Questions & Decisions

### Open Questions

1. **Should we support MCP resources and prompts in Phase 1?**
   - Decision: No, focus on tools only. Resources/prompts in Phase 2.

2. **Should we cache tool lists or fetch on every execution?**
   - Decision: Fetch on every execution for Phase 1. Add caching in Phase 2 if needed.

3. **Should we support multiple versions of the same MCP server?**
   - Decision: No, one instance per server name. Use different names for different configs.

4. **Should we validate tool arguments before sending to MCP server?**
   - Decision: No, trust MCP server to validate. Reduces complexity.

---

## Changelog

- **2026-03-24:** Initial PRD created for Phase 1
