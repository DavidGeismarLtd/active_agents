---
type: "always_apply"
---

- create small testable classes
- Create tests for all classes using rspec
- Avoid Defensive programming (avoid rescuing StandardError in particular)
- User prefers to avoid defensive programming patterns when accessing hash keys with known formats. exemple Dont do this :
# Defensive pattern with fallback to string keys
provider = model_config[:provider] || model_config["provider"] || "openai"
api = model_config[:api] || model_config["api"]
tool_config = model_config[:tool_config] || {}
✅ Do this instead:
# Only symbol keys
model = model_config[:model]
temperature = model_config[:temperature]
- User prefers to remove backward compatibility code for legacy data formats instead of maintaining it.
❌ Don't do this:
When you need to reference LLM provider API documentation (OpenAI, Anthropic, Google, etc.):

1. **First, check local documentation**: Look in `docs/llm_providers/` directory for comprehensive API documentation that is stored locally for quick reference. This includes:
   - OpenAI Chat Completions API (`docs/llm_providers/openai/chat_completions.md`)
   - OpenAI Assistants API (`docs/llm_providers/openai/assistants_api.md`)
   - OpenAI Responses API (`docs/llm_providers/openai/responses_api.md`)
   - Anthropic Messages API (`docs/llm_providers/anthropic/messages_api.md`)
   - Anthropic Tool Use (`docs/llm_providers/anthropic/tool_use.md`)
   - And other provider-specific documentation

2. **If local docs are insufficient**: Use the `web-search` or `web-fetch` tools to find up-to-date official documentation from the provider's website.

3. **If you still cannot find relevant information**:
   - **DO NOT invent or hallucinate API parameters, endpoints, or behavior**
   - Explicitly tell the user: "I couldn't find documentation for [specific feature/API]. Could you please search for the official documentation and share it with me, or point me to the relevant docs?"
   - Suggest specific search terms or official documentation URLs they should check

4. **Never assume or guess**: If you're uncertain about API details, request formats, parameters, or behavior, always acknowledge the uncertainty and ask for clarification rather than providing potentially incorrect information.

This is especially important when working with LLM APIs where incorrect parameter usage can lead to failed API calls, wasted tokens, or unexpected behavior.
