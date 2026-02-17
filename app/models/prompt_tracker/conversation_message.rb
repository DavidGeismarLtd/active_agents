# frozen_string_literal: true

module PromptTracker
  # Value object representing a single message in a conversation.
  #
  # This class ensures consistent message structure across all
  # SimulatedConversationRunner implementations (RubyLLM, OpenAI, Anthropic, etc.).
  #
  # @example Creating an assistant message
  #   message = ConversationMessage.new(
  #     role: "assistant",
  #     content: "Hello! How can I help?",
  #     turn: 1,
  #     usage: { prompt_tokens: 10, completion_tokens: 5 },
  #     tool_calls: [{ id: "call_1", function_name: "search" }]
  #   )
  #
  # @example Creating a user message
  #   message = ConversationMessage.new(
  #     role: "user",
  #     content: "What's the weather?",
  #     turn: 1
  #   )
  #
  class ConversationMessage
    attr_reader :role, :content, :turn, :usage, :tool_calls,
                :file_search_results, :web_search_results,
                :code_interpreter_results, :api_metadata

    # Initialize a new conversation message
    #
    # @param role [String] Message role ("user" or "assistant")
    # @param content [String] Message content
    # @param turn [Integer] Turn number in the conversation
    # @param usage [Hash] Token usage information (optional)
    # @param tool_calls [Array] Tool calls made in this message (optional)
    # @param file_search_results [Array] File search results (optional, OpenAI-specific)
    # @param web_search_results [Array] Web search results (optional)
    # @param code_interpreter_results [Array] Code interpreter results (optional, OpenAI-specific)
    # @param api_metadata [Hash] Provider-specific metadata (optional)
    def initialize(role:, content:, turn:, usage: {}, tool_calls: [],
                   file_search_results: [], web_search_results: [],
                   code_interpreter_results: [], api_metadata: {})
      @role = role
      @content = content
      @turn = turn
      @usage = usage || {}
      @tool_calls = tool_calls || []
      @file_search_results = file_search_results || []
      @web_search_results = web_search_results || []
      @code_interpreter_results = code_interpreter_results || []
      @api_metadata = api_metadata || {}
    end

    # Convert to hash format for serialization
    #
    # @return [Hash] Message as a hash with string keys
    def to_h
      {
        "role" => role,
        "content" => content,
        "turn" => turn,
        "usage" => usage,
        "tool_calls" => tool_calls,
        "file_search_results" => file_search_results,
        "web_search_results" => web_search_results,
        "code_interpreter_results" => code_interpreter_results,
        "api_metadata" => api_metadata
      }
    end

    # Check if this is an assistant message
    #
    # @return [Boolean]
    def assistant?
      role == "assistant"
    end

    # Check if this is a user message
    #
    # @return [Boolean]
    def user?
      role == "user"
    end

    # Check if this message includes tool calls
    #
    # @return [Boolean]
    def has_tool_calls?
      tool_calls.any?
    end

    # Check if this message has file search results
    #
    # @return [Boolean]
    def has_file_search_results?
      file_search_results.any?
    end

    # Check if this message has web search results
    #
    # @return [Boolean]
    def has_web_search_results?
      web_search_results.any?
    end

    # Check if this message has code interpreter results
    #
    # @return [Boolean]
    def has_code_interpreter_results?
      code_interpreter_results.any?
    end
  end
end
