# frozen_string_literal: true

module PromptTracker
  # Value object representing a normalized LLM response.
  #
  # This is a PURE VALUE OBJECT - it stores data, not transforms it.
  # All normalization happens in LlmResponseNormalizers before data reaches here.
  #
  # @example Create a normalized response
  #   response = NormalizedLlmResponse.new(
  #     text: "Hello!",
  #     usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
  #     model: "gpt-4o"
  #   )
  #   response.to_h  # => { text: "Hello!", usage: {...}, ... }
  #
  class NormalizedLlmResponse
    REQUIRED_KEYS = [ :text, :usage, :model ].freeze

    attr_reader :text, :usage, :model, :tool_calls, :file_search_results,
                :web_search_results, :code_interpreter_results, :api_metadata, :raw_response

    # Initialize a normalized response
    #
    # @param text [String] the response text content
    # @param usage [Hash] token usage { prompt_tokens:, completion_tokens:, total_tokens: }
    # @param model [String] the model name used
    # @param tool_calls [Array<Hash>] tool/function calls (default: [])
    # @param file_search_results [Array<Hash>] file search results (default: [])
    # @param web_search_results [Array<Hash>] web search results (default: [])
    # @param code_interpreter_results [Array<Hash>] code interpreter results (default: [])
    # @param api_metadata [Hash] API-specific metadata (default: {})
    # @param raw_response [Object] original API response for debugging
    def initialize(
      text:,
      usage:,
      model:,
      tool_calls: [],
      file_search_results: [],
      web_search_results: [],
      code_interpreter_results: [],
      api_metadata: {},
      raw_response: nil
    )
      @text = text || ""
      @usage = usage || { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      @model = model
      @tool_calls = tool_calls || []
      @file_search_results = file_search_results || []
      @web_search_results = web_search_results || []
      @code_interpreter_results = code_interpreter_results || []
      @api_metadata = (api_metadata || {}).deep_symbolize_keys
      @raw_response = raw_response
    end

    # Convert to hash representation
    #
    # @return [Hash] the normalized response as a hash with symbol keys
    def to_h
      {
        text: text,
        usage: usage,
        model: model,
        tool_calls: tool_calls,
        file_search_results: file_search_results,
        web_search_results: web_search_results,
        code_interpreter_results: code_interpreter_results,
        api_metadata: api_metadata,
        raw_response: raw_response
      }
    end

    # Allow hash-like access for backward compatibility during migration
    #
    # @param key [Symbol, String] the key to access
    # @return [Object] the value
    def [](key)
      to_h[key.to_sym]
    end

    # Check if a key exists
    #
    # @param key [Symbol, String] the key to check
    # @return [Boolean] true if key exists
    def key?(key)
      to_h.key?(key.to_sym)
    end

    # Dig into nested values (for compatibility with hash-like access)
    #
    # @param keys [Array<Symbol, String>] the keys to dig through
    # @return [Object] the nested value
    def dig(*keys)
      to_h.dig(*keys.map { |k| k.is_a?(String) ? k.to_sym : k })
    end

    # Convenience method to get thread_id from api_metadata (Assistants API)
    def thread_id
      api_metadata[:thread_id]
    end

    # Convenience method to get run_id from api_metadata (Assistants API)
    def run_id
      api_metadata[:run_id]
    end

    # Convenience method to get response_id from api_metadata (Responses API)
    def response_id
      api_metadata[:response_id]
    end

    # Convenience method to get annotations from api_metadata (Assistants API)
    def annotations
      api_metadata[:annotations] || []
    end

    # Convenience method to get run_steps from api_metadata (Assistants API)
    def run_steps
      api_metadata[:run_steps] || []
    end
  end

  # Alias for backward compatibility during migration
  NormalizedResponse = NormalizedLlmResponse
end
