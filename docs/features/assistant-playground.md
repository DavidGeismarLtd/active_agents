# OpenAI Assistant Playground

## Overview

The Assistant Playground is an interactive interface for creating, editing, and testing OpenAI Assistants directly within the PromptTracker application. It provides a split-screen layout similar to OpenAI's Playground, allowing you to configure assistants and test them in real-time.

## Features

### ✅ Complete Assistant Configuration
- **Basic Information**: Name and description
- **System Instructions**: Full control over assistant behavior
- **Model Selection**: Choose from GPT-4o, GPT-4 Turbo, GPT-4, GPT-3.5 Turbo
- **Tools**: Enable file_search, code_interpreter (functions coming soon)
- **Model Configuration**: Temperature, Top P, Response Format

### ✅ Real-Time Testing
- **Thread Management**: Create new conversation threads
- **Live Chat**: Test your assistant with real conversations
- **Message History**: View full conversation history
- **Typing Indicators**: Visual feedback during assistant responses

### ✅ Auto-Save
- **Debounced Saving**: Automatically saves changes after 3 seconds of inactivity
- **Save Status**: Visual indicator showing save state (saving/saved/error)
- **Manual Save**: Option to save immediately

## Architecture

### Backend Components

#### 1. AssistantPlaygroundService
**Location**: `app/services/prompt_tracker/assistant_playground_service.rb`

Handles all OpenAI API interactions:
- `create_assistant(params)` - Creates new assistant via API
- `update_assistant(assistant_id, params)` - Updates existing assistant
- `create_thread()` - Creates new conversation thread
- `send_message(thread_id:, assistant_id:, content:)` - Sends message and runs assistant
- `load_messages(thread_id:)` - Loads thread message history

#### 2. AssistantPlaygroundController
**Location**: `app/controllers/prompt_tracker/testing/openai/assistant_playground_controller.rb`

HTTP request handling:
- `show` - Renders playground interface
- `create_assistant` - POST endpoint for creating assistants
- `update_assistant` - POST endpoint for updating assistants
- `send_message` - POST endpoint for sending messages
- `create_thread` - POST endpoint for creating threads
- `load_messages` - GET endpoint for loading messages

#### 3. Routes
**Location**: `config/routes.rb`

```ruby
resource :playground, only: [:show], controller: "assistant_playground" do
  post :create_assistant
  post :update_assistant
  post :send_message
  post :create_thread
  get  :load_messages
end
```

### Frontend Components

#### 1. View Template
**Location**: `app/views/prompt_tracker/testing/openai/assistant_playground/show.html.erb`

Split-screen HTML structure:
- **Left (60%)**: Thread chat interface
- **Right (40%)**: Configuration sidebar

#### 2. CSS Styling
**Location**: `app/assets/stylesheets/prompt_tracker/assistant_playground.css`

Modern, responsive design with:
- Gradient avatars for user/assistant messages
- Smooth animations and transitions
- Typing indicators
- Custom scrollbars
- Mobile-responsive layout

#### 3. Stimulus Controller
**Location**: `app/javascript/controllers/assistant_playground_controller.js`

Interactive JavaScript for:
- Real-time message sending
- Thread management
- Auto-save with debouncing
- Character counting
- Keyboard shortcuts (Enter to send, Shift+Enter for new line)

## Usage

### Accessing the Playground

1. **From Assistant Show Page**: Click the "Playground" button
2. **Direct URL**: `/testing/openai/assistants/:id/playground`

### Creating a New Assistant

1. Navigate to the playground
2. Fill in basic information (name, description)
3. Write system instructions
4. Select model and tools
5. Configure temperature and top_p if needed
6. Click "Create Assistant"
7. Start testing immediately after creation

### Editing an Existing Assistant

1. Open the playground for an existing assistant
2. Make changes to any configuration
3. Changes auto-save after 3 seconds
4. Or click "Update Assistant" to save immediately

### Testing Your Assistant

1. Type a message in the input box
2. Press Enter to send (Shift+Enter for new line)
3. Watch the typing indicator while assistant responds
4. View full conversation history
5. Create new threads to start fresh conversations

## API Integration

### OpenAI API Endpoints Used

- `POST /v1/assistants` - Create assistant
- `POST /v1/assistants/{id}` - Update assistant
- `POST /v1/threads` - Create thread
- `POST /v1/threads/{thread_id}/messages` - Add message
- `POST /v1/threads/{thread_id}/runs` - Run assistant
- `GET /v1/threads/{thread_id}/runs/{run_id}` - Check run status
- `GET /v1/threads/{thread_id}/messages` - List messages

### Error Handling

The service handles:
- API failures (network errors, rate limits)
- Timeouts (default 60 seconds for runs)
- Validation errors (missing required fields)
- Run failures (failed, cancelled, expired runs)

## Configuration

### Environment Variables

- `OPENAI_LOUNA_API_KEY` - Primary OpenAI API key (used first)
- `OPENAI_API_KEY` - Fallback OpenAI API key

### Available Models

Configured in controller:
- GPT-4o
- GPT-4 Turbo
- GPT-4
- GPT-3.5 Turbo

### Supported Tools

- ✅ File Search - Search through uploaded files
- ✅ Code Interpreter - Execute Python code
- 🚧 Functions - Custom function calling (coming soon)

## Testing

### RSpec Tests

**Location**: `spec/services/prompt_tracker/assistant_playground_service_spec.rb`

Tests cover:
- Creating assistants
- Updating assistants
- Creating threads
- Sending messages
- Error handling

Run tests:
```bash
bundle exec rspec spec/services/prompt_tracker/assistant_playground_service_spec.rb
```

## Future Enhancements

- [ ] Function calling support
- [ ] File upload for file_search tool
- [ ] Export conversation history
- [ ] Share playground sessions
- [ ] Conversation templates
- [ ] Multi-turn conversation testing
- [ ] Performance metrics (latency, token usage)
- [ ] A/B testing different configurations

## Troubleshooting

### "OpenAI API key not configured"
- Ensure `OPENAI_LOUNA_API_KEY` or `OPENAI_API_KEY` is set in environment

### "Run timed out"
- Increase timeout parameter in `send_message` call
- Check OpenAI API status

### Auto-save not working
- Check browser console for JavaScript errors
- Verify CSRF token is present

### Messages not loading
- Check thread_id is valid
- Verify assistant has permission to access thread

## Related Documentation

- [OpenAI Assistants API Documentation](https://platform.openai.com/docs/assistants/overview)
- [Assistant Testing MVP Plan](../plans/assistant-conversation-testing-mvp.md)
- [Implementation Plan](../plans/assistant-playground-implementation.md)

