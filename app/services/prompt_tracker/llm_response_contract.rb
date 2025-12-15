# frozen_string_literal: true

module PromptTracker
  # Contract for LLM responses returned from track_llm_call block.
  #
  # This service defines the explicit contract that developers must follow when
  # returning responses from the track_llm_call block. It provides clear validation
  # and normalization of responses.
  #
  # Developers can return either:
  # 1. A plain String (simplest - just the response text)
  # 2. A Hash with structured data (for token counts and metadata)
  #
  # Hash format:
  # {
  #   text: "The response text",           # Required
  #   tokens_prompt: 100,                  # Optional
  #   tokens_completion: 50,               # Optional
  #   tokens_total: 150,                   # Optional (auto-calculated if not provided)
  #   metadata: { ... }                    # Optional
  # }
  #
  # @example Return plain string (simplest)
  #   track_llm_call("greeting", ...) do |prompt|
  #     "Hello, world!"  # Just return the text
  #   end
  #
  # @example Return structured hash (with token counts)
  #   track_llm_call("greeting", ...) do |prompt|
  #     response = OpenAI::Client.new.chat(...)
  #     {
  #       text: response.dig("choices", 0, "message", "content"),
  #       tokens_prompt: response.dig("usage", "prompt_tokens"),
  #       tokens_completion: response.dig("usage", "completion_tokens"),
  #       metadata: { model: response["model"], id: response["id"] }
  #     }
  #   end
  #
  # @example Using LlmClientService (handles contract automatically)
  #   track_llm_call("greeting", ...) do |prompt|
  #     PromptTracker::LlmClientService.call(
  #       provider: "openai",
  #       model: "gpt-4",
  #       prompt: prompt
  #     )  # Returns hash in correct format
  #   end
  #
  class LlmResponseContract
    # Error raised when response doesn't match the contract
    class InvalidResponseError < StandardError; end

    # Normalize response to standard format.
    #
    # @param response [Hash, String] the response from the block
    # @return [Hash] normalized response with keys: :text, :tokens_prompt, :tokens_completion, :tokens_total, :metadata
    # @raise [InvalidResponseError] if response is invalid
    #
    # @example Normalize string
    #   LlmResponseContract.normalize("Hello!")
    #   # => { text: "Hello!", tokens_prompt: nil, tokens_completion: nil, tokens_total: nil, metadata: {} }
    #
    # @example Normalize hash
    #   LlmResponseContract.normalize({ text: "Hello!", tokens_prompt: 10 })
    #   # => { text: "Hello!", tokens_prompt: 10, tokens_completion: nil, tokens_total: nil, metadata: {} }
    #
    def self.normalize(response)
      case response
      when String
        normalize_string(response)
      when Hash
        normalize_hash(response)
      else
        raise InvalidResponseError,
              "Block must return String or Hash with :text key. Got: #{response.class}"
      end
    end

    # Normalize a string response
    #
    # @param response [String] the response text
    # @return [Hash] normalized response
    def self.normalize_string(response)
      {
        text: response,
        tokens_prompt: nil,
        tokens_completion: nil,
        tokens_total: nil,
        metadata: {}
      }
    end
    private_class_method :normalize_string

    # Normalize a hash response
    #
    # @param response [Hash] the response hash
    # @return [Hash] normalized response
    # @raise [InvalidResponseError] if hash doesn't contain :text key
    def self.normalize_hash(response)
      # Support both symbol and string keys
      text = response[:text] || response["text"]

      if text.nil?
        raise InvalidResponseError,
              "Hash response must include :text or 'text' key. Got keys: #{response.keys.inspect}"
      end

      tokens_prompt = response[:tokens_prompt] || response["tokens_prompt"]
      tokens_completion = response[:tokens_completion] || response["tokens_completion"]
      tokens_total = response[:tokens_total] || response["tokens_total"]
      metadata = response[:metadata] || response["metadata"] || {}

      # Auto-calculate tokens_total if not provided but components are
      if tokens_total.nil? && tokens_prompt && tokens_completion
        tokens_total = tokens_prompt + tokens_completion
      end

      {
        text: text,
        tokens_prompt: tokens_prompt,
        tokens_completion: tokens_completion,
        tokens_total: tokens_total,
        metadata: metadata
      }
    end
    private_class_method :normalize_hash
  end
end
