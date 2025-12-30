# OpenAI Assistant Playground Implementation Plan

## Overview

Create an interactive playground for creating and editing OpenAI Assistants, similar to the OpenAI platform interface. The playground will feature a split-screen layout with configuration on the right and a live thread chat interface on the left.

## Goals

1. **Create/Edit Assistants**: Allow users to create new assistants or edit existing ones directly through the OpenAI API
2. **Live Testing**: Provide a real-time chat interface to test the assistant while configuring it
3. **Full Configuration**: Support all OpenAI Assistant parameters (instructions, model, tools, model config)
4. **Seamless Integration**: Integrate with existing PromptTracker testing infrastructure

## API Verification

Based on OpenAI Assistants API documentation and the ruby-openai gem:

### Assistant Creation/Update Parameters
- ✅ `name` - Assistant name
- ✅ `description` - Assistant description
- ✅ `instructions` - System instructions (like system prompt)
- ✅ `model` - Model to use (gpt-4o, gpt-4-turbo, etc.)
- ✅ `tools` - Array of tools:
  - `file_search` - File search capability
  - `code_interpreter` - Code execution capability
  - `function` - Custom function definitions
- ✅ `temperature` - Sampling temperature (0-2)
- ✅ `top_p` - Nucleus sampling (0-1)
- ✅ `response_format` - Response format (text or json_object)
- ✅ `tool_resources` - Resources for tools (vector stores, code interpreter files)
- ✅ `metadata` - Custom metadata (key-value pairs)

### Thread Management
- ✅ `threads.create` - Create new conversation thread
- ✅ `messages.create` - Add messages to thread
- ✅ `runs.create` - Run assistant on thread
- ✅ `runs.retrieve` - Check run status
- ✅ `messages.list` - Get thread messages

All required API endpoints are available and supported by the ruby-openai gem.

## Architecture

### 1. Routes

Add new routes for the playground:

```ruby
# config/routes.rb
namespace :testing do
  namespace :openai do
    resources :assistants do
      # Playground for creating/editing assistants
      resource :playground, only: [:show], controller: 'assistant_playground' do
        member do
          post :create_assistant    # Create new assistant via API
          post :update_assistant    # Update existing assistant via API
          post :send_message        # Send message in thread
          post :create_thread       # Create new thread
          get  :load_messages       # Load thread messages
        end
      end
    end
  end
end
```

### 2. Controller

Create `AssistantPlaygroundController`:

**Location**: `app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb`

**Actions**:
- `show` - Render playground interface
- `create_assistant` - Create assistant via OpenAI API
- `update_assistant` - Update assistant via OpenAI API
- `send_message` - Send message and run assistant
- `create_thread` - Create new thread for testing
- `load_messages` - Load thread message history

### 3. Service Layer

Create `AssistantPlaygroundService`:

**Location**: `app/services/prompt_tracker/assistant_playground_service.rb`

**Responsibilities**:
- Create/update assistants via OpenAI API
- Manage thread lifecycle
- Handle message sending and retrieval
- Parse and format responses

**Key Methods**:
```ruby
class AssistantPlaygroundService
  def create_assistant(params)
  def update_assistant(assistant_id, params)
  def create_thread
  def send_message(thread_id, assistant_id, content)
  def load_messages(thread_id)
end
```

### 4. Views

Create playground view with split-screen layout:

**Location**: `app/views/prompt_tracker/testing/openai/assistant_playground/show.html.erb`

**Layout Structure**:
```
┌─────────────────────────────────────────────────────────────┐
│                    Assistant Playground                     │
├──────────────────────────────┬──────────────────────────────┤
│                              │                              │
│   Thread Chat Interface      │   Configuration Sidebar      │
│   (Left Side - 60%)          │   (Right Side - 40%)         │
│                              │                              │
│   - Message history          │   - Name                     │
│   - Input box                │   - Instructions             │
│   - Send button              │   - Model selector           │
│   - New thread button        │   - Tools checkboxes         │
│                              │   - Model config             │
│                              │   - Save/Update buttons      │
│                              │                              │
└──────────────────────────────┴──────────────────────────────┘
```

### 5. JavaScript Controller

Create Stimulus controller for interactivity:

**Location**: `app/javascript/prompt_tracker/controllers/assistant_playground_controller.js`

**Responsibilities**:
- Handle message sending
- Update chat interface in real-time
- Auto-save configuration changes
- Manage thread state
- Handle tool selection UI
- Validate form inputs

**Key Features**:
- Debounced auto-save for configuration
- Real-time message updates
- Thread switching
- Loading states
- Error handling

## Detailed Component Specifications

### Right Sidebar Configuration

#### Section 1: Basic Information
```html
<div class="card mb-3">
  <div class="card-header">Basic Information</div>
  <div class="card-body">
    <!-- Name -->
    <input type="text" name="name" placeholder="Assistant Name">

    <!-- Description (optional) -->
    <textarea name="description" placeholder="Description"></textarea>
  </div>
</div>
```

#### Section 2: Instructions
```html
<div class="card mb-3">
  <div class="card-header">System Instructions</div>
  <div class="card-body">
    <!-- Instructions textarea with syntax highlighting -->
    <textarea name="instructions"
              rows="10"
              placeholder="You are a helpful assistant..."></textarea>
    <small>Character count: <span id="char-count">0</span></small>
  </div>
</div>
```

#### Section 3: Model Selection
```html
<div class="card mb-3">
  <div class="card-header">Model</div>
  <div class="card-body">
    <select name="model">
      <option value="gpt-4o">GPT-4o</option>
      <option value="gpt-4-turbo">GPT-4 Turbo</option>
      <option value="gpt-4">GPT-4</option>
      <option value="gpt-3.5-turbo">GPT-3.5 Turbo</option>
    </select>
  </div>
</div>
```

#### Section 4: Tools
```html
<div class="card mb-3">
  <div class="card-header">Tools</div>
  <div class="card-body">
    <!-- File Search -->
    <div class="form-check">
      <input type="checkbox" id="tool_file_search" value="file_search">
      <label for="tool_file_search">
        <i class="bi bi-search"></i> File Search
      </label>
      <small>Enables searching through uploaded files</small>
    </div>

    <!-- Code Interpreter -->
    <div class="form-check">
      <input type="checkbox" id="tool_code_interpreter" value="code_interpreter">
      <label for="tool_code_interpreter">
        <i class="bi bi-code-slash"></i> Code Interpreter
      </label>
      <small>Enables Python code execution</small>
    </div>

    <!-- Functions (future) -->
    <div class="form-check">
      <input type="checkbox" id="tool_functions" value="function" disabled>
      <label for="tool_functions">
        <i class="bi bi-gear"></i> Functions
      </label>
      <small>Custom function calling (coming soon)</small>
    </div>
  </div>
</div>
```

#### Section 5: Model Configuration
```html
<div class="card mb-3">
  <div class="card-header">
    Model Configuration
    <button type="button" class="btn btn-sm" data-bs-toggle="collapse"
            data-bs-target="#modelConfig">
      <i class="bi bi-chevron-down"></i>
    </button>
  </div>
  <div id="modelConfig" class="collapse card-body">
    <!-- Response Format -->
    <div class="mb-3">
      <label>Response Format</label>
      <select name="response_format">
        <option value="auto">Auto</option>
        <option value="text">Text</option>
        <option value="json_object">JSON Object</option>
      </select>
    </div>

    <!-- Temperature -->
    <div class="mb-3">
      <label>Temperature: <span id="temp-value">1.0</span></label>
      <input type="range" name="temperature"
             min="0" max="2" step="0.1" value="1.0">
      <small>Controls randomness (0 = focused, 2 = creative)</small>
    </div>

    <!-- Top P -->
    <div class="mb-3">
      <label>Top P: <span id="top-p-value">1.0</span></label>
      <input type="range" name="top_p"
             min="0" max="1" step="0.05" value="1.0">
      <small>Nucleus sampling threshold</small>
    </div>
  </div>
</div>
```

#### Section 6: Actions
```html
<div class="d-grid gap-2">
  <!-- Save/Update Button -->
  <button type="button" class="btn btn-primary" id="saveAssistant">
    <i class="bi bi-save"></i>
    <span id="saveButtonText">Create Assistant</span>
  </button>

  <!-- Cancel/Back Button -->
  <a href="..." class="btn btn-outline-secondary">
    <i class="bi bi-arrow-left"></i> Back to Assistants
  </a>

  <!-- Status Indicator -->
  <div id="saveStatus" class="text-muted small">
    <i class="bi bi-clock"></i> Unsaved changes
  </div>
</div>
```

### Left Side: Thread Chat Interface

#### Thread Header
```html
<div class="thread-header">
  <h5>Test Conversation</h5>
  <div class="thread-actions">
    <button class="btn btn-sm btn-outline-primary" id="newThread">
      <i class="bi bi-plus-circle"></i> New Thread
    </button>
    <span class="badge bg-secondary" id="threadId">
      Thread: thread_abc123
    </span>
  </div>
</div>
```

#### Messages Container
```html
<div class="messages-container" id="messagesContainer">
  <!-- User Message -->
  <div class="message user-message">
    <div class="message-avatar">
      <i class="bi bi-person-circle"></i>
    </div>
    <div class="message-content">
      <div class="message-text">Hello, how can you help me?</div>
      <div class="message-meta">
        <small class="text-muted">2:30 PM</small>
      </div>
    </div>
  </div>

  <!-- Assistant Message -->
  <div class="message assistant-message">
    <div class="message-avatar">
      <i class="bi bi-robot"></i>
    </div>
    <div class="message-content">
      <div class="message-text">I can help you with...</div>
      <div class="message-meta">
        <small class="text-muted">2:30 PM</small>
        <span class="badge bg-info">gpt-4o</span>
      </div>
    </div>
  </div>

  <!-- Loading State -->
  <div class="message assistant-message loading" style="display: none;">
    <div class="message-avatar">
      <i class="bi bi-robot"></i>
    </div>
    <div class="message-content">
      <div class="typing-indicator">
        <span></span><span></span><span></span>
      </div>
    </div>
  </div>
</div>
```

#### Message Input
```html
<div class="message-input-container">
  <form id="messageForm">
    <div class="input-group">
      <textarea id="messageInput"
                class="form-control"
                rows="2"
                placeholder="Type your message..."
                required></textarea>
      <button type="submit" class="btn btn-primary" id="sendButton">
        <i class="bi bi-send"></i> Send
      </button>
    </div>
    <small class="text-muted">
      Press Enter to send, Shift+Enter for new line
    </small>
  </form>
</div>
```

## Data Flow & State Management

### Creating a New Assistant

```
User fills form → Click "Create Assistant" → AJAX POST to create_assistant
  ↓
Controller validates params → Service calls OpenAI API
  ↓
OpenAI returns assistant_id → Save to database → Return success
  ↓
Update UI with assistant_id → Enable thread testing → Show success message
```

### Updating an Existing Assistant

```
Load assistant data → Populate form → User makes changes
  ↓
Debounced auto-save (3 seconds) → AJAX POST to update_assistant
  ↓
Service calls OpenAI API assistants.update → Update database
  ↓
Return success → Update "Last saved" indicator
```

### Sending a Message

```
User types message → Click Send → Disable input → Show loading
  ↓
AJAX POST to send_message with thread_id, assistant_id, content
  ↓
Service: Add message to thread → Run assistant → Wait for completion
  ↓
Retrieve assistant response → Return formatted response
  ↓
Update UI: Add user message → Add assistant message → Enable input
```

### Thread Management

```
Initial load: No thread exists
  ↓
User sends first message → Auto-create thread → Store thread_id in session/state
  ↓
Subsequent messages use same thread_id
  ↓
Click "New Thread" → Create new thread → Clear messages → Update thread_id
```

## Service Implementation Details

### AssistantPlaygroundService

```ruby
# app/services/prompt_tracker/assistant_playground_service.rb

module PromptTracker
  class AssistantPlaygroundService
    class PlaygroundError < StandardError; end

    attr_reader :client

    def initialize
      @client = build_client
    end

    # Create a new assistant via OpenAI API
    def create_assistant(params)
      response = client.assistants.create(
        parameters: {
          name: params[:name],
          description: params[:description],
          instructions: params[:instructions],
          model: params[:model],
          tools: build_tools_array(params[:tools]),
          temperature: params[:temperature]&.to_f,
          top_p: params[:top_p]&.to_f,
          response_format: build_response_format(params[:response_format]),
          metadata: params[:metadata] || {}
        }
      )

      # Save to database
      assistant = PromptTracker::Openai::Assistant.create!(
        assistant_id: response['id'],
        name: response['name'],
        description: response['description'],
        metadata: {
          instructions: response['instructions'],
          model: response['model'],
          tools: response['tools'],
          temperature: response['temperature'],
          top_p: response['top_p'],
          response_format: response['response_format'],
          last_synced_at: Time.current.iso8601
        }
      )

      { success: true, assistant: assistant, api_response: response }
    rescue => e
      { success: false, error: e.message }
    end

    # Update existing assistant via OpenAI API
    def update_assistant(assistant_id, params)
      response = client.assistants.update(
        id: assistant_id,
        parameters: {
          name: params[:name],
          description: params[:description],
          instructions: params[:instructions],
          model: params[:model],
          tools: build_tools_array(params[:tools]),
          temperature: params[:temperature]&.to_f,
          top_p: params[:top_p]&.to_f,
          response_format: build_response_format(params[:response_format]),
          metadata: params[:metadata] || {}
        }
      )

      # Update database
      assistant = PromptTracker::Openai::Assistant.find_by(assistant_id: assistant_id)
      assistant.update!(
        name: response['name'],
        description: response['description'],
        metadata: {
          instructions: response['instructions'],
          model: response['model'],
          tools: response['tools'],
          temperature: response['temperature'],
          top_p: response['top_p'],
          response_format: response['response_format'],
          last_synced_at: Time.current.iso8601
        }
      )

      { success: true, assistant: assistant, api_response: response }
    rescue => e
      { success: false, error: e.message }
    end

    # Create a new thread
    def create_thread
      response = client.threads.create
      { success: true, thread_id: response['id'] }
    rescue => e
      { success: false, error: e.message }
    end

    # Send message and run assistant
    def send_message(thread_id:, assistant_id:, content:, timeout: 60)
      # Add user message
      client.messages.create(
        thread_id: thread_id,
        parameters: {
          role: 'user',
          content: content
        }
      )

      # Run assistant
      run = client.runs.create(
        thread_id: thread_id,
        parameters: { assistant_id: assistant_id }
      )

      # Wait for completion
      final_run = wait_for_completion(thread_id, run['id'], timeout)

      # Get assistant's response
      messages = client.messages.list(
        thread_id: thread_id,
        parameters: { order: 'desc', limit: 1 }
      )

      assistant_message = messages['data'].first

      {
        success: true,
        message: {
          role: 'assistant',
          content: assistant_message.dig('content', 0, 'text', 'value'),
          created_at: Time.at(assistant_message['created_at']),
          run_id: run['id']
        },
        usage: final_run['usage']
      }
    rescue => e
      { success: false, error: e.message }
    end

    # Load thread messages
    def load_messages(thread_id:, limit: 50)
      response = client.messages.list(
        thread_id: thread_id,
        parameters: { order: 'asc', limit: limit }
      )

      messages = response['data'].map do |msg|
        {
          role: msg['role'],
          content: msg.dig('content', 0, 'text', 'value'),
          created_at: Time.at(msg['created_at'])
        }
      end

      { success: true, messages: messages }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def build_client
      require 'openai'
      api_key = ENV['OPENAI_LOUNA_API_KEY'] || ENV['OPENAI_API_KEY']
      raise PlaygroundError, 'OpenAI API key not configured' if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end

    def build_tools_array(tools_param)
      return [] if tools_param.blank?

      tools = []
      tools << { type: 'file_search' } if tools_param.include?('file_search')
      tools << { type: 'code_interpreter' } if tools_param.include?('code_interpreter')
      tools
    end

    def build_response_format(format)
      return nil if format.blank? || format == 'auto'
      { type: format }
    end

    def wait_for_completion(thread_id, run_id, timeout)
      start_time = Time.now

      loop do
        run = client.runs.retrieve(thread_id: thread_id, id: run_id)

        case run['status']
        when 'completed'
          return run
        when 'failed', 'cancelled', 'expired'
          raise PlaygroundError, "Run #{run['status']}: #{run.dig('last_error', 'message')}"
        when 'requires_action'
          raise PlaygroundError, 'Tool calls not yet supported in playground'
        end

        if Time.now - start_time > timeout
          raise PlaygroundError, "Run timed out after #{timeout} seconds"
        end

        sleep 1
      end
    end
  end
end
```

## Controller Implementation

### AssistantPlaygroundController

```ruby
# app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb

module PromptTracker
  module Testing
    module Openai
      class AssistantPlaygroundController < ApplicationController
        before_action :set_assistant, only: [:show]
        before_action :initialize_service

        # GET /testing/openai/assistants/:assistant_id/playground
        # OR /testing/openai/assistants/new/playground (for new assistant)
        def show
          @assistant ||= PromptTracker::Openai::Assistant.new
          @is_new = @assistant.new_record?

          # Get available models from configuration or defaults
          @available_models = [
            { id: 'gpt-4o', name: 'GPT-4o' },
            { id: 'gpt-4-turbo', name: 'GPT-4 Turbo' },
            { id: 'gpt-4', name: 'GPT-4' },
            { id: 'gpt-3.5-turbo', name: 'GPT-3.5 Turbo' }
          ]
        end

        # POST /testing/openai/assistants/playground/create_assistant
        def create_assistant
          result = @service.create_assistant(assistant_params)

          if result[:success]
            render json: {
              success: true,
              assistant_id: result[:assistant].assistant_id,
              message: 'Assistant created successfully',
              redirect_url: testing_openai_assistant_playground_path(result[:assistant])
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/update_assistant
        def update_assistant
          result = @service.update_assistant(params[:assistant_id], assistant_params)

          if result[:success]
            render json: {
              success: true,
              message: 'Assistant updated successfully',
              last_saved_at: Time.current.strftime('%I:%M %p')
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/create_thread
        def create_thread
          result = @service.create_thread

          if result[:success]
            session[:playground_thread_id] = result[:thread_id]
            render json: {
              success: true,
              thread_id: result[:thread_id]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # POST /testing/openai/assistants/:assistant_id/playground/send_message
        def send_message
          thread_id = params[:thread_id] || session[:playground_thread_id]

          # Auto-create thread if needed
          if thread_id.blank?
            thread_result = @service.create_thread
            return render json: { success: false, error: 'Failed to create thread' },
                          status: :unprocessable_entity unless thread_result[:success]
            thread_id = thread_result[:thread_id]
            session[:playground_thread_id] = thread_id
          end

          result = @service.send_message(
            thread_id: thread_id,
            assistant_id: params[:assistant_id],
            content: params[:content]
          )

          if result[:success]
            render json: {
              success: true,
              thread_id: thread_id,
              message: result[:message],
              usage: result[:usage]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        # GET /testing/openai/assistants/:assistant_id/playground/load_messages
        def load_messages
          thread_id = params[:thread_id] || session[:playground_thread_id]

          if thread_id.blank?
            return render json: { success: true, messages: [] }
          end

          result = @service.load_messages(thread_id: thread_id)

          if result[:success]
            render json: {
              success: true,
              messages: result[:messages]
            }
          else
            render json: {
              success: false,
              error: result[:error]
            }, status: :unprocessable_entity
          end
        end

        private

        def set_assistant
          @assistant = PromptTracker::Openai::Assistant.find(params[:assistant_id]) if params[:assistant_id] != 'new'
        end

        def initialize_service
          @service = AssistantPlaygroundService.new
        end

        def assistant_params
          params.require(:assistant).permit(
            :name,
            :description,
            :instructions,
            :model,
            :temperature,
            :top_p,
            :response_format,
            tools: [],
            metadata: {}
          )
        end
      end
    end
  end
end
```

## JavaScript Stimulus Controller

```javascript
// app/javascript/prompt_tracker/controllers/assistant_playground_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "name", "description", "instructions", "model",
    "temperature", "temperatureValue", "topP", "topPValue",
    "responseFormat", "toolCheckbox",
    "messagesContainer", "messageInput", "sendButton",
    "threadId", "newThreadButton",
    "saveButton", "saveButtonText", "saveStatus",
    "loadingIndicator", "charCount"
  ]

  static values = {
    assistantId: String,
    isNew: Boolean,
    createUrl: String,
    updateUrl: String,
    sendMessageUrl: String,
    createThreadUrl: String,
    loadMessagesUrl: String
  }

  connect() {
    this.threadId = null
    this.autoSaveTimer = null
    this.autoSaveDelay = 3000 // 3 seconds

    this.attachEventListeners()
    this.updateCharCount()

    // Load existing thread messages if assistant exists
    if (!this.isNewValue && this.threadId) {
      this.loadMessages()
    }
  }

  disconnect() {
    if (this.autoSaveTimer) {
      clearTimeout(this.autoSaveTimer)
    }
  }

  attachEventListeners() {
    // Auto-save on configuration changes
    const configInputs = [
      this.nameTarget, this.descriptionTarget, this.instructionsTarget,
      this.modelTarget, this.temperatureTarget, this.topPTarget,
      this.responseFormatTarget
    ]

    configInputs.forEach(input => {
      if (input) {
        input.addEventListener('input', () => this.scheduleAutoSave())
      }
    })

    // Tool checkboxes
    this.toolCheckboxTargets.forEach(checkbox => {
      checkbox.addEventListener('change', () => this.scheduleAutoSave())
    })

    // Range input value display
    if (this.hasTemperatureTarget) {
      this.temperatureTarget.addEventListener('input', (e) => {
        this.temperatureValueTarget.textContent = e.target.value
      })
    }

    if (this.hasTopPTarget) {
      this.topPTarget.addEventListener('input', (e) => {
        this.topPValueTarget.textContent = e.target.value
      })
    }

    // Character count
    if (this.hasInstructionsTarget) {
      this.instructionsTarget.addEventListener('input', () => {
        this.updateCharCount()
      })
    }

    // Enter key handling for message input
    if (this.hasMessageInputTarget) {
      this.messageInputTarget.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          this.sendMessage()
        }
      })
    }
  }

  // Save assistant (create or update)
  async saveAssistant(event) {
    event?.preventDefault()

    const formData = this.buildFormData()
    const url = this.isNewValue ? this.createUrlValue : this.updateUrlValue

    this.setSaveButtonLoading(true)

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken()
        },
        body: JSON.stringify(formData)
      })

      const data = await response.json()

      if (data.success) {
        this.showSaveSuccess(data.message)

        // If creating new assistant, redirect to edit mode
        if (this.isNewValue && data.redirect_url) {
          window.location.href = data.redirect_url
        } else {
          this.updateSaveStatus('Saved at ' + data.last_saved_at)
        }
      } else {
        this.showSaveError(data.error)
      }
    } catch (error) {
      this.showSaveError('Failed to save assistant: ' + error.message)
    } finally {
      this.setSaveButtonLoading(false)
    }
  }

  // Schedule auto-save (debounced)
  scheduleAutoSave() {
    // Don't auto-save for new assistants
    if (this.isNewValue) {
      this.updateSaveStatus('Unsaved changes')
      return
    }

    if (this.autoSaveTimer) {
      clearTimeout(this.autoSaveTimer)
    }

    this.updateSaveStatus('Saving...')

    this.autoSaveTimer = setTimeout(() => {
      this.saveAssistant()
    }, this.autoSaveDelay)
  }

  // Send message in thread
  async sendMessage(event) {
    event?.preventDefault()

    const content = this.messageInputTarget.value.trim()
    if (!content) return

    // Can't send messages without assistant_id
    if (!this.assistantIdValue) {
      alert('Please save the assistant first before testing')
      return
    }

    // Add user message to UI immediately
    this.addMessageToUI('user', content)
    this.messageInputTarget.value = ''

    // Show loading indicator
    this.showAssistantTyping()
    this.setSendButtonLoading(true)

    try {
      const response = await fetch(this.sendMessageUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken()
        },
        body: JSON.stringify({
          assistant_id: this.assistantIdValue,
          thread_id: this.threadId,
          content: content
        })
      })

      const data = await response.json()

      if (data.success) {
        // Update thread ID if it was auto-created
        if (data.thread_id) {
          this.threadId = data.thread_id
          this.updateThreadIdDisplay(data.thread_id)
        }

        // Add assistant message to UI
        this.hideAssistantTyping()
        this.addMessageToUI('assistant', data.message.content, data.message.created_at)
      } else {
        this.hideAssistantTyping()
        this.showMessageError(data.error)
      }
    } catch (error) {
      this.hideAssistantTyping()
      this.showMessageError('Failed to send message: ' + error.message)
    } finally {
      this.setSendButtonLoading(false)
    }
  }

  // Create new thread
  async createNewThread(event) {
    event?.preventDefault()

    if (!confirm('Start a new conversation? Current messages will be cleared.')) {
      return
    }

    try {
      const response = await fetch(this.createThreadUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCsrfToken()
        }
      })

      const data = await response.json()

      if (data.success) {
        this.threadId = data.thread_id
        this.updateThreadIdDisplay(data.thread_id)
        this.clearMessages()
      } else {
        alert('Failed to create thread: ' + data.error)
      }
    } catch (error) {
      alert('Failed to create thread: ' + error.message)
    }
  }

  // Load existing messages
  async loadMessages() {
    if (!this.threadId) return

    try {
      const response = await fetch(
        `${this.loadMessagesUrlValue}?thread_id=${this.threadId}`
      )

      const data = await response.json()

      if (data.success) {
        this.clearMessages()
        data.messages.forEach(msg => {
          this.addMessageToUI(msg.role, msg.content, msg.created_at)
        })
      }
    } catch (error) {
      console.error('Failed to load messages:', error)
    }
  }

  // UI Helper Methods

  buildFormData() {
    const tools = []
    this.toolCheckboxTargets.forEach(checkbox => {
      if (checkbox.checked) {
        tools.push(checkbox.value)
      }
    })

    return {
      assistant: {
        name: this.nameTarget.value,
        description: this.descriptionTarget.value,
        instructions: this.instructionsTarget.value,
        model: this.modelTarget.value,
        temperature: this.temperatureTarget.value,
        top_p: this.topPTarget.value,
        response_format: this.responseFormatTarget.value,
        tools: tools
      }
    }
  }

  addMessageToUI(role, content, timestamp = null) {
    const messageDiv = document.createElement('div')
    messageDiv.className = `message ${role}-message`

    const time = timestamp ? new Date(timestamp).toLocaleTimeString() : new Date().toLocaleTimeString()

    messageDiv.innerHTML = `
      <div class="message-avatar">
        <i class="bi bi-${role === 'user' ? 'person-circle' : 'robot'}"></i>
      </div>
      <div class="message-content">
        <div class="message-text">${this.escapeHtml(content)}</div>
        <div class="message-meta">
          <small class="text-muted">${time}</small>
        </div>
      </div>
    `

    this.messagesContainerTarget.appendChild(messageDiv)
    this.scrollToBottom()
  }

  showAssistantTyping() {
    const loadingDiv = this.messagesContainerTarget.querySelector('.loading')
    if (loadingDiv) {
      loadingDiv.style.display = 'flex'
      this.scrollToBottom()
    }
  }

  hideAssistantTyping() {
    const loadingDiv = this.messagesContainerTarget.querySelector('.loading')
    if (loadingDiv) {
      loadingDiv.style.display = 'none'
    }
  }

  clearMessages() {
    // Keep only the loading indicator
    const loadingDiv = this.messagesContainerTarget.querySelector('.loading')
    this.messagesContainerTarget.innerHTML = ''
    if (loadingDiv) {
      this.messagesContainerTarget.appendChild(loadingDiv)
    }
  }

  scrollToBottom() {
    this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
  }

  updateThreadIdDisplay(threadId) {
    if (this.hasThreadIdTarget) {
      this.threadIdTarget.textContent = `Thread: ${threadId.substring(0, 20)}...`
    }
  }

  updateCharCount() {
    if (this.hasCharCountTarget && this.hasInstructionsTarget) {
      const count = this.instructionsTarget.value.length
      this.charCountTarget.textContent = count.toLocaleString()
    }
  }

  updateSaveStatus(text) {
    if (this.hasSaveStatusTarget) {
      this.saveStatusTarget.innerHTML = `<i class="bi bi-clock"></i> ${text}`
    }
  }

  setSaveButtonLoading(loading) {
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = loading
      if (loading) {
        this.saveButtonTextTarget.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Saving...'
      } else {
        this.saveButtonTextTarget.textContent = this.isNewValue ? 'Create Assistant' : 'Update Assistant'
      }
    }
  }

  setSendButtonLoading(loading) {
    if (this.hasSendButtonTarget) {
      this.sendButtonTarget.disabled = loading
    }
  }

  showSaveSuccess(message) {
    // Could use toast notification here
    console.log('Success:', message)
  }

  showSaveError(error) {
    alert('Error: ' + error)
  }

  showMessageError(error) {
    this.addMessageToUI('system', `Error: ${error}`)
  }

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
```

## CSS Styling

```css
/* app/assets/stylesheets/prompt_tracker/assistant_playground.css */

.assistant-playground {
  display: flex;
  height: calc(100vh - 100px);
  gap: 1rem;
}

/* Left Side - Thread Chat */
.playground-thread {
  flex: 1 1 60%;
  display: flex;
  flex-direction: column;
  background: white;
  border: 1px solid #dee2e6;
  border-radius: 0.5rem;
  overflow: hidden;
}

.thread-header {
  padding: 1rem;
  border-bottom: 1px solid #dee2e6;
  background: #f8f9fa;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.thread-actions {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.messages-container {
  flex: 1;
  overflow-y: auto;
  padding: 1rem;
  background: #f8f9fa;
}

.message {
  display: flex;
  gap: 0.75rem;
  margin-bottom: 1rem;
  animation: fadeIn 0.3s ease-in;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.message-avatar {
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
}

.user-message .message-avatar {
  background: #e3f2fd;
  color: #1976d2;
}

.assistant-message .message-avatar {
  background: #f3e5f5;
  color: #7b1fa2;
}

.message-content {
  flex: 1;
  min-width: 0;
}

.message-text {
  background: white;
  padding: 0.75rem 1rem;
  border-radius: 0.5rem;
  box-shadow: 0 1px 2px rgba(0,0,0,0.1);
  white-space: pre-wrap;
  word-wrap: break-word;
}

.user-message .message-text {
  background: #e3f2fd;
}

.assistant-message .message-text {
  background: white;
}

.message-meta {
  margin-top: 0.25rem;
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.typing-indicator {
  display: flex;
  gap: 0.25rem;
  padding: 0.75rem 1rem;
}

.typing-indicator span {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #999;
  animation: typing 1.4s infinite;
}

.typing-indicator span:nth-child(2) {
  animation-delay: 0.2s;
}

.typing-indicator span:nth-child(3) {
  animation-delay: 0.4s;
}

@keyframes typing {
  0%, 60%, 100% { transform: translateY(0); }
  30% { transform: translateY(-10px); }
}

.message-input-container {
  padding: 1rem;
  border-top: 1px solid #dee2e6;
  background: white;
}

.message-input-container textarea {
  resize: none;
  border-radius: 0.5rem 0 0 0.5rem;
}

.message-input-container button {
  border-radius: 0 0.5rem 0.5rem 0;
}

/* Right Side - Configuration */
.playground-config {
  flex: 0 0 40%;
  overflow-y: auto;
  padding: 1rem;
  background: #f8f9fa;
  border: 1px solid #dee2e6;
  border-radius: 0.5rem;
}

.playground-config .card {
  margin-bottom: 1rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}

.playground-config .card-header {
  background: white;
  font-weight: 600;
  border-bottom: 2px solid #e3f2fd;
}

.playground-config textarea {
  font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
  font-size: 0.875rem;
}

.playground-config input[type="range"] {
  width: 100%;
}

.form-check {
  padding: 0.75rem;
  border: 1px solid #dee2e6;
  border-radius: 0.25rem;
  margin-bottom: 0.5rem;
  transition: background-color 0.2s;
}

.form-check:hover {
  background-color: #f8f9fa;
}

.form-check input:checked ~ label {
  font-weight: 600;
  color: #1976d2;
}

/* Responsive */
@media (max-width: 992px) {
  .assistant-playground {
    flex-direction: column;
    height: auto;
  }

  .playground-thread {
    min-height: 500px;
  }

  .playground-config {
    flex: 1;
  }
}

/* Loading states */
.btn.loading {
  position: relative;
  color: transparent;
}

.btn.loading::after {
  content: "";
  position: absolute;
  width: 16px;
  height: 16px;
  top: 50%;
  left: 50%;
  margin-left: -8px;
  margin-top: -8px;
  border: 2px solid #fff;
  border-radius: 50%;
  border-top-color: transparent;
  animation: spinner 0.6s linear infinite;
}

@keyframes spinner {
  to { transform: rotate(360deg); }
}
```

## Implementation Steps

### Phase 1: Backend Foundation (Day 1)

1. **Create Service**
   - [ ] Create `AssistantPlaygroundService` in `app/services/prompt_tracker/`
   - [ ] Implement `create_assistant` method
   - [ ] Implement `update_assistant` method
   - [ ] Implement `create_thread` method
   - [ ] Implement `send_message` method
   - [ ] Implement `load_messages` method
   - [ ] Add error handling and validation

2. **Create Controller**
   - [ ] Create `AssistantPlaygroundController` in `app/controllers/prompt_tracker/testing/openai/`
   - [ ] Implement all actions (show, create_assistant, update_assistant, etc.)
   - [ ] Add before_action filters
   - [ ] Add strong parameters

3. **Add Routes**
   - [ ] Add playground routes under `testing/openai/assistants`
   - [ ] Test routes with `rails routes | grep playground`

### Phase 2: Frontend UI (Day 2)

4. **Create View**
   - [ ] Create `show.html.erb` in `app/views/prompt_tracker/testing/openai/assistant_playground/`
   - [ ] Build split-screen layout structure
   - [ ] Add right sidebar configuration form
   - [ ] Add left side thread chat interface
   - [ ] Add Stimulus controller data attributes

5. **Add CSS**
   - [ ] Create `assistant_playground.css` in `app/assets/stylesheets/prompt_tracker/`
   - [ ] Style split-screen layout
   - [ ] Style message bubbles
   - [ ] Style configuration cards
   - [ ] Add responsive breakpoints
   - [ ] Add loading animations

### Phase 3: JavaScript Interactivity (Day 3)

6. **Create Stimulus Controller**
   - [ ] Create `assistant_playground_controller.js` in `app/javascript/prompt_tracker/controllers/`
   - [ ] Implement save assistant functionality
   - [ ] Implement auto-save with debouncing
   - [ ] Implement send message functionality
   - [ ] Implement thread management
   - [ ] Add loading states
   - [ ] Add error handling

7. **Register Controller**
   - [ ] Add to Stimulus controller index
   - [ ] Test controller connection

### Phase 4: Integration & Testing (Day 4)

8. **Integration**
   - [ ] Add "Playground" button to assistant show page
   - [ ] Add "Create in Playground" button to assistants index
   - [ ] Update navigation breadcrumbs
   - [ ] Test full create flow
   - [ ] Test full update flow
   - [ ] Test thread conversation flow

9. **Testing**
   - [ ] Write service specs
   - [ ] Write controller specs
   - [ ] Write system specs for playground
   - [ ] Test error scenarios
   - [ ] Test edge cases (empty fields, API failures, etc.)

10. **Documentation**
    - [ ] Update README with playground feature
    - [ ] Add inline code documentation
    - [ ] Create user guide screenshots
    - [ ] Update CHANGELOG

## Testing Considerations

### Unit Tests (RSpec)

```ruby
# spec/services/prompt_tracker/assistant_playground_service_spec.rb
RSpec.describe PromptTracker::AssistantPlaygroundService do
  describe '#create_assistant' do
    it 'creates assistant via OpenAI API'
    it 'saves assistant to database'
    it 'handles API errors gracefully'
    it 'validates required parameters'
  end

  describe '#update_assistant' do
    it 'updates assistant via OpenAI API'
    it 'updates database record'
    it 'handles non-existent assistant'
  end

  describe '#send_message' do
    it 'sends message to thread'
    it 'runs assistant'
    it 'waits for completion'
    it 'retrieves response'
    it 'handles timeout'
  end
end

# spec/controllers/prompt_tracker/testing/openai/assistant_playground_controller_spec.rb
RSpec.describe PromptTracker::Testing::Openai::AssistantPlaygroundController do
  describe 'GET #show' do
    it 'renders playground for new assistant'
    it 'renders playground for existing assistant'
    it 'loads assistant data'
  end

  describe 'POST #create_assistant' do
    it 'creates assistant successfully'
    it 'returns JSON response'
    it 'handles validation errors'
  end

  describe 'POST #send_message' do
    it 'sends message successfully'
    it 'auto-creates thread if needed'
    it 'returns formatted response'
  end
end
```

### System Tests

```ruby
# spec/system/assistant_playground_spec.rb
RSpec.describe 'Assistant Playground', type: :system do
  it 'creates new assistant from playground' do
    visit new_testing_openai_assistant_playground_path

    fill_in 'Name', with: 'Test Assistant'
    fill_in 'Instructions', with: 'You are helpful'
    select 'GPT-4o', from: 'Model'
    check 'File Search'

    click_button 'Create Assistant'

    expect(page).to have_content('Assistant created successfully')
  end

  it 'sends messages in thread' do
    assistant = create(:openai_assistant)
    visit testing_openai_assistant_playground_path(assistant)

    fill_in 'Message', with: 'Hello'
    click_button 'Send'

    expect(page).to have_content('Hello')
    # Wait for assistant response
    expect(page).to have_css('.assistant-message', wait: 10)
  end

  it 'auto-saves configuration changes' do
    assistant = create(:openai_assistant)
    visit testing_openai_assistant_playground_path(assistant)

    fill_in 'Instructions', with: 'Updated instructions'

    # Wait for auto-save
    expect(page).to have_content('Saved at', wait: 5)
  end
end
```

## Edge Cases & Error Handling

1. **API Failures**
   - OpenAI API down → Show friendly error message
   - Rate limiting → Show retry message
   - Invalid API key → Show configuration error

2. **Validation**
   - Empty name → Show validation error
   - Empty instructions → Allow (optional)
   - Invalid model → Show error
   - No tools selected → Allow (optional)

3. **Thread Management**
   - Thread expires → Auto-create new thread
   - Message send fails → Show error, keep message in input
   - Long-running assistant → Show timeout warning

4. **State Management**
   - Unsaved changes → Warn before leaving page
   - Auto-save conflicts → Use last-write-wins
   - Session expires → Redirect to login

## Future Enhancements

1. **Function Calling Support**
   - UI for defining custom functions
   - Function schema editor
   - Test function calls in playground

2. **File Upload**
   - Upload files for file_search
   - Upload files for code_interpreter
   - Manage vector stores

3. **Advanced Features**
   - Export conversation as dataset
   - Save conversation templates
   - Compare assistant versions
   - A/B test different configurations

4. **Collaboration**
   - Share playground sessions
   - Comment on conversations
   - Team workspaces

## Success Criteria

✅ Users can create new assistants directly from playground
✅ Users can edit existing assistants with live preview
✅ Users can test assistants in real-time conversations
✅ All OpenAI assistant parameters are configurable
✅ Auto-save prevents data loss
✅ Thread management is seamless
✅ Error handling is robust and user-friendly
✅ UI is responsive and intuitive
✅ Performance is acceptable (< 2s for message send)
✅ Code is well-tested (> 80% coverage)

## Conclusion

This implementation plan provides a comprehensive roadmap for building an OpenAI Assistant playground that matches the functionality of the OpenAI platform. The split-screen design allows users to configure and test assistants simultaneously, providing immediate feedback and a superior developer experience.

The architecture is modular, testable, and follows Rails best practices. The service layer abstracts OpenAI API complexity, the controller handles HTTP concerns, and the Stimulus controller provides rich interactivity without page reloads.

**Estimated Timeline**: 4 days for MVP
**Estimated Effort**: 1 developer, full-time
**Dependencies**: ruby-openai gem, Bootstrap 5, Stimulus.js
