# Agent Deployment & Function Registry PRD

## Overview

Enable users to deploy prompt versions as live, interactive agents accessible via unique URLs, with a reusable function library for building sophisticated agentic workflows.

## Problem Statement

Currently, PromptTracker excels at:
- Testing prompts in the playground
- Tracking production LLM calls via `LlmCallService.track`
- Evaluating responses

However, users cannot:
1. **Deploy agents directly** - No way to expose a prompt version as a live agent endpoint
2. **Write executable functions** - Functions are just JSON schemas; users must build external webhooks for execution
3. **Reuse functions** - Functions are defined per-prompt in `model_config.tool_config`, leading to duplication
4. **Share agents** - No mechanism to give external users/systems access to configured agents
5. **Test functions in isolation** - No way to test function code before using in agents

This limits PromptTracker to being a testing/monitoring tool rather than a complete agent development platform.

**The Vision**: Users should be able to write function code directly in the browser (like AWS Lambda), test it, save it to a library, and deploy agents that execute these functions automatically - all without leaving PromptTracker.

## Goals

### Primary Goals
1. **Code-Based Function Library**: Write, test, and reuse executable Ruby functions directly in the browser
2. **In-Browser Code Editor**: Monaco editor (VS Code) with syntax highlighting, autocomplete, and error detection
3. **Sandboxed Execution**: Safe, isolated execution environment for user code with resource limits
4. **Agent Deployment**: One-click deployment of prompt versions as live agents with unique URLs
5. **Agent Runtime**: Robust execution environment for deployed agents with conversation state management
6. **Production Monitoring**: Track all deployed agent interactions through existing monitoring infrastructure

### Secondary Goals
- Environment variables management for API keys and secrets
- Function testing interface with sample inputs/outputs
- Package/gem management for function dependencies
- Deployment management: pause/resume, versioning, rollback
- Usage analytics: calls per agent, function usage, cost tracking, execution time
- Authentication & rate limiting for deployed agents

### Non-Goals (Future Phases)
- Multi-language support (Python, JavaScript) - start with Ruby only
- Multi-agent orchestration
- Agent marketplace/sharing between organizations
- Custom billing/monetization per agent
- Advanced IDE features (debugging, breakpoints, step-through)

## Success Metrics

1. **Adoption**: 50% of active users create at least one code-based function within 3 months
2. **Function Reuse**: Average function used in 3+ different agents
3. **Code Execution**: 99.9% of function executions complete successfully within timeout
4. **Agent Uptime**: 99.5% availability for deployed agents
5. **Developer Experience**: <10 minutes from writing first function to deployed agent
6. **Function Library Growth**: 100+ community functions created in first 3 months

## User Stories

### Function Registry

**As a developer**, I want to:
- Write Ruby code for functions directly in the browser with syntax highlighting
- Define function parameters using a visual JSON Schema builder
- Test my function code with sample inputs and see outputs immediately
- Save functions to a searchable library with categories and tags
- Manage environment variables (API keys, secrets) securely
- Install Ruby gems/packages my function needs
- See execution logs and errors when my function fails
- Import functions from the library into my playground
- See which agents are using each function
- Version function definitions when I update them
- Fork existing functions to create variations

**As a prompt engineer**, I want to:
- Search for existing functions before creating new ones
- Preview function code and understand what it does
- Test functions with different inputs to see how they behave
- Use functions without understanding the implementation details
- Share function definitions with my team
- See example usage and documentation for each function

### Agent Deployment

**As a developer**, I want to:
- Click "Deploy" on any active prompt version
- Get a unique, secure URL for my agent (e.g., `https://app.com/agents/customer-support-v2`)
- Configure deployment settings (rate limits, authentication, allowed origins)
- See deployment status (active, paused, error)
- View real-time logs of agent interactions
- Pause/resume deployments without losing configuration
- Roll back to previous versions if issues arise
- Delete deployments when no longer needed

**As an API consumer**, I want to:
- Send messages to deployed agents via simple HTTP POST
- Receive streaming or complete responses
- Maintain conversation context across multiple requests
- Get clear error messages when something fails
- See API documentation for each deployed agent

### Agent Runtime

**As a system**, I need to:
- Load prompt version configuration (system_prompt, model_config, tools)
- Execute function calls by routing to configured implementations
- Manage conversation state (in-memory or persisted)
- Track all interactions as LlmResponses for monitoring
- Handle errors gracefully (function failures, LLM errors, rate limits)
- Respect deployment configuration (auth, rate limits)
- Clean up stale conversation state

## Technical Architecture

### Phase 1: Function Registry (Foundation)

#### New Models

```ruby
# app/models/prompt_tracker/function_definition.rb
class FunctionDefinition < ApplicationRecord
  # Columns:
  # - name: string (unique, indexed)
  # - description: text
  # - parameters: jsonb (JSON Schema)
  # - code: text (Ruby source code)
  # - language: string (default: "ruby")
  # - category: string (e.g., "weather", "database", "email")
  # - tags: jsonb (array of strings)
  # - environment_variables: jsonb (encrypted, key-value pairs)
  # - dependencies: jsonb (array of gem names/versions)
  # - example_input: jsonb (sample arguments for testing)
  # - example_output: jsonb (expected output for example_input)
  # - version: integer
  # - created_by: string
  # - usage_count: integer (counter cache)
  # - last_executed_at: datetime
  # - execution_count: integer (counter cache)
  # - average_execution_time_ms: integer

  has_many :function_executions, dependent: :destroy
  has_many :deployed_agents, through: :function_executions

  validates :name, presence: true, uniqueness: true
  validates :code, presence: true
  validates :language, inclusion: { in: %w[ruby] } # Start with Ruby only
  validate :parameters_must_be_valid_json_schema
  validate :code_must_be_valid_ruby

  encrypts :environment_variables

  # Test the function with sample input
  def test(arguments = {})
    CodeExecutor.execute(
      code: code,
      arguments: arguments,
      environment_variables: environment_variables,
      dependencies: dependencies
    )
  end

  # Execute the function (used by agents)
  def execute(arguments)
    result = test(arguments)

    # Update stats
    increment!(:execution_count)
    update!(last_executed_at: Time.current)
    update_average_execution_time(result[:execution_time_ms])

    result
  end

  private

  def update_average_execution_time(new_time_ms)
    if average_execution_time_ms.nil?
      update!(average_execution_time_ms: new_time_ms)
    else
      # Rolling average
      new_avg = ((average_execution_time_ms * (execution_count - 1)) + new_time_ms) / execution_count
      update!(average_execution_time_ms: new_avg)
    end
  end
end

# app/models/prompt_tracker/function_execution.rb
class FunctionExecution < ApplicationRecord
  # Tracks individual function executions for analytics and debugging
  belongs_to :function_definition
  belongs_to :deployed_agent, optional: true # nil for test executions
  belongs_to :agent_conversation, optional: true

  # Columns:
  # - function_definition_id: bigint
  # - deployed_agent_id: bigint (nullable)
  # - agent_conversation_id: bigint (nullable)
  # - arguments: jsonb (input arguments)
  # - result: jsonb (output result)
  # - success: boolean
  # - error_message: text
  # - execution_time_ms: integer
  # - executed_at: datetime

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, -> { where("executed_at > ?", 24.hours.ago) }
end
```

#### UI Components

**Function Library Page** (`/testing/functions`)
- Searchable table with filters (category, language, tags)
- "Create Function" button → opens full-page function editor
- Each row shows: name, description, category, execution count, avg execution time, actions
- Click row → opens function editor in edit mode
- Quick actions: Test, Duplicate, Delete

**Function Editor Page** (`/testing/functions/new` or `/testing/functions/:id/edit`)

Full-page editor with split layout:

**Left Panel (60% width):**
- **Header**: Function name input, category dropdown, tags input
- **Description**: Rich text editor for function documentation
- **Parameters Builder**: Visual JSON Schema builder
  - Add parameter button
  - For each parameter: name, type (string/number/boolean/object/array), description, required checkbox
  - Auto-generates JSON Schema
- **Environment Variables**: Secure key-value pairs
  - Add variable button
  - Each variable: key, value (masked), description
  - Warning: "These are encrypted and only accessible to your function"
- **Dependencies**: Gem management
  - Add gem button
  - Each gem: name, version (optional)
  - Shows installation status

**Right Panel (40% width):**
- **Code Editor**: Monaco editor (VS Code)
  - Syntax highlighting for Ruby
  - Autocomplete for standard library
  - Error detection (linting)
  - Line numbers, minimap
  - Template code pre-filled:
    ```ruby
    # Function: get_weather
    # This function will be called with the parameters you defined

    def execute(**args)
      # Access parameters
      city = args[:city]
      units = args[:units] || "celsius"

      # Access environment variables
      api_key = env['WEATHER_API_KEY']

      # Make HTTP requests (HTTP gem available)
      response = HTTP.get("https://api.weather.com/current", params: {
        q: city,
        units: units,
        appid: api_key
      })

      # Return result (must be JSON-serializable)
      JSON.parse(response.body)
    end
    ```

**Bottom Panel (collapsible):**
- **Test Runner**:
  - Input: JSON editor for test arguments (pre-filled with example_input)
  - "Run Test" button
  - Output: Shows result, execution time, or error message
  - Save as example: Checkbox to save current input/output as example

**Action Buttons** (top right):
- "Test" - Run function with current test input
- "Save" - Save function to library
- "Save & Test" - Save then run test
- "Cancel" - Discard changes

**Playground Integration**
- "Import from Library" button in Functions panel
- Search modal to browse/filter function library
- Select function → copies function code and parameters to playground
- "Save to Library" button - saves current playground function to library

#### Services

**Note**: Initial implementation uses AWS Lambda for code execution instead of Docker for simplicity, security, and scalability. Docker-based execution can be added later as an alternative backend.

```ruby
# app/services/prompt_tracker/code_executor.rb
class CodeExecutor
  # Execute user-written Ruby code using AWS Lambda
  #
  # @param code [String] Ruby source code
  # @param arguments [Hash] function arguments
  # @param environment_variables [Hash] environment variables (API keys, etc.)
  # @param dependencies [Array<String>] gem dependencies
  # @return [Result] execution result with success status, output, errors, and timing

  Result = Struct.new(:success?, :result, :error, :execution_time_ms, :logs, keyword_init: true)

  def self.execute(code:, arguments:, environment_variables: {}, dependencies: [])
    # Delegate to Lambda adapter (can be swapped for Docker later)
    LambdaAdapter.execute(
      code: code,
      arguments: arguments,
      environment_variables: environment_variables,
      dependencies: dependencies
    )
  end
end

# app/services/prompt_tracker/code_executor/lambda_adapter.rb
class CodeExecutor::LambdaAdapter
  # AWS Lambda-based code execution
  # Benefits:
  # - Zero infrastructure management
  # - Built-in sandboxing and security
  # - Automatic scaling
  # - Pay-per-use pricing
  # - Easy to test locally with SAM/LocalStack

  TIMEOUT = 30 # seconds
  MEMORY_SIZE = 512 # MB
  RUNTIME = 'ruby3.2'

  Result = CodeExecutor::Result

  def self.execute(code:, arguments:, environment_variables: {}, dependencies: [])
    new(code, arguments, environment_variables, dependencies).execute
  end

  def initialize(code, arguments, environment_variables, dependencies)
    @code = code
    @arguments = arguments
    @environment_variables = environment_variables
    @dependencies = dependencies
    @lambda_client = Aws::Lambda::Client.new(
      region: PromptTracker.configuration.aws_region,
      credentials: Aws::Credentials.new(
        PromptTracker.configuration.aws_access_key_id,
        PromptTracker.configuration.aws_secret_access_key
      )
    )
  end

  def execute
    start_time = Time.current

    # Create or update Lambda function with user code
    function_name = ensure_lambda_function

    # Invoke Lambda with arguments
    response = invoke_lambda(function_name)

    execution_time_ms = ((Time.current - start_time) * 1000).to_i

    # Parse response
    parse_lambda_response(response, execution_time_ms)
  rescue Aws::Lambda::Errors::ServiceException => e
    Result.new(
      success?: false,
      result: nil,
      error: "Lambda error: #{e.message}",
      execution_time_ms: 0,
      logs: ""
    )
  rescue => e
    Result.new(
      success?: false,
      result: nil,
      error: "Execution error: #{e.message}",
      execution_time_ms: 0,
      logs: ""
    )
  end

  private

  def ensure_lambda_function
    # Generate unique function name based on code hash
    # This allows caching - same code = same Lambda function
    code_hash = Digest::SHA256.hexdigest(@code)[0..15]
    function_name = "#{PromptTracker.configuration.lambda_function_prefix}-#{code_hash}"

    begin
      # Check if function exists
      @lambda_client.get_function(function_name: function_name)

      # Function exists - update code if needed
      @lambda_client.update_function_code(
        function_name: function_name,
        zip_file: build_deployment_package
      )

      # Update environment variables
      @lambda_client.update_function_configuration(
        function_name: function_name,
        environment: { variables: @environment_variables }
      )
    rescue Aws::Lambda::Errors::ResourceNotFoundException
      # Function doesn't exist - create it
      @lambda_client.create_function(
        function_name: function_name,
        runtime: RUNTIME,
        role: PromptTracker.configuration.lambda_execution_role_arn,
        handler: 'function.handler',
        code: { zip_file: build_deployment_package },
        timeout: TIMEOUT,
        memory_size: MEMORY_SIZE,
        environment: { variables: @environment_variables },
        description: "PromptTracker function execution"
      )

      # Wait for function to be active
      @lambda_client.wait_until(:function_active, function_name: function_name)
    end

    function_name
  end

  def invoke_lambda(function_name)
    @lambda_client.invoke(
      function_name: function_name,
      invocation_type: 'RequestResponse', # Synchronous
      log_type: 'Tail', # Include logs in response
      payload: { arguments: @arguments }.to_json
    )
  end

  def parse_lambda_response(response, execution_time_ms)
    # Decode logs (base64 encoded)
    logs = response.log_result ? Base64.decode64(response.log_result) : ""

    # Parse payload
    payload = JSON.parse(response.payload.read)

    if response.status_code == 200 && !payload['errorMessage']
      Result.new(
        success?: true,
        result: payload['result'],
        error: nil,
        execution_time_ms: execution_time_ms,
        logs: logs
      )
    else
      Result.new(
        success?: false,
        result: nil,
        error: payload['errorMessage'] || payload['errorType'] || 'Unknown error',
        execution_time_ms: execution_time_ms,
        logs: logs
      )
    end
  end

  def build_deployment_package
    # Create ZIP file with Lambda handler and user code
    require 'zip'

    zip_buffer = Zip::OutputStream.write_buffer do |zip|
      # Add Lambda handler
      zip.put_next_entry('function.rb')
      zip.write(lambda_handler_code)

      # Add user code
      zip.put_next_entry('user_code.rb')
      zip.write(@code)

      # Add Gemfile if dependencies specified
      if @dependencies.any?
        zip.put_next_entry('Gemfile')
        zip.write(gemfile_content)
      end
    end

    zip_buffer.rewind
    zip_buffer.read
  end

  def lambda_handler_code
    # Lambda handler that loads and executes user code
    <<~RUBY
      require 'json'

      def handler(event:, context:)
        # Load user code
        require_relative 'user_code'

        # Extract arguments from event
        arguments = event['arguments'] || {}

        # Execute user function
        result = execute(**arguments.transform_keys(&:to_sym))

        # Return result
        { result: result }
      rescue => e
        # Return error
        {
          errorMessage: e.message,
          errorType: e.class.name,
          stackTrace: e.backtrace
        }
      end
    RUBY
  end

  def gemfile_content
    # Base gems always available
    base_gems = [
      "gem 'http'",
      "gem 'json'"
    ]

    # User-specified gems
    user_gems = @dependencies.map do |dep|
      if dep.is_a?(Hash)
        "gem '#{dep['name']}', '#{dep['version']}'"
      else
        "gem '#{dep}'"
      end
    end

    <<~GEMFILE
      source 'https://rubygems.org'

      #{base_gems.join("\n")}
      #{user_gems.join("\n")}
    GEMFILE
  end
end
```

### Phase 2: Agent Deployment

#### New Models

```ruby
# app/models/prompt_tracker/deployed_agent.rb
class DeployedAgent < ApplicationRecord
  belongs_to :prompt_version
  has_many :function_usages, dependent: :destroy
  has_many :function_definitions, through: :function_usages
  has_many :agent_conversations, dependent: :destroy
  has_many :llm_responses, as: :trackable, dependent: :nullify

  # Columns:
  # - prompt_version_id: bigint
  # - name: string (user-friendly name)
  # - slug: string (unique, URL-safe, indexed)
  # - status: enum [:active, :paused, :error]
  # - deployment_config: jsonb
  #   {
  #     auth: { type: "api_key", key: "..." },
  #     rate_limit: { requests_per_minute: 60 },
  #     allowed_origins: ["https://example.com"],
  #     conversation_ttl: 3600 # seconds
  #   }
  # - deployed_at: datetime
  # - paused_at: datetime
  # - error_message: text
  # - request_count: integer (counter cache)
  # - last_request_at: datetime
  # - created_by: string

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :status, inclusion: { in: %w[active paused error] }

  before_validation :generate_slug, on: :create, if: -> { slug.blank? }
  after_create :extract_functions_from_version

  scope :active, -> { where(status: "active") }
  scope :paused, -> { where(status: "paused") }

  def public_url
    "#{PromptTracker.configuration.agent_base_url}/agents/#{slug}/chat"
  end

  def pause!
    update!(status: "paused", paused_at: Time.current)
  end

  def resume!
    update!(status: "active", paused_at: nil)
  end

  private

  def generate_slug
    base = name.parameterize
    self.slug = base
    counter = 1
    while DeployedAgent.exists?(slug: slug)
      self.slug = "#{base}-#{counter}"
      counter += 1
    end
  end

  def extract_functions_from_version
    # Link to FunctionDefinition records for functions in prompt_version.model_config.tool_config
    # Functions must exist in the library before deployment
    functions = prompt_version.model_config.dig("tool_config", "functions") || []
    functions.each do |func_config|
      func_def = FunctionDefinition.find_by(name: func_config["name"])
      if func_def
        function_definitions << func_def unless function_definitions.include?(func_def)
      else
        errors.add(:base, "Function '#{func_config["name"]}' not found in library. Please save it first.")
      end
    end
  end
end

# app/models/prompt_tracker/agent_conversation.rb
class AgentConversation < ApplicationRecord
  belongs_to :deployed_agent

  # Columns:
  # - deployed_agent_id: bigint
  # - conversation_id: string (unique, indexed) - client-provided or generated
  # - messages: jsonb (array of message hashes)
  # - metadata: jsonb (client context, user_id, etc.)
  # - last_message_at: datetime
  # - expires_at: datetime (TTL based on deployment_config)

  validates :conversation_id, presence: true, uniqueness: { scope: :deployed_agent_id }

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def add_message(role:, content:)
    self.messages ||= []
    self.messages << { role: role, content: content, timestamp: Time.current.iso8601 }
    self.last_message_at = Time.current
    save!
  end

  def extend_ttl!
    ttl = deployed_agent.deployment_config.dig("conversation_ttl") || 3600
    update!(expires_at: ttl.seconds.from_now)
  end
end
```

#### UI Components

**Deploy Button** (on PromptVersion show page)
- Prominent "Deploy Agent" button (only for active versions)
- Click → modal with deployment form
- Form fields:
  - Agent Name (required)
  - Slug (auto-generated, editable)
  - Authentication: API Key (generated) or None
  - Rate Limit: requests per minute (default: 60)
  - Conversation TTL: seconds (default: 3600)
  - Allowed Origins: comma-separated URLs (CORS)
- Preview: Shows what the public URL will be
- "Deploy" button → creates DeployedAgent, shows success with URL + API key

**Deployed Agents Dashboard** (`/agents`)
- Table of all deployed agents
- Columns: Name, Slug, Status, Version, Requests (24h), Last Request, Actions
- Status badges: Active (green), Paused (yellow), Error (red)
- Actions: View Details, Pause/Resume, Delete
- Click row → Agent Detail page

**Agent Detail Page** (`/agents/:id`)
- Header: Name, Status, Public URL (copy button), API Key (show/hide)
- Tabs:
  1. **Overview**: Stats (total requests, avg response time, error rate), deployment config
  2. **Logs**: Real-time stream of requests/responses (last 100, paginated)
  3. **Functions**: List of functions used by this agent with call counts
  4. **Analytics**: Charts (requests over time, function usage, costs)
  5. **Settings**: Edit deployment config, pause/resume, delete
- "Test Agent" button → opens chat interface to test the deployed agent

#### API Endpoints

```ruby
# config/routes.rb - Public API (outside engine namespace)
namespace :agents do
  post ':slug/chat', to: 'deployed_agents#chat'
  get ':slug/info', to: 'deployed_agents#info'
end

# app/controllers/agents/deployed_agents_controller.rb
module Agents
  class DeployedAgentsController < ActionController::API
    before_action :authenticate_agent_request
    before_action :check_rate_limit
    before_action :load_agent

    # POST /agents/:slug/chat
    # Body: { message: "...", conversation_id: "..." (optional), metadata: {...} }
    # Response: { response: "...", conversation_id: "...", function_calls: [...] }
    def chat
      result = AgentRuntimeService.call(
        deployed_agent: @agent,
        message: params[:message],
        conversation_id: params[:conversation_id],
        metadata: params[:metadata]
      )

      render json: result
    end

    # GET /agents/:slug/info
    # Response: { name: "...", description: "...", available_functions: [...] }
    def info
      render json: {
        name: @agent.name,
        description: @agent.prompt_version.notes,
        available_functions: @agent.function_definitions.map { |f|
          { name: f.name, description: f.description, parameters: f.parameters }
        }
      }
    end
  end
end
```

### Phase 3: Agent Runtime

#### Core Service

```ruby
# app/services/prompt_tracker/agent_runtime_service.rb
class AgentRuntimeService
  # Execute a single turn of agent conversation
  #
  # @param deployed_agent [DeployedAgent]
  # @param message [String] user message
  # @param conversation_id [String, nil] existing conversation ID or nil for new
  # @param metadata [Hash] client metadata (user_id, session_id, etc.)
  # @return [Hash] { response: "...", conversation_id: "...", function_calls: [...] }

  Result = Struct.new(:success?, :response, :conversation_id, :function_calls, :error, keyword_init: true)

  def self.call(deployed_agent:, message:, conversation_id: nil, metadata: {})
    new(deployed_agent, message, conversation_id, metadata).execute
  end

  def initialize(deployed_agent, message, conversation_id, metadata)
    @deployed_agent = deployed_agent
    @message = message
    @conversation_id = conversation_id || SecureRandom.uuid
    @metadata = metadata
    @function_calls = []
  end

  def execute
    # 1. Load or create conversation
    conversation = load_conversation
    conversation.add_message(role: "user", content: @message)

    # 2. Build messages array for LLM
    messages = build_messages(conversation)

    # 3. Call LLM with function calling enabled
    llm_response = call_llm(messages)

    # 4. Handle function calls (if any)
    if llm_response.function_calls.present?
      function_results = execute_functions(llm_response.function_calls)
      @function_calls = llm_response.function_calls

      # Add function results to conversation and call LLM again
      messages += build_function_messages(llm_response.function_calls, function_results)
      llm_response = call_llm(messages)
    end

    # 5. Save assistant response to conversation
    conversation.add_message(role: "assistant", content: llm_response.content)
    conversation.extend_ttl!

    # 6. Track in monitoring
    track_response(llm_response, conversation)

    Result.new(
      success?: true,
      response: llm_response.content,
      conversation_id: @conversation_id,
      function_calls: @function_calls
    )
  rescue => e
    @deployed_agent.update!(status: "error", error_message: e.message)
    Result.new(success?: false, error: e.message)
  end

  private

  def load_conversation
    @deployed_agent.agent_conversations.find_or_create_by!(conversation_id: @conversation_id) do |conv|
      ttl = @deployed_agent.deployment_config.dig("conversation_ttl") || 3600
      conv.expires_at = ttl.seconds.from_now
      conv.metadata = @metadata
    end
  end

  def build_messages(conversation)
    # Convert conversation.messages to LLM format
    messages = []

    # Add system prompt if present
    if @deployed_agent.prompt_version.system_prompt.present?
      messages << { role: "system", content: @deployed_agent.prompt_version.system_prompt }
    end

    # Add conversation history
    conversation.messages.each do |msg|
      messages << { role: msg["role"], content: msg["content"] }
    end

    messages
  end

  def call_llm(messages)
    model_config = @deployed_agent.prompt_version.model_config

    # Build tools array from function definitions
    tools = build_tools_array

    LlmClientService.call(
      messages: messages,
      model_config: model_config.merge("tools" => tools),
      track_response: false # We'll track manually
    )
  end

  def build_tools_array
    @deployed_agent.function_definitions.map do |func_def|
      {
        type: "function",
        function: {
          name: func_def.name,
          description: func_def.description,
          parameters: func_def.parameters
        }
      }
    end
  end

  def execute_functions(function_calls)
    function_calls.map do |call|
      func_def = @deployed_agent.function_definitions.find_by(name: call[:name])

      if func_def
        # Execute the function code
        result = func_def.execute(call[:arguments])

        # Track execution for analytics
        FunctionExecution.create!(
          function_definition: func_def,
          deployed_agent: @deployed_agent,
          agent_conversation: @conversation,
          arguments: call[:arguments],
          result: result[:result],
          success: result[:success?],
          error_message: result[:error],
          execution_time_ms: result[:execution_time_ms],
          executed_at: Time.current
        )

        result
      else
        { success?: false, error: "Function not found: #{call[:name]}" }
      end
    end
  end

  def build_function_messages(function_calls, function_results)
    messages = []

    # Add assistant message with function calls
    messages << {
      role: "assistant",
      content: nil,
      function_calls: function_calls
    }

    # Add function results
    function_calls.each_with_index do |call, index|
      messages << {
        role: "function",
        name: call[:name],
        content: function_results[index][:result].to_json
      }
    end

    messages
  end

  def track_response(llm_response, conversation)
    # Create LlmResponse record for monitoring
    @deployed_agent.llm_responses.create!(
      prompt_version: @deployed_agent.prompt_version,
      response_text: llm_response.content,
      tokens_prompt: llm_response.usage[:prompt_tokens],
      tokens_completion: llm_response.usage[:completion_tokens],
      metadata: {
        conversation_id: @conversation_id,
        client_metadata: @metadata,
        function_calls: @function_calls
      }
    )

    # Update agent stats
    @deployed_agent.increment!(:request_count)
    @deployed_agent.update!(last_request_at: Time.current)
  end
end
```

#### Background Jobs

```ruby
# app/jobs/prompt_tracker/cleanup_expired_conversations_job.rb
class CleanupExpiredConversationsJob < ApplicationJob
  queue_as :default

  # Run daily to clean up expired conversations
  def perform
    AgentConversation.expired.find_each(&:destroy)
  end
end

# app/jobs/prompt_tracker/agent_health_check_job.rb
class AgentHealthCheckJob < ApplicationJob
  queue_as :default

  # Run every 5 minutes to check agent health
  def perform
    DeployedAgent.active.find_each do |agent|
      # Check if agent has had errors recently
      recent_errors = agent.llm_responses.where("created_at > ?", 5.minutes.ago)
                           .where.not(error_message: nil)

      if recent_errors.count > 10
        agent.update!(status: "error", error_message: "High error rate detected")
      end
    end
  end
end
```

## Database Migrations

```ruby
# db/migrate/XXXXXX_create_function_definitions.rb
class CreateFunctionDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_function_definitions do |t|
      t.string :name, null: false, index: { unique: true }
      t.text :description
      t.jsonb :parameters, default: {} # JSON Schema
      t.text :code, null: false # Ruby source code
      t.string :language, null: false, default: "ruby"
      t.string :category
      t.jsonb :tags, default: []
      t.text :environment_variables # Encrypted by Rails
      t.jsonb :dependencies, default: [] # Array of gem names/versions
      t.jsonb :example_input, default: {}
      t.jsonb :example_output, default: {}
      t.integer :version, default: 1
      t.string :created_by
      t.integer :usage_count, default: 0
      t.datetime :last_executed_at
      t.integer :execution_count, default: 0
      t.integer :average_execution_time_ms

      t.timestamps
    end

    add_index :prompt_tracker_function_definitions, :category
    add_index :prompt_tracker_function_definitions, :language
    add_index :prompt_tracker_function_definitions, :last_executed_at
  end
end

# db/migrate/XXXXXX_create_deployed_agents.rb
class CreateDeployedAgents < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_deployed_agents do |t|
      t.references :prompt_version, null: false, foreign_key: { to_table: :prompt_tracker_prompt_versions }
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.string :status, null: false, default: "active"
      t.jsonb :deployment_config, default: {}
      t.datetime :deployed_at
      t.datetime :paused_at
      t.text :error_message
      t.integer :request_count, default: 0
      t.datetime :last_request_at
      t.string :created_by

      t.timestamps
    end

    add_index :prompt_tracker_deployed_agents, :status
  end
end

# db/migrate/XXXXXX_create_function_executions.rb
class CreateFunctionExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_function_executions do |t|
      t.references :function_definition, null: false, foreign_key: { to_table: :prompt_tracker_function_definitions }
      t.references :deployed_agent, null: true, foreign_key: { to_table: :prompt_tracker_deployed_agents }
      t.references :agent_conversation, null: true, foreign_key: { to_table: :prompt_tracker_agent_conversations }
      t.jsonb :arguments, default: {}
      t.jsonb :result
      t.boolean :success, null: false, default: true
      t.text :error_message
      t.integer :execution_time_ms
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :prompt_tracker_function_executions, :executed_at
    add_index :prompt_tracker_function_executions, :success
    add_index :prompt_tracker_function_executions, [:function_definition_id, :executed_at]
  end
end

# db/migrate/XXXXXX_create_deployed_agent_functions.rb
# Join table for many-to-many relationship between deployed_agents and function_definitions
class CreateDeployedAgentFunctions < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_deployed_agent_functions do |t|
      t.references :deployed_agent, null: false, foreign_key: { to_table: :prompt_tracker_deployed_agents }
      t.references :function_definition, null: false, foreign_key: { to_table: :prompt_tracker_function_definitions }

      t.timestamps
    end

    add_index :prompt_tracker_deployed_agent_functions, [:deployed_agent_id, :function_definition_id],
              unique: true, name: 'index_deployed_agent_functions_unique'
  end
end

# db/migrate/XXXXXX_create_agent_conversations.rb
class CreateAgentConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :prompt_tracker_agent_conversations do |t|
      t.references :deployed_agent, null: false, foreign_key: { to_table: :prompt_tracker_deployed_agents }
      t.string :conversation_id, null: false
      t.jsonb :messages, default: []
      t.jsonb :metadata, default: {}
      t.datetime :last_message_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :prompt_tracker_agent_conversations, [:deployed_agent_id, :conversation_id],
              unique: true, name: 'index_agent_conversations_on_agent_and_conversation'
    add_index :prompt_tracker_agent_conversations, :expires_at
  end
end
```

## Configuration

Add to `lib/prompt_tracker/configuration.rb`:

```ruby
# AWS Lambda configuration for function execution
# @return [String] AWS region (e.g., "us-east-1")
attr_accessor :aws_region

# @return [String] AWS access key ID
attr_accessor :aws_access_key_id

# @return [String] AWS secret access key
attr_accessor :aws_secret_access_key

# @return [String] Lambda execution role ARN
attr_accessor :lambda_execution_role_arn

# @return [String] Prefix for Lambda function names
attr_accessor :lambda_function_prefix

# Base URL for deployed agents (used to generate public URLs)
# @return [String] base URL (e.g., "https://api.example.com")
attr_accessor :agent_base_url

# Default deployment configuration
# @return [Hash] default config for new deployments
attr_accessor :default_deployment_config

# Function execution timeout (seconds)
# @return [Integer] timeout for webhook function calls
attr_accessor :function_execution_timeout
```

Example initializer:

```ruby
# config/initializers/prompt_tracker.rb
PromptTracker.configure do |config|
  # ... existing config ...

  # AWS Lambda configuration (required for function execution)
  config.aws_region = ENV.fetch("AWS_REGION", "us-east-1")
  config.aws_access_key_id = ENV.fetch("AWS_ACCESS_KEY_ID")
  config.aws_secret_access_key = ENV.fetch("AWS_SECRET_ACCESS_KEY")
  config.lambda_execution_role_arn = ENV.fetch("LAMBDA_EXECUTION_ROLE_ARN")
  config.lambda_function_prefix = ENV.fetch("LAMBDA_FUNCTION_PREFIX", "prompt-tracker")

  # Agent deployment settings
  config.agent_base_url = ENV.fetch("AGENT_BASE_URL", "http://localhost:3000")

  config.default_deployment_config = {
    auth: { type: "api_key" },
    rate_limit: { requests_per_minute: 60 },
    conversation_ttl: 3600, # 1 hour
    allowed_origins: []
  }

  config.function_execution_timeout = 30 # seconds
end
```

## Security Considerations

### Authentication
- **API Key**: Generate secure random keys (32+ characters) for each deployed agent
- **Key Rotation**: Allow users to regenerate API keys without redeploying
- **Key Storage**: Store hashed keys in database, show plaintext only once on creation
- **Header Format**: `Authorization: Bearer <api_key>`

### Rate Limiting
- **Per-Agent Limits**: Configurable requests per minute per deployed agent
- **Implementation**: Use Redis with sliding window algorithm
- **Response**: Return `429 Too Many Requests` with `Retry-After` header
- **Bypass**: Allow internal requests to bypass rate limits

### CORS
- **Allowed Origins**: Configurable whitelist per deployed agent
- **Default**: Empty list (no CORS, API-only access)
- **Wildcards**: Support `*` for public agents (with warning)

### Input Validation
- **Message Length**: Limit to 10,000 characters
- **Conversation ID**: Validate format (UUID or alphanumeric)
- **Metadata**: Limit size to 1KB JSON
- **Function Arguments**: Validate against JSON Schema before execution

### Code Execution Security (Critical)

**Sandboxing** (Docker-based isolation):
- Each function execution runs in a fresh Docker container
- No network access by default (NetworkMode: 'none')
- Filesystem is read-only except for /tmp
- No access to host system or other containers
- Container destroyed immediately after execution

**Resource Limits**:
- **CPU**: 1.0 core max per execution
- **Memory**: 512MB max per execution
- **Timeout**: 30 seconds max execution time
- **Disk**: 100MB max temporary storage
- **Network**: Disabled by default (can be enabled per-function with whitelist)

**Code Validation**:
- Syntax check before saving (Ruby parser)
- Forbidden patterns detection:
  - `eval`, `instance_eval`, `class_eval`
  - `system`, `exec`, `spawn`, `` ` `` (backticks)
  - `require 'open3'`, `IO.popen`
  - File operations outside /tmp
- Gem whitelist: Only approved gems can be installed
- Code review flag for admin approval (optional)

**Environment Variables**:
- Encrypted at rest using Rails encrypted attributes
- Never logged or displayed in UI after creation
- Injected into container at runtime only
- Automatically redacted from error messages

**Execution Monitoring**:
- All executions logged with arguments, results, errors
- Anomaly detection: Flag functions with high failure rates
- Rate limiting: Max executions per function per minute
- Cost tracking: Monitor execution time and resource usage
- Auto-pause functions that exceed error threshold (>10% failures)

### Data Privacy
- **Conversation Storage**: Encrypt sensitive fields at rest
- **TTL Enforcement**: Automatically delete expired conversations
- **User Consent**: Document that conversations are stored temporarily
- **GDPR Compliance**: Provide API to delete user conversations

## Testing Strategy

### Unit Tests

```ruby
# spec/models/prompt_tracker/function_definition_spec.rb
RSpec.describe PromptTracker::FunctionDefinition do
  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_inclusion_of(:implementation_type).in_array(%w[mock webhook code]) }
  end

  describe "#parameters_must_be_valid_json_schema" do
    it "accepts valid JSON Schema" do
      func = build(:function_definition, parameters: {
        type: "object",
        properties: { city: { type: "string" } }
      })
      expect(func).to be_valid
    end

    it "rejects invalid JSON Schema" do
      func = build(:function_definition, parameters: { invalid: true })
      expect(func).not_to be_valid
    end
  end
end

# spec/models/prompt_tracker/deployed_agent_spec.rb
RSpec.describe PromptTracker::DeployedAgent do
  describe "#generate_slug" do
    it "generates slug from name" do
      agent = create(:deployed_agent, name: "Customer Support Bot")
      expect(agent.slug).to eq("customer-support-bot")
    end

    it "handles duplicate slugs" do
      create(:deployed_agent, name: "Bot", slug: "bot")
      agent = create(:deployed_agent, name: "Bot")
      expect(agent.slug).to eq("bot-1")
    end
  end

  describe "#public_url" do
    it "returns correct URL" do
      agent = create(:deployed_agent, slug: "my-agent")
      expect(agent.public_url).to include("/agents/my-agent/chat")
    end
  end
end

# spec/services/prompt_tracker/function_executor_spec.rb
RSpec.describe PromptTracker::FunctionExecutor do
  describe ".execute" do
    context "with mock implementation" do
      it "returns configured mock response" do
        func = create(:function_definition,
          implementation_type: "mock",
          implementation_config: { response: { temp: 72 } }
        )

        result = described_class.execute(
          function_definition: func,
          arguments: { city: "Berlin" }
        )

        expect(result[:success]).to be true
        expect(result[:result]).to eq({ temp: 72 })
      end
    end

    context "with webhook implementation" do
      it "calls webhook and returns response" do
        stub_request(:post, "https://api.example.com/weather")
          .to_return(status: 200, body: { temp: 72 }.to_json)

        func = create(:function_definition,
          implementation_type: "webhook",
          implementation_config: {
            url: "https://api.example.com/weather",
            method: "POST"
          }
        )

        result = described_class.execute(
          function_definition: func,
          arguments: { city: "Berlin" }
        )

        expect(result[:success]).to be true
        expect(result[:result]["temp"]).to eq(72)
      end

      it "handles webhook timeout" do
        stub_request(:post, "https://api.example.com/weather")
          .to_timeout

        func = create(:function_definition,
          implementation_type: "webhook",
          implementation_config: { url: "https://api.example.com/weather", method: "POST" }
        )

        result = described_class.execute(
          function_definition: func,
          arguments: { city: "Berlin" }
        )

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end
end

# spec/services/prompt_tracker/agent_runtime_service_spec.rb
RSpec.describe PromptTracker::AgentRuntimeService do
  let(:deployed_agent) { create(:deployed_agent) }

  describe ".call" do
    it "creates new conversation for first message" do
      expect {
        described_class.call(
          deployed_agent: deployed_agent,
          message: "Hello"
        )
      }.to change(PromptTracker::AgentConversation, :count).by(1)
    end

    it "reuses existing conversation" do
      conversation_id = SecureRandom.uuid

      described_class.call(
        deployed_agent: deployed_agent,
        message: "Hello",
        conversation_id: conversation_id
      )

      expect {
        described_class.call(
          deployed_agent: deployed_agent,
          message: "How are you?",
          conversation_id: conversation_id
        )
      }.not_to change(PromptTracker::AgentConversation, :count)
    end

    it "executes function calls" do
      func = create(:function_definition, name: "get_weather")
      deployed_agent.function_definitions << func

      # Mock LLM response with function call
      allow_any_instance_of(PromptTracker::LlmClientService)
        .to receive(:call).and_return(
          OpenStruct.new(
            function_calls: [{ name: "get_weather", arguments: { city: "Berlin" } }],
            content: "The weather in Berlin is 72°F"
          )
        )

      result = described_class.call(
        deployed_agent: deployed_agent,
        message: "What's the weather in Berlin?"
      )

      expect(result.success?).to be true
      expect(result.function_calls).to be_present
    end
  end
end
```

### Integration Tests

```ruby
# spec/requests/agents/deployed_agents_spec.rb
RSpec.describe "Agents API", type: :request do
  let(:deployed_agent) { create(:deployed_agent, :with_api_key) }

  describe "POST /agents/:slug/chat" do
    it "returns response for valid request" do
      post "/agents/#{deployed_agent.slug}/chat",
        params: { message: "Hello" },
        headers: { "Authorization" => "Bearer #{deployed_agent.api_key}" }

      expect(response).to have_http_status(:success)
      expect(json_response["response"]).to be_present
      expect(json_response["conversation_id"]).to be_present
    end

    it "returns 401 for missing API key" do
      post "/agents/#{deployed_agent.slug}/chat",
        params: { message: "Hello" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 429 for rate limit exceeded" do
      # Make requests up to rate limit
      61.times do
        post "/agents/#{deployed_agent.slug}/chat",
          params: { message: "Hello" },
          headers: { "Authorization" => "Bearer #{deployed_agent.api_key}" }
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it "maintains conversation context" do
      # First message
      post "/agents/#{deployed_agent.slug}/chat",
        params: { message: "My name is Alice" },
        headers: { "Authorization" => "Bearer #{deployed_agent.api_key}" }

      conversation_id = json_response["conversation_id"]

      # Second message
      post "/agents/#{deployed_agent.slug}/chat",
        params: { message: "What's my name?", conversation_id: conversation_id },
        headers: { "Authorization" => "Bearer #{deployed_agent.api_key}" }

      expect(response).to have_http_status(:success)
      # Response should reference "Alice" from conversation context
    end
  end

  describe "GET /agents/:slug/info" do
    it "returns agent information" do
      get "/agents/#{deployed_agent.slug}/info"

      expect(response).to have_http_status(:success)
      expect(json_response["name"]).to eq(deployed_agent.name)
      expect(json_response["available_functions"]).to be_an(Array)
    end
  end
end
```

### E2E Tests

```ruby
# spec/system/agent_deployment_spec.rb
RSpec.describe "Agent Deployment", type: :system do
  it "allows deploying an agent from prompt version" do
    prompt_version = create(:prompt_version, :active)

    visit prompt_tracker.testing_prompt_path(prompt_version.prompt)

    click_button "Deploy Agent"

    within "#deployAgentModal" do
      fill_in "Agent Name", with: "Customer Support Bot"
      click_button "Deploy"
    end

    expect(page).to have_content("Agent deployed successfully")
    expect(page).to have_content("customer-support-bot")

    # Copy API key
    click_button "Copy API Key"
    expect(page).to have_content("API key copied")
  end

  it "allows managing deployed agents" do
    deployed_agent = create(:deployed_agent)

    visit prompt_tracker.agents_path

    expect(page).to have_content(deployed_agent.name)

    # Pause agent
    within "tr[data-agent-id='#{deployed_agent.id}']" do
      click_button "Pause"
    end

    expect(page).to have_content("Paused")

    # Resume agent
    within "tr[data-agent-id='#{deployed_agent.id}']" do
      click_button "Resume"
    end

    expect(page).to have_content("Active")
  end
end
```

## Implementation Plan

### Phase 1: Function Registry - Foundation (Weeks 1-2)

**Week 1: Models & Database**
- [ ] Create `FunctionDefinition` model with validations
- [ ] Create `FunctionExecution` model for tracking
- [ ] Create migrations for both tables
- [ ] Add JSON Schema validation for `parameters` field
- [ ] Add Ruby syntax validation for `code` field
- [ ] Implement encrypted environment_variables
- [ ] Write comprehensive model specs
- [ ] Seed database with 5-10 example functions

**Week 2: Basic UI - Function Library**
- [ ] Create `FunctionsController` with index, show, new, create actions
- [ ] Build Function Library index page with search/filter
- [ ] Create basic function form (name, description, category, tags)
- [ ] Add parameters builder (simple JSON Schema form)
- [ ] Implement category/tag filtering
- [ ] Write controller specs and basic system tests

**Deliverables:**
- Basic function library with CRUD operations
- Simple form for creating functions (no code editor yet)
- Search and filtering working

### Phase 2: Code Editor & Execution (Weeks 3-5)

**Week 3: Monaco Editor Integration** ✅ COMPLETE
- [x] Add Monaco editor to function form (via CDN)
- [x] Configure syntax highlighting for Ruby and JSON
- [x] Add code templates and snippets (5 templates: basic, API call, data processing, validation, conditional)
- [x] Add line numbers, minimap, error highlighting
- [x] Automatic content sync with form textarea
- [x] Responsive layout with configurable heights
- [x] Theme support (light/dark mode)
- [x] Add Test UI to function show page with AJAX submission
- [x] Display test results inline with execution time
- [x] Load example input button

**Week 4: Docker-Based Code Execution**
- [ ] Set up Docker on development/staging/production servers
- [ ] Create base Docker image for Ruby execution (with HTTP gem)
- [ ] Implement `CodeExecutor` service with Docker API
- [ ] Add resource limits (CPU, memory, timeout)
- [ ] Implement code wrapping and argument injection
- [ ] Add error handling and logging
- [ ] Write comprehensive service specs with Docker mocks

**Week 5: Testing Interface & Security**
- [ ] Build test runner UI (input/output panels)
- [ ] Implement "Run Test" functionality
- [ ] Add execution logs display
- [ ] Implement code validation (forbidden patterns)
- [ ] Add environment variables manager (encrypted)
- [ ] Create gem dependency manager
- [ ] Add execution analytics (time, success rate)
- [ ] Write integration tests for full execution flow

**Deliverables:**
- Full-featured code editor in browser
- Working Docker-based code execution
- Test interface for functions
- Security validations in place

### Phase 3: Playground Integration & Polish (Week 6)

**Week 6: Playground Integration**
- [ ] Add "Import from Library" button to playground functions panel
- [ ] Create function search modal for playground
- [ ] Implement function import (copies code to playground)
- [ ] Add "Save to Library" button for current playground functions
- [ ] Update playground to use `CodeExecutor` for function testing
- [ ] Add function execution preview in playground
- [ ] Write integration tests for playground + library

**Deliverables:**
- Seamless integration between playground and function library
- Users can test functions in playground before deploying
- Complete Phase 1 ready for agent deployment

### Phase 4: Agent Deployment (Weeks 7-9)

**Week 7: Models & Core Logic**
- [ ] Create `DeployedAgent` model with slug generation
- [ ] Create `AgentConversation` model with TTL
- [ ] Create join table for deployed_agents <-> function_definitions
- [ ] Add migrations for all tables
- [ ] Implement API key generation and hashing
- [ ] Add validation: functions must exist in library before deployment
- [ ] Write model specs for all new models

**Week 8: Deployment UI**
- [ ] Add "Deploy Agent" button to PromptVersion show page
- [ ] Create deployment modal with configuration form
- [ ] Validate that all functions are saved to library
- [ ] Build Deployed Agents dashboard (`/agents`)
- [ ] Create Agent Detail page with tabs (overview, logs, functions, analytics, settings)
- [ ] Implement pause/resume/delete actions
- [ ] Add "Test Agent" chat interface
- [ ] Write system tests for deployment flow

**Week 9: Public API**
- [ ] Create `Agents::DeployedAgentsController` (API controller)
- [ ] Implement authentication middleware (API key validation)
- [ ] Implement rate limiting middleware (Redis-based)
- [ ] Add CORS support with configurable origins
- [ ] Create API documentation page with examples
- [ ] Add OpenAPI/Swagger spec generation
- [ ] Write request specs for public API endpoints

**Deliverables:**
- One-click deployment from prompt versions
- Public API endpoints for agent chat
- Agent management dashboard
- Authentication and rate limiting
- Validation that functions exist in library

### Phase 5: Agent Runtime (Weeks 10-12)

**Week 10: Core Runtime Service**
- [ ] Create `AgentRuntimeService` with conversation management
- [ ] Implement function call detection and routing to `CodeExecutor`
- [ ] Add conversation state persistence
- [ ] Integrate with existing `LlmClientService`
- [ ] Track all interactions as `LlmResponse` records
- [ ] Handle multi-turn function calling (loop with max iterations)
- [ ] Write comprehensive service specs

**Week 11: Production Execution & Monitoring**
- [ ] Set up Docker on production servers
- [ ] Implement execution queue (Sidekiq) for async function execution
- [ ] Add function execution logging and analytics
- [ ] Create `FunctionExecution` records for all executions
- [ ] Implement execution timeout and error handling
- [ ] Add retry logic for transient failures
- [ ] Write specs for production execution flow

**Week 12: Background Jobs & Health Monitoring**
- [ ] Create `CleanupExpiredConversationsJob` (daily)
- [ ] Create `CleanupDockerContainersJob` (hourly - cleanup orphaned containers)
- [ ] Create `AgentHealthCheckJob` (every 5 minutes)
- [ ] Add agent error detection and auto-pause
- [ ] Implement conversation TTL enforcement
- [ ] Add monitoring dashboard for deployed agents
- [ ] Create alerts for high error rates, slow executions
- [ ] Write job specs and integration tests

**Deliverables:**
- Fully functional agent runtime with conversation management
- Production-ready code execution with Docker
- Automated health checks and cleanup
- Comprehensive monitoring and alerting

### Phase 6: Polish & Documentation (Weeks 13-14)

**Week 13: Final Polish & Performance**
- [ ] Add comprehensive error messages and user feedback
- [ ] Implement loading states and optimistic UI updates
- [ ] Add analytics charts (requests over time, function usage, execution times, costs)
- [ ] Optimize Docker image build time (caching, pre-built base images)
- [ ] Add function execution caching (same input = cached output)
- [ ] Performance testing and optimization
- [ ] Load testing for concurrent executions

**Week 14: Documentation & Security Audit**
- [ ] Write user documentation (guides, API docs, examples)
- [ ] Create video tutorial for writing first function
- [ ] Create video tutorial for deployment workflow
- [ ] Document security best practices
- [ ] Security audit (penetration testing, code review)
- [ ] Docker security hardening
- [ ] Beta testing with 5-10 select users
- [ ] Collect feedback and iterate

**Deliverables:**
- Production-ready feature with comprehensive documentation
- Performance benchmarks and optimization complete
- Security audit completed with no critical issues
- User guides, tutorials, and API documentation
- Beta testing feedback incorporated

## Rollout Strategy

### Alpha Phase (Week 15)
- Enable for internal team only (dogfooding)
- Create 10+ real-world functions (weather, database, email, etc.)
- Deploy 3-5 production agents internally
- Monitor Docker resource usage, execution times, error rates
- Fix critical bugs and performance issues

### Beta Phase (Weeks 16-17)
- Enable feature flag for 10-20 select users (early adopters)
- Provide onboarding support and documentation
- Monitor error rates, performance, Docker resource usage
- Collect user feedback via in-app surveys and interviews
- Fix critical bugs and UX issues
- Optimize Docker image build time and execution performance

### General Availability (Week 18)
- Enable feature for all users
- Announce via blog post, email, social media
- Host webinar: "Build Your First AI Agent in 10 Minutes"
- Create showcase page with example functions and agents
- Monitor support tickets and iterate
- Track adoption metrics and success criteria

**Total Timeline: 18 weeks (4.5 months) from kickoff to GA**

## Open Questions

### Critical Technical Decisions

1. **Docker vs. Alternatives for Code Execution?**
   - **Docker**: Mature, well-documented, good isolation, ~2-5s startup
   - **Firecracker**: Faster startup (~125ms), lighter weight, more complex setup
   - **AWS Lambda**: No infrastructure management, vendor lock-in, cold starts
   - **Recommendation**: Start with Docker (Phases 1-6), evaluate Firecracker in Phase 7

2. **Gem Whitelist vs. Blacklist?**
   - **Whitelist**: Safest, but limits functionality (~50 approved gems)
   - **Blacklist**: More flexible, but risky (block known dangerous gems)
   - **No restrictions + code review**: Most flexible, requires manual review
   - **Recommendation**: Start with whitelist, expand based on user requests

3. **Network Access for Functions?**
   - **Default**: No network access (NetworkMode: 'none')
   - **Optional**: Enable per-function with domain whitelist
   - **Use case**: Calling external APIs (weather, database, Slack)
   - **Security**: Block private IPs, localhost, metadata endpoints
   - **Recommendation**: Start with no network, add whitelisting in Phase 7

4. **Function Execution Caching?**
   - **Recommendation**: Yes, opt-in per function
   - **Cache key**: function_definition_id + arguments hash
   - **TTL**: Configurable (5 minutes to 24 hours)
   - **Use case**: Weather API (10 min), database queries (1 hour)
   - **Invalidation**: Manual or automatic on code update

5. **Conversation Storage: Database vs. Redis?**
   - **Database**: Persistent, queryable, easier debugging
   - **Redis**: Faster, automatic TTL, less database load
   - **Recommendation**: Start with database, add Redis caching if needed

6. **Multi-turn Function Calling?**
   - Should agents support multiple rounds of function calls in one turn?
   - **Recommendation**: Yes, implement loop with max iterations (5)

7. **Streaming Responses?**
   - Should agents support SSE streaming for real-time responses?
   - **Recommendation**: Phase 7 feature, start with complete responses

### Product Decisions

8. **Function Versioning?**
   - How to handle updates to functions used by deployed agents?
   - **Option A**: Auto-update all agents (risky - could break agents)
   - **Option B**: Pin to version, require manual update (safer)
   - **Recommendation**: Option B, add auto-update opt-in later

9. **Function Sharing Across Organizations?**
   - **Phase 1-6**: Private (per-org) only for security
   - **Phase 7**: Public function marketplace with code review
   - **Concern**: Malicious code in shared functions
   - **Mitigation**: Security badges, community ratings, admin review

10. **Pricing Model?**
    - **Option A**: Flat fee per agent + execution quota
    - **Option B**: Usage-based (per request + per execution)
    - **Option C**: Included in plans with limits (100 executions/day)
    - **Recommendation**: Start with Option C, add Option B for power users

11. **Multi-language Support Timeline?**
    - **Phase 1-6**: Ruby only
    - **Phase 7**: Add Python (high demand, similar sandboxing)
    - **Phase 8**: Add JavaScript/Node.js
    - Each language needs separate Docker base image and validation

12. **Agent Marketplace?**
    - Should users be able to share/sell agents publicly?
    - **Recommendation**: Future feature (Phase 8+), focus on private deployments first

13. **Custom Domains?**
    - Should users deploy agents on custom domains?
    - **Recommendation**: Enterprise feature, start with subdomain/path-based URLs

## Success Criteria

### Launch Criteria (Must Have)
- [ ] All Phase 1-6 features implemented and tested
- [ ] Security audit completed with no critical issues (code execution, Docker sandboxing)
- [ ] Performance benchmarks met:
  - [ ] Function execution: p95 < 5s (including Docker startup)
  - [ ] Agent response time: p95 < 3s (end-to-end)
  - [ ] Code editor loads in < 1s
- [ ] Docker infrastructure stable:
  - [ ] Container cleanup working (no orphaned containers)
  - [ ] Resource limits enforced (CPU, memory, timeout)
  - [ ] Execution success rate > 99%
- [ ] Documentation complete:
  - [ ] User guide: "Write Your First Function"
  - [ ] User guide: "Deploy Your First Agent"
  - [ ] API documentation with examples
  - [ ] Security best practices guide
- [ ] Beta testing completed with positive feedback (5-10 users)
- [ ] Error rate < 1% in production

### Post-Launch Metrics (3 Months)

**Adoption Metrics**
- 50% of active users create at least one code-based function
- 30% of active users deploy at least one agent
- Average 3 deployed agents per deploying user
- 100+ functions in library (community-created)

**Engagement Metrics**
- 10,000+ agent API requests per day
- 50,000+ function executions per day
- Average 5 functions per agent
- 70% of functions reused across multiple agents
- Average 10 test runs per function before deployment

**Quality Metrics**
- Agent uptime > 99.5%
- API error rate < 0.5%
- Function execution success rate > 95%
- Average function execution time < 2s (p95 < 5s)
- Average agent response time < 1.5s (p95 < 3s)
- Docker container cleanup success rate > 99.9%
- User satisfaction score > 4.5/5

**Security Metrics**
- Zero security incidents related to code execution
- Zero container escapes or infrastructure compromises
- < 1% of functions flagged for dangerous patterns
- Environment variable leakage incidents: 0

**Business Metrics**
- 20% increase in user retention
- 15% increase in paid conversions (if pricing added)
- 50% reduction in support tickets about "how to deploy prompts"
- 30% increase in time spent in platform (code editor engagement)

## Risks & Mitigation

### Technical Risks

**Risk: Malicious code execution (HIGH SEVERITY)**
- **Impact**: User code could attack infrastructure, steal data, or abuse resources
- **Mitigation**: Docker sandboxing with no network access by default
- **Mitigation**: Resource limits (CPU, memory, timeout) enforced at container level
- **Mitigation**: Code validation to block dangerous patterns (eval, system, exec)
- **Mitigation**: Read-only filesystem except /tmp
- **Mitigation**: Container destroyed immediately after execution
- **Mitigation**: Optional admin review for new functions before execution

**Risk: Docker resource exhaustion**
- **Impact**: Too many concurrent executions could overwhelm server
- **Mitigation**: Queue-based execution with max concurrency limit
- **Mitigation**: Monitor Docker resource usage and alert on high usage
- **Mitigation**: Auto-pause agents that exceed resource quotas
- **Mitigation**: Implement execution quotas per user/agent

**Risk: Slow Docker container startup**
- **Impact**: Function execution takes too long, poor user experience
- **Mitigation**: Pre-build base Docker images with common gems
- **Mitigation**: Cache Docker images for frequently-used dependency sets
- **Mitigation**: Consider container pooling (keep warm containers ready)
- **Mitigation**: Set expectations: "First execution may take 5-10s"

**Risk: High LLM API costs from deployed agents**
- **Mitigation**: Implement per-agent cost tracking, usage alerts, rate limits
- **Mitigation**: Add cost caps per agent (pause when exceeded)

**Risk: Conversation state growing unbounded**
- **Mitigation**: Enforce strict TTL on conversations
- **Mitigation**: Limit conversation history to last N messages
- **Mitigation**: Add background job to clean up expired conversations

**Risk: Rate limiting bypass or abuse**
- **Mitigation**: Implement Redis-based sliding window rate limiter
- **Mitigation**: Add IP-based rate limiting as backup
- **Mitigation**: Monitor for suspicious patterns and auto-ban

**Risk: Environment variable leakage**
- **Impact**: API keys exposed in logs or error messages
- **Mitigation**: Encrypt environment variables at rest
- **Mitigation**: Redact from all logs and error messages
- **Mitigation**: Never display in UI after creation
- **Mitigation**: Audit all code paths that handle env vars

### Product Risks

**Risk: Users deploy agents with poor prompts, get bad results**
- **Mitigation**: Require testing before deployment (minimum N test runs)
- **Mitigation**: Show warning if prompt has no evaluations
- **Mitigation**: Add "deployment readiness score" based on testing coverage

**Risk: Function library becomes cluttered with low-quality functions**
- **Mitigation**: Add quality ratings and reviews
- **Mitigation**: Implement "verified" badge for high-quality functions
- **Mitigation**: Allow filtering by usage count, rating

**Risk: Users confused about difference between testing and deployment**
- **Mitigation**: Clear UI separation (Testing vs. Deployment sections)
- **Mitigation**: Add onboarding tutorial explaining workflow
- **Mitigation**: Show deployment checklist before first deployment

## Appendix

### Example API Usage

**Deploy an agent:**
```bash
# Via UI: Click "Deploy Agent" on prompt version page
# Result: Get unique URL and API key
```

**Chat with deployed agent:**
```bash
curl -X POST https://app.com/agents/customer-support-v2/chat \
  -H "Authorization: Bearer sk_abc123..." \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I need help with my order",
    "metadata": {
      "user_id": "user_123",
      "session_id": "sess_456"
    }
  }'

# Response:
{
  "response": "I'd be happy to help! Could you provide your order number?",
  "conversation_id": "conv_789",
  "function_calls": []
}
```

**Continue conversation:**
```bash
curl -X POST https://app.com/agents/customer-support-v2/chat \
  -H "Authorization: Bearer sk_abc123..." \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Order #12345",
    "conversation_id": "conv_789"
  }'

# Response:
{
  "response": "I found your order. It's currently being processed and will ship tomorrow.",
  "conversation_id": "conv_789",
  "function_calls": [
    {
      "name": "lookup_order",
      "arguments": { "order_id": "12345" }
    }
  ]
}
```

### Example Function Definitions

**Weather Function (Code-based with API call):**
```ruby
# Function: get_weather
# Description: Get current weather for a city using OpenWeatherMap API
# Parameters: { city: string, units: "celsius" | "fahrenheit" }
# Environment Variables: OPENWEATHER_API_KEY

def execute(city:, units: "celsius")
  # Access environment variable
  api_key = env['OPENWEATHER_API_KEY']

  # Convert units to API format
  api_units = units == "celsius" ? "metric" : "imperial"

  # Make HTTP request (HTTP gem is pre-installed)
  response = HTTP.get("https://api.openweathermap.org/data/2.5/weather", params: {
    q: city,
    units: api_units,
    appid: api_key
  })

  # Parse and return result
  data = JSON.parse(response.body)

  {
    temperature: data["main"]["temp"],
    conditions: data["weather"][0]["description"],
    humidity: data["main"]["humidity"],
    wind_speed: data["wind"]["speed"]
  }
end
```

**Database Query Function (Code-based with PostgreSQL):**
```ruby
# Function: get_user_orders
# Description: Get all orders for a user from the database
# Parameters: { user_id: integer, limit: integer }
# Environment Variables: DATABASE_URL
# Dependencies: pg (PostgreSQL gem)

require 'pg'

def execute(user_id:, limit: 10)
  # Connect to database
  conn = PG.connect(env['DATABASE_URL'])

  # Execute query with parameterized values (prevent SQL injection)
  result = conn.exec_params(
    'SELECT id, total, status, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
    [user_id, limit]
  )

  # Convert to array of hashes
  orders = result.map do |row|
    {
      id: row['id'],
      total: row['total'].to_f,
      status: row['status'],
      created_at: row['created_at']
    }
  end

  conn.close

  { orders: orders, count: orders.length }
end
```

**Slack Notification Function (Code-based):**
```ruby
# Function: send_slack_message
# Description: Send a message to a Slack channel
# Parameters: { channel: string, message: string }
# Environment Variables: SLACK_WEBHOOK_URL

def execute(channel:, message:)
  webhook_url = env['SLACK_WEBHOOK_URL']

  payload = {
    channel: channel,
    text: message,
    username: "PromptTracker Bot",
    icon_emoji: ":robot_face:"
  }

  response = HTTP.post(webhook_url, json: payload)

  if response.status.success?
    { success: true, message: "Message sent to #{channel}" }
  else
    { success: false, error: "Failed to send message: #{response.status}" }
  end
end
```

**Simple Calculator Function (Code-based, no external dependencies):**
```ruby
# Function: calculate
# Description: Perform basic arithmetic operations
# Parameters: { operation: "add" | "subtract" | "multiply" | "divide", a: number, b: number }

def execute(operation:, a:, b:)
  result = case operation
  when "add"
    a + b
  when "subtract"
    a - b
  when "multiply"
    a * b
  when "divide"
    raise "Cannot divide by zero" if b == 0
    a.to_f / b
  else
    raise "Unknown operation: #{operation}"
  end

  {
    operation: operation,
    a: a,
    b: b,
    result: result
  }
end
```

### Related Documentation

- [OpenAI Responses API - Function Calling](docs/llm_providers/openai/responses_api/function_calling.md)
- [Anthropic Messages API - Tool Use](docs/llm_providers/anthropic/tool_use.md)
- [PromptTracker Testing Guide](docs/testing_guide.md)
- [PromptTracker Playground Guide](docs/playground_guide.md)

### References

- [OpenAI Assistants API](https://platform.openai.com/docs/assistants/overview)
- [Anthropic Claude Tool Use](https://docs.anthropic.com/claude/docs/tool-use)
- [LangChain Agents](https://python.langchain.com/docs/modules/agents/)
- [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT)

---

**Document Version:** 2.0 (Code-First Approach)
**Last Updated:** 2026-03-11
**Author:** PromptTracker Team
**Status:** Draft - Ready for Review

**Major Changes from v1.0:**
- Shifted from webhook-based functions to code-first approach
- Added Monaco code editor integration
- Added Docker-based sandboxed execution environment
- Expanded security section for code execution risks
- Extended timeline from 10 weeks to 18 weeks (4.5 months)
- Added comprehensive code examples in Appendix
- Updated success metrics to include execution performance and security
