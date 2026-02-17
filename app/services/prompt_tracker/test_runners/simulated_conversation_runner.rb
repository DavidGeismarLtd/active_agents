# frozen_string_literal: true

module PromptTracker
  module TestRunners
    # Base class for simulated conversation runners.
    #
    # This class provides the foundation for executing conversational tests
    # across different LLM APIs. It handles:
    # - API execution
    # - Multi-turn conversation orchestration
    # - Interlocutor simulation for conversational tests
    # - Response aggregation and token calculation
    #
    # Each runner is responsible for a specific API type (Chat Completion,
    # Response API, Assistants API, etc.) and provides a consistent output format.
    #
    # Subclasses must implement:
    # - #execute(params) - Execute the test with given parameters
    #
    # @example Create a new runner
    #   class ChatCompletionRunner < SimulatedConversationRunner
    #     def execute(params)
    #       # API-specific execution logic
    #       { messages: [...], ... }
    #     end
    #   end
    #
    class SimulatedConversationRunner
      attr_reader :model_config, :use_real_llm, :testable

      # Initialize the handler
      #
      # @param model_config [Hash] model configuration from prompt version
      # @param use_real_llm [Boolean] whether to use real LLM API or mock
      # @param testable [Object] the testable object (PromptVersion)
      def initialize(model_config:, use_real_llm: false, testable: nil)
        @model_config = model_config.with_indifferent_access
        @use_real_llm = use_real_llm
        @testable = testable
      end

      # Execute the test with given parameters
      #
      # @param params [Hash] execution parameters including:
      #   - :system_prompt [String] the system prompt
      #   - :max_turns [Integer] maximum conversation turns (1 for single-turn, >1 for multi-turn)
      #   - :interlocutor_prompt [String, nil] prompt for user simulation (required for multi-turn)
      #   - :first_user_message [String, nil] initial user message
      # @return [Hash] output_data with standardized format
      def execute(params)
        raise NotImplementedError, "Subclasses must implement #execute"
      end

      private

      # Get the model name from config
      #
      # @return [String] the model name
      def model
        model_config[:model] || "gpt-4o"
      end

      # Get the temperature from config
      #
      # @return [Float] the temperature
      def temperature
        model_config[:temperature] || 0.7
      end

      # Get the tools from config
      #
      # @return [Array] array of tools
      def tools
        model_config[:tools] || []
      end

      # Get the tool_config from config
      #
      # @return [Hash] tool configuration
      def tool_config
        model_config[:tool_config] || {}
      end

      # Get the provider from config
      #
      # @return [String] the provider name
      def provider
        model_config[:provider] || "openai"
      end

      # Get the API type from config
      #
      # @return [String, nil] the API type (e.g., "chat_completions", "responses")
      def api
        model_config[:api]
      end

      # Build standard output data structure
      #
      # @param messages [Array<Hash>] array of message hashes
      # @param params [Hash] original execution params
      # @param extra [Hash] additional fields to include
      # @return [Hash] standardized output_data
      def build_output_data(messages:, params:, **extra)
        {
          "rendered_system_prompt" => params[:system_prompt],
          "rendered_user_prompt" => params[:first_user_message],
          "rendered_prompt" => build_rendered_prompt_display(params),
          "model" => model,
          "provider" => provider,
          "messages" => messages,
          "total_turns" => calculate_total_turns(messages),
          "status" => "completed",
          "max_turns" => params[:max_turns],
          "interlocutor_prompt" => params[:interlocutor_prompt]
        }.merge(extra.stringify_keys)
      end

      # Build the rendered_prompt display string combining system and user prompts
      #
      # @param params [Hash] execution params
      # @return [String] formatted prompt display
      def build_rendered_prompt_display(params)
        parts = []
        if params[:system_prompt].present?
          parts << "[System]\n#{params[:system_prompt]}"
        end
        if params[:first_user_message].present?
          parts << "[User]\n#{params[:first_user_message]}"
        end
        parts.join("\n\n")
      end

      # Calculate total conversation turns from messages
      #
      # @param messages [Array<Hash>] array of messages
      # @return [Integer] number of turns (user-assistant pairs)
      def calculate_total_turns(messages)
        messages.count { |m| m["role"] == "assistant" }
      end

      # Generate a mock response for testing
      #
      # @param turn [Integer] the turn number
      # @return [NormalizedLlmResponse] mock LLM response
      def mock_llm_response(turn: 1)
        PromptTracker::NormalizedLlmResponse.new(
          text: "Mock LLM response for testing (turn #{turn})",
          usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
          model: model,
          tool_calls: [],
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: {},
          raw_response: {}
        )
      end
    end
  end
end
