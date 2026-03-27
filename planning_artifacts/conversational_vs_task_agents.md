# Conversational vs Task Agents - Comparison

**Date:** 2026-03-20

---

## Side-by-Side Comparison

| Feature | Conversational Agent | Task Agent |
|---------|---------------------|------------|
| **Purpose** | Interactive chat with users | Autonomous task execution |
| **Trigger** | External HTTP request (user message) | Scheduled (cron) or manual |
| **State Management** | AgentConversation (multi-turn history) | TaskRun (execution history) |
| **Input** | User message string | Initial prompt template + variables |
| **Output** | Response text to user | Structured result via functions |
| **Execution Pattern** | Reactive (waits for user) | Proactive (runs on schedule) |
| **Duration** | Short (seconds) | Can be long-running (minutes/hours) |
| **Interaction Model** | Multi-turn dialogue | Single autonomous execution |
| **Function Calling** | Yes (during conversation) | Yes (for data & output) |
| **Conversation TTL** | Yes (expires after inactivity) | N/A (stateless) |
| **Scheduling** | N/A | Cron or interval-based |
| **Retry Logic** | N/A (user retries manually) | Automatic retry on failure |
| **Cost Tracking** | Per conversation | Per task run |
| **Use Cases** | Customer support, Q&A, assistants | Data scraping, reports, monitoring |

---

## Shared Infrastructure

Both agent types share:

✅ **DeployedAgent model** (with `agent_type` field)  
✅ **PromptVersion** (defines agent behavior)  
✅ **FunctionDefinition** (executable functions)  
✅ **LlmResponse tracking** (all LLM calls)  
✅ **FunctionExecution tracking** (all function calls)  
✅ **API key authentication**  
✅ **Rate limiting**  
✅ **Pause/resume functionality**  
✅ **Error handling**

---

## Unique to Conversational Agents

- **AgentConversation** model (message history)
- **deployment_config** (conversation_ttl, allowed_origins)
- **Public chat endpoint** (`/agents/:slug/chat`)
- **Web UI for chatting** (optional)
- **Conversation state** (messages array)
- **Real-time responses** (synchronous HTTP)

---

## Unique to Task Agents

- **TaskRun** model (execution history)
- **TaskSchedule** model (when to run)
- **task_config** (initial_prompt, variables, execution settings)
- **Manual trigger endpoint** (`/agents/:slug/run`)
- **Autonomous loop** (multi-turn until complete)
- **Completion criteria** (auto-detect or explicit)
- **Scheduled execution** (cron-based)
- **Background jobs** (asynchronous)
- **Iteration tracking** (how many LLM calls)
- **Output summary** (final result)

---

## Configuration Examples

### Conversational Agent

```ruby
DeployedAgent.create!(
  agent_type: "conversational",
  name: "Customer Support Bot",
  prompt_version: support_version,
  deployment_config: {
    auth: { type: "api_key" },
    rate_limit: { requests_per_minute: 60 },
    conversation_ttl: 3600,
    allowed_origins: ["https://example.com"],
    enable_web_ui: true
  }
)
```

### Task Agent

```ruby
DeployedAgent.create!(
  agent_type: "task",
  name: "Daily Real Estate Scraper",
  prompt_version: scraper_version,
  task_config: {
    initial_prompt: "Fetch all new listings from {{source_url}}",
    variables: { source_url: "https://example.com" },
    execution: {
      max_iterations: 5,
      timeout_seconds: 3600,
      retry_on_failure: true,
      max_retries: 3
    },
    completion_criteria: {
      type: "auto" # or "explicit"
    }
  }
)
```

---

## Execution Flow Comparison

### Conversational Agent Flow

```
1. User sends message via HTTP POST
2. Load or create AgentConversation
3. Add user message to conversation history
4. Call LLM with full conversation context
5. Execute any function calls
6. Add assistant response to conversation
7. Return response to user immediately
8. Extend conversation TTL
```

### Task Agent Flow

```
1. Schedule triggers or user clicks "Run Now"
2. Create TaskRun record (status: queued)
3. Enqueue background job
4. Job updates TaskRun (status: running)
5. Render initial prompt with variables
6. Loop (up to max_iterations):
   - Call LLM with current prompt
   - Execute any function calls
   - Check if task complete
   - If not, continue with next iteration
7. Update TaskRun (status: completed/failed)
8. Store output summary and stats
```

---

## When to Use Each Type

### Use Conversational Agent When:
- ✅ You need interactive dialogue with users
- ✅ Users ask questions and expect immediate responses
- ✅ Context from previous messages is important
- ✅ You're building a chatbot, assistant, or support agent
- ✅ Execution is triggered by user actions

**Examples:**
- Customer support chatbot
- Product recommendation assistant
- FAQ answering bot
- Interactive troubleshooting guide

### Use Task Agent When:
- ✅ You need autonomous execution on a schedule
- ✅ The task is self-contained (doesn't need user input)
- ✅ You want to automate repetitive workflows
- ✅ Output is delivered via functions (email, webhook, etc.)
- ✅ Execution can take longer than a few seconds

**Examples:**
- Daily data scraping and reporting
- Hourly competitor price monitoring
- Weekly analytics report generation
- Automated content creation and posting
- Periodic database cleanup tasks

---

## Migration Path

### Converting Conversational → Task

If you have a conversational agent that you want to run on schedule:

1. Create new task agent with same PromptVersion
2. Configure initial_prompt (what user would normally say)
3. Set up schedule
4. Add output delivery functions (email, webhook, etc.)

### Converting Task → Conversational

If you have a task agent that you want to make interactive:

1. Create new conversational agent with same PromptVersion
2. Configure deployment_config
3. Remove scheduling
4. Adjust prompt to be more conversational

---

## Cost Comparison

### Conversational Agent Costs
- **Per conversation**: Sum of all LLM calls in conversation
- **Varies by**: Conversation length, user engagement
- **Typical**: $0.001 - $0.05 per conversation

### Task Agent Costs
- **Per task run**: Sum of all LLM calls + function executions
- **Varies by**: Task complexity, iterations needed
- **Typical**: $0.01 - $0.50 per run
- **Monthly**: Cost per run × runs per day × 30

**Example:**
- Daily scraper: $0.05/run × 1 run/day × 30 days = $1.50/month
- Hourly monitor: $0.02/run × 24 runs/day × 30 days = $14.40/month

---

## Summary

Both agent types leverage the same core infrastructure but serve different purposes:

- **Conversational agents** are for **interactive, user-driven** experiences
- **Task agents** are for **autonomous, scheduled** workflows

By extending the DeployedAgent model with an `agent_type` field, we get the best of both worlds while maximizing code reuse and maintaining consistency across the system.

