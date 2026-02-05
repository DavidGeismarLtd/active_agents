# OpenAI Assistants API

## Overview
The Assistants API allows you to build AI assistants with:
- Instructions and model selection
- Access to tools (Code Interpreter, File Search, Function calling)
- Persistent threads for conversations
- File handling capabilities

## Core Concepts

### Assistant
A configured AI with instructions, model, and tools.

### Thread
A conversation session between user and assistant.

### Message
A message within a thread (user or assistant).

### Run
An invocation of an assistant on a thread.

### Run Step
Detailed steps the assistant took during a run.

## Create Assistant

```
POST https://api.openai.com/v1/assistants
```

### Request Body
```json
{
  "model": "gpt-4o",
  "name": "Math Tutor",
  "instructions": "You are a personal math tutor. Help students with math problems.",
  "tools": [
    {"type": "code_interpreter"},
    {"type": "file_search"}
  ],
  "tool_resources": {
    "file_search": {
      "vector_store_ids": ["vs_abc123"]
    }
  },
  "metadata": {
    "user_id": "user_123"
  }
}
```

### Parameters
- **model** (required): Model ID (e.g., `gpt-4o`, `gpt-4-turbo`)
- **name**: Name of the assistant (max 256 chars)
- **description**: Description (max 512 chars)
- **instructions**: System instructions (max 256,000 chars)
- **tools**: Array of tools (`code_interpreter`, `file_search`, `function`)
- **tool_resources**: Resources for tools (vector stores, code interpreter files)
- **metadata**: Key-value pairs (max 16 pairs)
- **temperature**: 0-2 (default: 1)
- **top_p**: 0-1 (default: 1)
- **response_format**: `auto` or `{"type": "json_object"}`

## Create Thread

```
POST https://api.openai.com/v1/threads
```

### Request Body
```json
{
  "messages": [
    {
      "role": "user",
      "content": "Solve this equation: 3x + 11 = 14"
    }
  ],
  "metadata": {
    "session_id": "session_123"
  }
}
```

## Add Message to Thread

```
POST https://api.openai.com/v1/threads/{thread_id}/messages
```

### Request Body
```json
{
  "role": "user",
  "content": "What is the solution?",
  "attachments": [
    {
      "file_id": "file-abc123",
      "tools": [{"type": "file_search"}]
    }
  ]
}
```

## Create Run

```
POST https://api.openai.com/v1/threads/{thread_id}/runs
```

### Request Body
```json
{
  "assistant_id": "asst_abc123",
  "instructions": "Please address the user as Jane Doe.",
  "additional_instructions": "Be concise.",
  "additional_messages": [
    {
      "role": "user",
      "content": "Extra context here"
    }
  ],
  "tools": [{"type": "code_interpreter"}],
  "metadata": {
    "run_type": "test"
  }
}
```

### Parameters
- **assistant_id** (required): ID of assistant to use
- **model**: Override assistant's model
- **instructions**: Override assistant's instructions
- **additional_instructions**: Append to instructions
- **additional_messages**: Add messages before run
- **tools**: Override assistant's tools
- **stream**: Enable streaming
- **temperature**, **top_p**, **max_prompt_tokens**, **max_completion_tokens**

## Run Status

A run can have these statuses:
- `queued`: Waiting to be processed
- `in_progress`: Currently running
- `requires_action`: Waiting for function call results
- `cancelling`: Being cancelled
- `cancelled`: Cancelled
- `failed`: Failed
- `completed`: Successfully completed
- `incomplete`: Incomplete (max tokens/time reached)
- `expired`: Expired before completion

## Retrieve Run

```
GET https://api.openai.com/v1/threads/{thread_id}/runs/{run_id}
```

### Response
```json
{
  "id": "run_abc123",
  "object": "thread.run",
  "created_at": 1699063290,
  "assistant_id": "asst_abc123",
  "thread_id": "thread_abc123",
  "status": "completed",
  "started_at": 1699063290,
  "completed_at": 1699063291,
  "model": "gpt-4o",
  "instructions": "You are a helpful assistant.",
  "tools": [{"type": "code_interpreter"}],
  "metadata": {},
  "usage": {
    "prompt_tokens": 123,
    "completion_tokens": 456,
    "total_tokens": 579
  }
}
```

## List Messages

```
GET https://api.openai.com/v1/threads/{thread_id}/messages
```

### Response
```json
{
  "object": "list",
  "data": [
    {
      "id": "msg_abc123",
      "object": "thread.message",
      "created_at": 1699017614,
      "thread_id": "thread_abc123",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": {
            "value": "The solution is x = 1",
            "annotations": []
          }
        }
      ],
      "assistant_id": "asst_abc123",
      "run_id": "run_abc123",
      "metadata": {}
    }
  ]
}
```

## Reference
- Official Docs: https://platform.openai.com/docs/assistants
- API Reference: https://platform.openai.com/docs/api-reference/assistants



Assistants
Deprecated
The Assistants API is deprecated and will be removed in August 2026. The recommended replacement is the Responses API. Learn more.

Build assistants that can call models and use tools to perform tasks.

Create assistant
Deprecated
post

https://api.openai.com/v1/assistants
Create an assistant with a model and instructions.

Request body
model
string

Required
ID of the model to use. You can use the List models API to see all of your available models, or see our Model overview for descriptions of them.

description
string

Optional
The description of the assistant. The maximum length is 512 characters.

instructions
string

Optional
The system instructions that the assistant uses. The maximum length is 256,000 characters.

metadata
map

Optional
Set of 16 key-value pairs that can be attached to an object. This can be useful for storing additional information about the object in a structured format, and querying for objects via API or the dashboard.

Keys are strings with a maximum length of 64 characters. Values are strings with a maximum length of 512 characters.

name
string

Optional
The name of the assistant. The maximum length is 256 characters.

reasoning_effort
string

Optional
Defaults to medium
Constrains effort on reasoning for reasoning models. Currently supported values are none, minimal, low, medium, high, and xhigh. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.

gpt-5.1 defaults to none, which does not perform reasoning. The supported reasoning values for gpt-5.1 are none, low, medium, and high. Tool calls are supported for all reasoning values in gpt-5.1.
All models before gpt-5.1 default to medium reasoning effort, and do not support none.
The gpt-5-pro model defaults to (and only supports) high reasoning effort.
xhigh is supported for all models after gpt-5.1-codex-max.
response_format
"auto" or object

Optional
Specifies the format that the model must output. Compatible with GPT-4o, GPT-4 Turbo, and all GPT-3.5 Turbo models since gpt-3.5-turbo-1106.

Setting to { "type": "json_schema", "json_schema": {...} } enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the Structured Outputs guide.

Setting to { "type": "json_object" } enables JSON mode, which ensures the message the model generates is valid JSON.

Important: when using JSON mode, you must also instruct the model to produce JSON yourself via a system or user message. Without this, the model may generate an unending stream of whitespace until the generation reaches the token limit, resulting in a long-running and seemingly "stuck" request. Also note that the message content may be partially cut off if finish_reason="length", which indicates the generation exceeded max_tokens or the conversation exceeded the max context length.


Show possible types
temperature
number

Optional
Defaults to 1
What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.

tool_resources
object

Optional
A set of resources that are used by the assistant's tools. The resources are specific to the type of tool. For example, the code_interpreter tool requires a list of file IDs, while the file_search tool requires a list of vector store IDs.


Show properties
tools
array

Optional
Defaults to []
A list of tool enabled on the assistant. There can be a maximum of 128 tools per assistant. Tools can be of types code_interpreter, file_search, or function.


Hide possible types
Code interpreter tool
object

Show properties
FileSearch tool
object

Show properties
Function tool
object

Show properties
top_p
number

Optional
Defaults to 1
An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.

We generally recommend altering this or temperature but not both.

Returns
An assistant object.

Code Interpreter
Files
Example request
curl "https://api.openai.com/v1/assistants" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -d '{
    "instructions": "You are a personal math tutor. When asked a question, write and run Python code to answer the question.",
    "name": "Math Tutor",
    "tools": [{"type": "code_interpreter"}],
    "model": "gpt-4o"
  }'
Response
{
  "id": "asst_abc123",
  "object": "assistant",
  "created_at": 1698984975,
  "name": "Math Tutor",
  "description": null,
  "model": "gpt-4o",
  "instructions": "You are a personal math tutor. When asked a question, write and run Python code to answer the question.",
  "tools": [
    {
      "type": "code_interpreter"
    }
  ],
  "metadata": {},
  "top_p": 1.0,
  "temperature": 1.0,
  "response_format": "auto"
}
List assistants
Deprecated
get

https://api.openai.com/v1/assistants
Returns a list of assistants.

Query parameters
after
string

Optional
A cursor for use in pagination. after is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list.

before
string

Optional
A cursor for use in pagination. before is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list.

limit
integer

Optional
Defaults to 20
A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20.

order
string

Optional
Defaults to desc
Sort order by the created_at timestamp of the objects. asc for ascending order and desc for descending order.

Returns
A list of assistant objects.

Example request
curl "https://api.openai.com/v1/assistants?order=desc&limit=20" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"
Response
{
  "object": "list",
  "data": [
    {
      "id": "asst_abc123",
      "object": "assistant",
      "created_at": 1698982736,
      "name": "Coding Tutor",
      "description": null,
      "model": "gpt-4o",
      "instructions": "You are a helpful assistant designed to make me better at coding!",
      "tools": [],
      "tool_resources": {},
      "metadata": {},
      "top_p": 1.0,
      "temperature": 1.0,
      "response_format": "auto"
    },
    {
      "id": "asst_abc456",
      "object": "assistant",
      "created_at": 1698982718,
      "name": "My Assistant",
      "description": null,
      "model": "gpt-4o",
      "instructions": "You are a helpful assistant designed to make me better at coding!",
      "tools": [],
      "tool_resources": {},
      "metadata": {},
      "top_p": 1.0,
      "temperature": 1.0,
      "response_format": "auto"
    },
    {
      "id": "asst_abc789",
      "object": "assistant",
      "created_at": 1698982643,
      "name": null,
      "description": null,
      "model": "gpt-4o",
      "instructions": null,
      "tools": [],
      "tool_resources": {},
      "metadata": {},
      "top_p": 1.0,
      "temperature": 1.0,
      "response_format": "auto"
    }
  ],
  "first_id": "asst_abc123",
  "last_id": "asst_abc789",
  "has_more": false
}
Retrieve assistant
Deprecated
get

https://api.openai.com/v1/assistants/{assistant_id}
Retrieves an assistant.

Path parameters
assistant_id
string

Required
The ID of the assistant to retrieve.

Returns
The assistant object matching the specified ID.

Example request
curl https://api.openai.com/v1/assistants/asst_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"
Response
{
  "id": "asst_abc123",
  "object": "assistant",
  "created_at": 1699009709,
  "name": "HR Helper",
  "description": null,
  "model": "gpt-4o",
  "instructions": "You are an HR bot, and you have access to files to answer employee questions about company policies.",
  "tools": [
    {
      "type": "file_search"
    }
  ],
  "metadata": {},
  "top_p": 1.0,
  "temperature": 1.0,
  "response_format": "auto"
}
Modify assistant
Deprecated
post

https://api.openai.com/v1/assistants/{assistant_id}
Modifies an assistant.

Path parameters
assistant_id
string

Required
The ID of the assistant to modify.

Request body
description
string

Optional
The description of the assistant. The maximum length is 512 characters.

instructions
string

Optional
The system instructions that the assistant uses. The maximum length is 256,000 characters.

metadata
map

Optional
Set of 16 key-value pairs that can be attached to an object. This can be useful for storing additional information about the object in a structured format, and querying for objects via API or the dashboard.

Keys are strings with a maximum length of 64 characters. Values are strings with a maximum length of 512 characters.

model
string

Optional
ID of the model to use. You can use the List models API to see all of your available models, or see our Model overview for descriptions of them.

name
string

Optional
The name of the assistant. The maximum length is 256 characters.

reasoning_effort
string

Optional
Defaults to medium
Constrains effort on reasoning for reasoning models. Currently supported values are none, minimal, low, medium, high, and xhigh. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.

gpt-5.1 defaults to none, which does not perform reasoning. The supported reasoning values for gpt-5.1 are none, low, medium, and high. Tool calls are supported for all reasoning values in gpt-5.1.
All models before gpt-5.1 default to medium reasoning effort, and do not support none.
The gpt-5-pro model defaults to (and only supports) high reasoning effort.
xhigh is supported for all models after gpt-5.1-codex-max.
response_format
"auto" or object

Optional
Specifies the format that the model must output. Compatible with GPT-4o, GPT-4 Turbo, and all GPT-3.5 Turbo models since gpt-3.5-turbo-1106.

Setting to { "type": "json_schema", "json_schema": {...} } enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the Structured Outputs guide.

Setting to { "type": "json_object" } enables JSON mode, which ensures the message the model generates is valid JSON.

Important: when using JSON mode, you must also instruct the model to produce JSON yourself via a system or user message. Without this, the model may generate an unending stream of whitespace until the generation reaches the token limit, resulting in a long-running and seemingly "stuck" request. Also note that the message content may be partially cut off if finish_reason="length", which indicates the generation exceeded max_tokens or the conversation exceeded the max context length.


Show possible types
temperature
number

Optional
Defaults to 1
What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.

tool_resources
object

Optional
A set of resources that are used by the assistant's tools. The resources are specific to the type of tool. For example, the code_interpreter tool requires a list of file IDs, while the file_search tool requires a list of vector store IDs.


Show properties
tools
array

Optional
Defaults to []
A list of tool enabled on the assistant. There can be a maximum of 128 tools per assistant. Tools can be of types code_interpreter, file_search, or function.


Show possible types
top_p
number

Optional
Defaults to 1
An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.

We generally recommend altering this or temperature but not both.

Returns
The modified assistant object.

Example request
curl https://api.openai.com/v1/assistants/asst_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -d '{
      "instructions": "You are an HR bot, and you have access to files to answer employee questions about company policies. Always response with info from either of the files.",
      "tools": [{"type": "file_search"}],
      "model": "gpt-4o"
    }'
Response
{
  "id": "asst_123",
  "object": "assistant",
  "created_at": 1699009709,
  "name": "HR Helper",
  "description": null,
  "model": "gpt-4o",
  "instructions": "You are an HR bot, and you have access to files to answer employee questions about company policies. Always response with info from either of the files.",
  "tools": [
    {
      "type": "file_search"
    }
  ],
  "tool_resources": {
    "file_search": {
      "vector_store_ids": []
    }
  },
  "metadata": {},
  "top_p": 1.0,
  "temperature": 1.0,
  "response_format": "auto"
}
Delete assistant
Deprecated
delete

https://api.openai.com/v1/assistants/{assistant_id}
Delete an assistant.

Path parameters
assistant_id
string

Required
The ID of the assistant to delete.

Returns
Deletion status

Example request
curl https://api.openai.com/v1/assistants/asst_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -X DELETE
Response
{
  "id": "asst_abc123",
  "object": "assistant.deleted",
  "deleted": true
}
The assistant object
Deprecated
Represents an assistant that can call the model and use tools.

created_at
integer

The Unix timestamp (in seconds) for when the assistant was created.

description
string

The description of the assistant. The maximum length is 512 characters.

id
string

The identifier, which can be referenced in API endpoints.

instructions
string

The system instructions that the assistant uses. The maximum length is 256,000 characters.

metadata
map

Set of 16 key-value pairs that can be attached to an object. This can be useful for storing additional information about the object in a structured format, and querying for objects via API or the dashboard.

Keys are strings with a maximum length of 64 characters. Values are strings with a maximum length of 512 characters.

model
string

ID of the model to use. You can use the List models API to see all of your available models, or see our Model overview for descriptions of them.

name
string

The name of the assistant. The maximum length is 256 characters.

object
string

The object type, which is always assistant.

response_format
"auto" or object

Specifies the format that the model must output. Compatible with GPT-4o, GPT-4 Turbo, and all GPT-3.5 Turbo models since gpt-3.5-turbo-1106.

Setting to { "type": "json_schema", "json_schema": {...} } enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the Structured Outputs guide.

Setting to { "type": "json_object" } enables JSON mode, which ensures the message the model generates is valid JSON.

Important: when using JSON mode, you must also instruct the model to produce JSON yourself via a system or user message. Without this, the model may generate an unending stream of whitespace until the generation reaches the token limit, resulting in a long-running and seemingly "stuck" request. Also note that the message content may be partially cut off if finish_reason="length", which indicates the generation exceeded max_tokens or the conversation exceeded the max context length.


Show possible types
temperature
number

What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.

tool_resources
object

A set of resources that are used by the assistant's tools. The resources are specific to the type of tool. For example, the code_interpreter tool requires a list of file IDs, while the file_search tool requires a list of vector store IDs.


Show properties
tools
array

A list of tool enabled on the assistant. There can be a maximum of 128 tools per assistant. Tools can be of types code_interpreter, file_search, or function.


Show possible types
top_p
number

An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.

We generally recommend altering this or temperature but not both.
