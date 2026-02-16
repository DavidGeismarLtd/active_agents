# OpenAI Chat Completions API

The Chat Completions API is OpenAI's primary interface for conversational AI. It powers ChatGPT and enables developers to build chat-based applications with GPT models.

**Source**: Official OpenAI OpenAPI Specification (fetched 2026-01-27)

## Endpoint

```
POST https://api.openai.com/v1/chat/completions
```

## Headers

```
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY
```

## Request Parameters

### Required Parameters

**model** (string)
- Model ID used to generate the response
- Examples: `gpt-4o`, `gpt-4o-mini`, `o1`, `o3`, `gpt-4.1`
- See [Models documentation](https://platform.openai.com/docs/models) for all available models

**messages** (array, minimum 1 item)
- Array of message objects comprising the conversation
- Supports different modalities: text, images, and audio (depending on model)
- Each message has:
  - `role`: One of `system`, `user`, `assistant`, `developer`, `tool`, or `function`
  - `content`: The message content (string or array for multimodal)
  - `name` (optional): Name of the message author

### Optional Parameters

**temperature** (number, 0-2, default: 1, nullable)
- Controls randomness. Higher values (0.8) make output more random, lower values (0.2) more focused and deterministic
- Recommend altering this OR `top_p`, not both

**max_completion_tokens** (integer, nullable)
- Upper bound for tokens that can be generated for a completion
- Includes visible output tokens and reasoning tokens

**top_p** (number, 0-1, default: 1, nullable)
- Nucleus sampling: model considers tokens with top_p probability mass
- 0.1 means only tokens in top 10% probability mass are considered
- Recommend altering this OR `temperature`, not both

**stream** (boolean, default: false, nullable)
- If true, model response data streamed as server-sent events (SSE)
- See [Streaming section](https://platform.openai.com/docs/api-reference/chat/streaming)

**stop** (string, array, or object, nullable)
- Sequences where the API will stop generating tokens
- Can be up to 4 stop sequences

**presence_penalty** (number, -2.0 to 2.0, default: 0, nullable)
- Positive values penalize new tokens based on whether they appear in the text so far
- Increases likelihood to talk about new topics

**frequency_penalty** (number, -2.0 to 2.0, default: 0, nullable)
- Positive values penalize new tokens based on their existing frequency
- Decreases likelihood to repeat the same line verbatim

**logit_bias** (object/map, default: null, nullable)
- Modify likelihood of specified tokens appearing
- Maps token IDs (integers) to bias values from -100 to 100
- Values between -1 and 1 decrease/increase likelihood; -100 or 100 ban/exclusively select tokens

**logprobs** (boolean, default: false, nullable)
- Whether to return log probabilities of output tokens
- Returns log probabilities of each output token in the `content` of `message`

**top_logprobs** (integer, 0-20, nullable)
- Number of most likely tokens to return at each position with associated log probability
- Requires `logprobs: true`

**response_format** (object)
- Specify output format
- `{ "type": "text" }`: Regular text (default)
- `{ "type": "json_object" }`: JSON mode (older, ensures valid JSON)
- `{ "type": "json_schema", "json_schema": {...} }`: Structured Outputs (preferred, ensures model matches your JSON schema)

**modalities** (array)
- Output modalities for the response
- Can include `text` and/or `audio`

**audio** (object, nullable)
- Parameters for audio output
- Required when audio output requested with `modalities: ["audio"]`
- Properties:
  - `voice`: Voice to use (`alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `nova`, `onyx`, `sage`, `shimmer`, `marin`, `cedar`)
  - `format`: Output audio format (`wav`, `aac`, `mp3`, `flac`, `opus`, `pcm16`)

**store** (boolean, default: false, nullable)
- Whether to store output for model distillation or evals products
- Supports text and image inputs (images over 8MB dropped)

**metadata** (object, nullable)
- Set of 16 key-value pairs for storing additional information
- Keys: max 64 characters, Values: max 512 characters

**reasoning_effort** (string)
- Amount of reasoning effort for reasoning models
- Options: `low`, `medium`, `high`

**verbosity** (string)
- Controls verbosity of reasoning model outputs

**web_search_options** (object)
- Options for web search tool
- Properties:
  - `user_location`: Approximate location for search
  - `search_context_size`: Size of search context

**user** (string, deprecated)
- Being replaced by `safety_identifier` and `prompt_cache_key`
- Use `prompt_cache_key` for caching optimizations

**safety_identifier** (string)
- Stable identifier to help detect policy violations
- Should uniquely identify each user (recommend hashing username/email)

**prompt_cache_key** (string)
- Used by OpenAI to cache responses for similar requests
- Replaces the `user` field for caching optimization

**service_tier** (string)
- Service tier to use (`auto` or `default`)

**prompt_cache_retention** (string, nullable)
- Retention policy for prompt cache
- `in-memory`: Standard caching
- `24h`: Extended prompt caching (keeps cached prefixes active up to 24 hours)

## Response Format

```json
{
  "id": "chatcmpl-B9MBs8CjcvOU2jLn4n570S5qMJKcT",
  "object": "chat.completion",
  "created": 1741569952,
  "model": "gpt-4.1-2025-04-14",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I assist you today?",
      "refusal": null,
      "annotations": []
    },
    "logprobs": null,
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 19,
    "completion_tokens": 10,
    "total_tokens": 29,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default"
}
```

### Response Fields

- **id**: Unique identifier for the chat completion
- **object**: Object type, always `chat.completion`
- **created**: Unix timestamp of when the completion was created
- **model**: The model used for completion
- **service_tier**: Service tier used for the request
- **choices**: Array of completion choices
  - **index**: Choice index
  - **message**: The generated message
    - **role**: Always `assistant`
    - **content**: The content of the message
    - **refusal**: Refusal message if model refused to respond
    - **annotations**: Array of annotations
    - **tool_calls** (optional): Tool calls generated by the model
  - **logprobs**: Log probability information (if requested)
  - **finish_reason**: Why the model stopped
    - `stop`: Natural stop point or provided stop sequence
    - `length`: Max tokens reached
    - `tool_calls`: Model called a tool
    - `content_filter`: Content filtered by moderation
- **usage**: Token usage statistics
  - **prompt_tokens**: Tokens in the prompt
  - **completion_tokens**: Tokens in the completion
  - **total_tokens**: Total tokens used
  - **prompt_tokens_details**: Breakdown of prompt tokens (cached, audio)
  - **completion_tokens_details**: Breakdown of completion tokens (reasoning, audio, prediction)

## Streaming

Set `stream: true` to receive partial message deltas via Server-Sent Events (SSE).

### Streaming Response Format

Each chunk:
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion.chunk",
  "created": 1694268190,
  "model": "gpt-4o",
  "choices": [{
    "index": 0,
    "delta": {
      "role": "assistant",
      "content": "Hello"
    },
    "logprobs": null,
    "finish_reason": null
  }]
}
```

The last chunk has `finish_reason` set and `delta` is empty or contains final fields.

## Tool/Function Calling

### Request with Tools

```json
{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": "What's the weather in Boston?"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get the current weather in a location",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {"type": "string", "description": "City and state, e.g. San Francisco, CA"},
          "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
        },
        "required": ["location"]
      }
    }
  }]
}
```

### Response with Tool Call

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\": \"Boston, MA\", \"unit\": \"fahrenheit\"}"
        }
      }]
    },
    "finish_reason": "tool_calls"
  }]
}
```

### Submitting Tool Results

After executing the function, submit the result back:

```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "user", "content": "What's the weather in Boston?"},
    {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {"name": "get_weather", "arguments": "{\"location\": \"Boston, MA\"}"}
      }]
    },
    {
      "role": "tool",
      "tool_call_id": "call_abc123",
      "content": "{\"temperature\": 72, \"condition\": \"sunny\"}"
    }
  ]
}
```

## Vision (Image Inputs)

Include images in messages using the multimodal content format:

```json
{
  "model": "gpt-4o",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "What's in this image?"},
      {
        "type": "image_url",
        "image_url": {
          "url": "https://example.com/image.jpg",
          "detail": "high"
        }
      }
    ]
  }]
}
```

The `detail` parameter can be `low`, `high`, or `auto`.

## JSON Mode and Structured Outputs

### JSON Mode (Legacy)

```json
{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": "Generate a person's profile"}],
  "response_format": {"type": "json_object"}
}
```

### Structured Outputs (Recommended)

```json
{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": "Generate a person's profile"}],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "person_profile",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "number"},
          "email": {"type": "string"}
        },
        "required": ["name", "age", "email"],
        "additionalProperties": false
      }
    }
  }
}
```

## Reference

- **Official Documentation**: https://platform.openai.com/docs/api-reference/chat
- **Models List**: https://platform.openai.com/docs/models
- **Streaming Guide**: https://platform.openai.com/docs/api-reference/chat/streaming
- **Function Calling**: https://platform.openai.com/docs/guides/function-calling
- **Vision Guide**: https://platform.openai.com/docs/guides/vision
- **Structured Outputs**: https://platform.openai.com/docs/guides/structured-outputs


Docs
API reference
Chat Completions
The Chat Completions API endpoint will generate a model response from a list of messages comprising a conversation.

Related guides:

Quickstart
Text inputs and outputs
Image inputs
Audio inputs and outputs
Structured Outputs
Function calling
Conversation state
Starting a new project? We recommend trying Responses to take advantage of the latest OpenAI platform features. Compare Chat Completions with Responses.

Create chat completion
post

https://api.openai.com/v1/chat/completions
Starting a new project? We recommend trying Responses to take advantage of the latest OpenAI platform features. Compare Chat Completions with Responses.

Creates a model response for the given chat conversation. Learn more in the text generation, vision, and audio guides.

Parameter support can differ depending on the model used to generate the response, particularly for newer reasoning models. Parameters that are only supported for reasoning models are noted below. For the current state of unsupported parameters in reasoning models, refer to the reasoning guide.

Request body
messages
array

Required
A list of messages comprising the conversation so far. Depending on the model you use, different message types (modalities) are supported, like text, images, and audio.


Show possible types
model
string

Required
Model ID used to generate the response, like gpt-4o or o3. OpenAI offers a wide range of models with different capabilities, performance characteristics, and price points. Refer to the model guide to browse and compare available models.

audio
object or null

Optional
Parameters for audio output. Required when audio output is requested with modalities: ["audio"]. Learn more.


Show properties
frequency_penalty
number or null

Optional
Defaults to 0
Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.

function_call
Deprecated
string or object

Optional
Deprecated in favor of tool_choice.

Controls which (if any) function is called by the model.

none means the model will not call a function and instead generates a message.

auto means the model can pick between generating a message or calling a function.

Specifying a particular function via {"name": "my_function"} forces the model to call that function.

none is the default when no functions are present. auto is the default if functions are present.


Show possible types
functions
Deprecated
array

Optional
Deprecated in favor of tools.

A list of functions the model may generate JSON inputs for.


Show properties
logit_bias
map

Optional
Defaults to null
Modify the likelihood of specified tokens appearing in the completion.

Accepts a JSON object that maps tokens (specified by their token ID in the tokenizer) to an associated bias value from -100 to 100. Mathematically, the bias is added to the logits generated by the model prior to sampling. The exact effect will vary per model, but values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.

logprobs
boolean or null

Optional
Defaults to false
Whether to return log probabilities of the output tokens or not. If true, returns the log probabilities of each output token returned in the content of message.

max_completion_tokens
integer or null

Optional
An upper bound for the number of tokens that can be generated for a completion, including visible output tokens and reasoning tokens.

max_tokens
Deprecated
integer or null

Optional
The maximum number of tokens that can be generated in the chat completion. This value can be used to control costs for text generated via API.

This value is now deprecated in favor of max_completion_tokens, and is not compatible with o-series models.

metadata
map

Optional
Set of 16 key-value pairs that can be attached to an object. This can be useful for storing additional information about the object in a structured format, and querying for objects via API or the dashboard.

Keys are strings with a maximum length of 64 characters. Values are strings with a maximum length of 512 characters.

modalities
array

Optional
Output types that you would like the model to generate. Most models are capable of generating text, which is the default:

["text"]

The gpt-4o-audio-preview model can also be used to generate audio. To request that this model generate both text and audio responses, you can use:

["text", "audio"]

n
integer or null

Optional
Defaults to 1
How many chat completion choices to generate for each input message. Note that you will be charged based on the number of generated tokens across all of the choices. Keep n as 1 to minimize costs.

parallel_tool_calls
boolean

Optional
Defaults to true
Whether to enable parallel function calling during tool use.

prediction
object

Optional
Configuration for a Predicted Output, which can greatly improve response times when large parts of the model response are known ahead of time. This is most common when you are regenerating a file with only minor changes to most of the content.


Show possible types
presence_penalty
number or null

Optional
Defaults to 0
Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.

prompt_cache_key
string

Optional
Used by OpenAI to cache responses for similar requests to optimize your cache hit rates. Replaces the user field. Learn more.

prompt_cache_retention
string

Optional
The retention policy for the prompt cache. Set to 24h to enable extended prompt caching, which keeps cached prefixes active for longer, up to a maximum of 24 hours. Learn more.

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
object

Optional
An object specifying the format that the model must output.

Setting to { "type": "json_schema", "json_schema": {...} } enables Structured Outputs which ensures the model will match your supplied JSON schema. Learn more in the Structured Outputs guide.

Setting to { "type": "json_object" } enables the older JSON mode, which ensures the message the model generates is valid JSON. Using json_schema is preferred for models that support it.


Show possible types
safety_identifier
string

Optional
A stable identifier used to help detect users of your application that may be violating OpenAI's usage policies. The IDs should be a string that uniquely identifies each user. We recommend hashing their username or email address, in order to avoid sending us any identifying information. Learn more.

seed
Deprecated
integer or null

Optional
This feature is in Beta. If specified, our system will make a best effort to sample deterministically, such that repeated requests with the same seed and parameters should return the same result. Determinism is not guaranteed, and you should refer to the system_fingerprint response parameter to monitor changes in the backend.

service_tier
string

Optional
Defaults to auto
Specifies the processing type used for serving the request.

If set to 'auto', then the request will be processed with the service tier configured in the Project settings. Unless otherwise configured, the Project will use 'default'.
If set to 'default', then the request will be processed with the standard pricing and performance for the selected model.
If set to 'flex' or 'priority', then the request will be processed with the corresponding service tier.
When not set, the default behavior is 'auto'.
When the service_tier parameter is set, the response body will include the service_tier value based on the processing mode actually used to serve the request. This response value may be different from the value set in the parameter.

stop
string / array / null

Optional
Defaults to null
Not supported with latest reasoning models o3 and o4-mini.

Up to 4 sequences where the API will stop generating further tokens. The returned text will not contain the stop sequence.

store
boolean or null

Optional
Defaults to false
Whether or not to store the output of this chat completion request for use in our model distillation or evals products.

Supports text and image inputs. Note: image inputs over 8MB will be dropped.

stream
boolean or null

Optional
Defaults to false
If set to true, the model response data will be streamed to the client as it is generated using server-sent events. See the Streaming section below for more information, along with the streaming responses guide for more information on how to handle the streaming events.

stream_options
object

Optional
Defaults to null
Options for streaming response. Only set this when you set stream: true.


Show properties
temperature
number

Optional
Defaults to 1
What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.

tool_choice
string or object

Optional
Controls which (if any) tool is called by the model. none means the model will not call any tool and instead generates a message. auto means the model can pick between generating a message or calling one or more tools. required means the model must call one or more tools. Specifying a particular tool via {"type": "function", "function": {"name": "my_function"}} forces the model to call that tool.

none is the default when no tools are present. auto is the default if tools are present.


Hide possible types
Tool choice mode
string
none means the model will not call any tool and instead generates a message. auto means the model can pick between generating a message or calling one or more tools. required means the model must call one or more tools.

Allowed tools
object
Constrains the tools available to the model to a pre-defined set.


Show properties
Function tool choice
object
Specifies a tool the model should use. Use to force the model to call a specific function.


Show properties
Custom tool choice
object
Specifies a tool the model should use. Use to force the model to call a specific custom tool.


Show properties
tools
array

Optional
A list of tools the model may call. You can provide either custom tools or function tools.


Show possible types
top_logprobs
integer

Optional
An integer between 0 and 20 specifying the number of most likely tokens to return at each token position, each with an associated log probability.

top_p
number

Optional
Defaults to 1
An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.

We generally recommend altering this or temperature but not both.

user
Deprecated
string

Optional
This field is being replaced by safety_identifier and prompt_cache_key. Use prompt_cache_key instead to maintain caching optimizations. A stable identifier for your end-users. Used to boost cache hit rates by better bucketing similar requests and to help OpenAI detect and prevent abuse. Learn more.

verbosity
string

Optional
Defaults to medium
Constrains the verbosity of the model's response. Lower values will result in more concise responses, while higher values will result in more verbose responses. Currently supported values are low, medium, and high.

web_search_options
object

Optional
This tool searches the web for relevant results to use in a response. Learn more about the web search tool.


Show properties
Returns
Returns a chat completion object, or a streamed sequence of chat completion chunk objects if the request is streamed.

Default
Image input
Streaming
Functions
Logprobs
Example request
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-5.2",
    "messages": [
      {
        "role": "developer",
        "content": "You are a helpful assistant."
      },
      {
        "role": "user",
        "content": "Hello!"
      }
    ]
  }'
Response
{
  "id": "chatcmpl-B9MBs8CjcvOU2jLn4n570S5qMJKcT",
  "object": "chat.completion",
  "created": 1741569952,
  "model": "gpt-4.1-2025-04-14",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I assist you today?",
        "refusal": null,
        "annotations": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 19,
    "completion_tokens": 10,
    "total_tokens": 29,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default"
}
Get chat completion
get

https://api.openai.com/v1/chat/completions/{completion_id}
Get a stored chat completion. Only Chat Completions that have been created with the store parameter set to true will be returned.

Path parameters
completion_id
string

Required
The ID of the chat completion to retrieve.

Returns
The ChatCompletion object matching the specified ID.

Example request
curl https://api.openai.com/v1/chat/completions/chatcmpl-abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"
Response
{
  "object": "chat.completion",
  "id": "chatcmpl-abc123",
  "model": "gpt-4o-2024-08-06",
  "created": 1738960610,
  "request_id": "req_ded8ab984ec4bf840f37566c1011c417",
  "tool_choice": null,
  "usage": {
    "total_tokens": 31,
    "completion_tokens": 18,
    "prompt_tokens": 13
  },
  "seed": 4944116822809979520,
  "top_p": 1.0,
  "temperature": 1.0,
  "presence_penalty": 0.0,
  "frequency_penalty": 0.0,
  "system_fingerprint": "fp_50cad350e4",
  "input_user": null,
  "service_tier": "default",
  "tools": null,
  "metadata": {},
  "choices": [
    {
      "index": 0,
      "message": {
        "content": "Mind of circuits hum,  \nLearning patterns in silence—  \nFuture's quiet spark.",
        "role": "assistant",
        "tool_calls": null,
        "function_call": null
      },
      "finish_reason": "stop",
      "logprobs": null
    }
  ],
  "response_format": null
}
Get chat messages
get

https://api.openai.com/v1/chat/completions/{completion_id}/messages
Get the messages in a stored chat completion. Only Chat Completions that have been created with the store parameter set to true will be returned.

Path parameters
completion_id
string

Required
The ID of the chat completion to retrieve messages from.

Query parameters
after
string

Optional
Identifier for the last message from the previous pagination request.

limit
integer

Optional
Defaults to 20
Number of messages to retrieve.

order
string

Optional
Defaults to asc
Sort order for messages by timestamp. Use asc for ascending order or desc for descending order. Defaults to asc.

Returns
A list of messages for the specified chat completion.

Example request
curl https://api.openai.com/v1/chat/completions/chat_abc123/messages \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"
Response
{
  "object": "list",
  "data": [
    {
      "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
      "role": "user",
      "content": "write a haiku about ai",
      "name": null,
      "content_parts": null
    }
  ],
  "first_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
  "last_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
  "has_more": false
}
List Chat Completions
get

https://api.openai.com/v1/chat/completions
List stored Chat Completions. Only Chat Completions that have been stored with the store parameter set to true will be returned.

Query parameters
after
string

Optional
Identifier for the last chat completion from the previous pagination request.

limit
integer

Optional
Defaults to 20
Number of Chat Completions to retrieve.

metadata
object or null

Optional
A list of metadata keys to filter the Chat Completions by. Example:

metadata[key1]=value1&metadata[key2]=value2

model
string

Optional
The model used to generate the Chat Completions.

order
string

Optional
Defaults to asc
Sort order for Chat Completions by timestamp. Use asc for ascending order or desc for descending order. Defaults to asc.

Returns
A list of Chat Completions matching the specified filters.

Example request
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"
Response
{
  "object": "list",
  "data": [
    {
      "object": "chat.completion",
      "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
      "model": "gpt-4.1-2025-04-14",
      "created": 1738960610,
      "request_id": "req_ded8ab984ec4bf840f37566c1011c417",
      "tool_choice": null,
      "usage": {
        "total_tokens": 31,
        "completion_tokens": 18,
        "prompt_tokens": 13
      },
      "seed": 4944116822809979520,
      "top_p": 1.0,
      "temperature": 1.0,
      "presence_penalty": 0.0,
      "frequency_penalty": 0.0,
      "system_fingerprint": "fp_50cad350e4",
      "input_user": null,
      "service_tier": "default",
      "tools": null,
      "metadata": {},
      "choices": [
        {
          "index": 0,
          "message": {
            "content": "Mind of circuits hum,  \nLearning patterns in silence—  \nFuture's quiet spark.",
            "role": "assistant",
            "tool_calls": null,
            "function_call": null
          },
          "finish_reason": "stop",
          "logprobs": null
        }
      ],
      "response_format": null
    }
  ],
  "first_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "last_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "has_more": false
}
Update chat completion
post

https://api.openai.com/v1/chat/completions/{completion_id}
Modify a stored chat completion. Only Chat Completions that have been created with the store parameter set to true can be modified. Currently, the only supported modification is to update the metadata field.

Path parameters
completion_id
string

Required
The ID of the chat completion to update.

Request body
metadata
map

Required
Set of 16 key-value pairs that can be attached to an object. This can be useful for storing additional information about the object in a structured format, and querying for objects via API or the dashboard.

Keys are strings with a maximum length of 64 characters. Values are strings with a maximum length of 512 characters.

Returns
The ChatCompletion object matching the specified ID.

Example request
curl -X POST https://api.openai.com/v1/chat/completions/chat_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"foo": "bar"}}'
Response
{
  "object": "chat.completion",
  "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "model": "gpt-4o-2024-08-06",
  "created": 1738960610,
  "request_id": "req_ded8ab984ec4bf840f37566c1011c417",
  "tool_choice": null,
  "usage": {
    "total_tokens": 31,
    "completion_tokens": 18,
    "prompt_tokens": 13
  },
  "seed": 4944116822809979520,
  "top_p": 1.0,
  "temperature": 1.0,
  "presence_penalty": 0.0,
  "frequency_penalty": 0.0,
  "system_fingerprint": "fp_50cad350e4",
  "input_user": null,
  "service_tier": "default",
  "tools": null,
  "metadata": {
    "foo": "bar"
  },
  "choices": [
    {
      "index": 0,
      "message": {
        "content": "Mind of circuits hum,  \nLearning patterns in silence—  \nFuture's quiet spark.",
        "role": "assistant",
        "tool_calls": null,
        "function_call": null
      },
      "finish_reason": "stop",
      "logprobs": null
    }
  ],
  "response_format": null
}
Delete chat completion
delete

https://api.openai.com/v1/chat/completions/{completion_id}
Delete a stored chat completion. Only Chat Completions that have been created with the store parameter set to true can be deleted.

Path parameters
completion_id
string

Required
The ID of the chat completion to delete.

Returns
A deletion confirmation object.

Example request
curl -X DELETE https://api.openai.com/v1/chat/completions/chat_abc123 \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"
Response
{
  "object": "chat.completion.deleted",
  "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "deleted": true
}
The chat completion object
Represents a chat completion response returned by model, based on the provided input.

choices
array

A list of chat completion choices. Can be more than one if n is greater than 1.


Show properties
created
integer

The Unix timestamp (in seconds) of when the chat completion was created.

id
string

A unique identifier for the chat completion.

model
string

The model used for the chat completion.

object
string

The object type, which is always chat.completion.

service_tier
string

Specifies the processing type used for serving the request.

If set to 'auto', then the request will be processed with the service tier configured in the Project settings. Unless otherwise configured, the Project will use 'default'.
If set to 'default', then the request will be processed with the standard pricing and performance for the selected model.
If set to 'flex' or 'priority', then the request will be processed with the corresponding service tier.
When not set, the default behavior is 'auto'.
When the service_tier parameter is set, the response body will include the service_tier value based on the processing mode actually used to serve the request. This response value may be different from the value set in the parameter.

system_fingerprint
Deprecated
string

This fingerprint represents the backend configuration that the model runs with.

Can be used in conjunction with the seed request parameter to understand when backend changes have been made that might impact determinism.

usage
object

Usage statistics for the completion request.


Show properties
OBJECT The chat completion object
{
  "id": "chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG",
  "object": "chat.completion",
  "created": 1741570283,
  "model": "gpt-4o-2024-08-06",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The image shows a wooden boardwalk path running through a lush green field or meadow. The sky is bright blue with some scattered clouds, giving the scene a serene and peaceful atmosphere. Trees and shrubs are visible in the background.",
        "refusal": null,
        "annotations": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 1117,
    "completion_tokens": 46,
    "total_tokens": 1163,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default",
  "system_fingerprint": "fp_fc9f1d7035"
}
The chat completion list object
An object representing a list of Chat Completions.

data
array

An array of chat completion objects.


Show properties
first_id
string

The identifier of the first chat completion in the data array.

has_more
boolean

Indicates whether there are more Chat Completions available.

last_id
string

The identifier of the last chat completion in the data array.

object
string

The type of this object. It is always set to "list".

OBJECT The chat completion list object
{
  "object": "list",
  "data": [
    {
      "object": "chat.completion",
      "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
      "model": "gpt-4o-2024-08-06",
      "created": 1738960610,
      "request_id": "req_ded8ab984ec4bf840f37566c1011c417",
      "tool_choice": null,
      "usage": {
        "total_tokens": 31,
        "completion_tokens": 18,
        "prompt_tokens": 13
      },
      "seed": 4944116822809979520,
      "top_p": 1.0,
      "temperature": 1.0,
      "presence_penalty": 0.0,
      "frequency_penalty": 0.0,
      "system_fingerprint": "fp_50cad350e4",
      "input_user": null,
      "service_tier": "default",
      "tools": null,
      "metadata": {},
      "choices": [
        {
          "index": 0,
          "message": {
            "content": "Mind of circuits hum,  \nLearning patterns in silence—  \nFuture's quiet spark.",
            "role": "assistant",
            "tool_calls": null,
            "function_call": null
          },
          "finish_reason": "stop",
          "logprobs": null
        }
      ],
      "response_format": null
    }
  ],
  "first_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "last_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2",
  "has_more": false
}
The chat completion message list object
An object representing a list of chat completion messages.

data
array

An array of chat completion message objects.


Show properties
first_id
string

The identifier of the first chat message in the data array.

has_more
boolean

Indicates whether there are more chat messages available.

last_id
string

The identifier of the last chat message in the data array.

object
string

The type of this object. It is always set to "list".

OBJECT The chat completion message list object
{
  "object": "list",
  "data": [
    {
      "id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
      "role": "user",
      "content": "write a haiku about ai",
      "name": null,
      "content_parts": null
    }
  ],
  "first_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
  "last_id": "chatcmpl-AyPNinnUqUDYo9SAdA52NobMflmj2-0",
  "has_more": false
}
Previous
Server events
Next
Streaming

Docs Assistant
