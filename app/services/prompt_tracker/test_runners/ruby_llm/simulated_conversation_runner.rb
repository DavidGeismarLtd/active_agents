# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module RubyLlm
      # Unified conversation runner for all RubyLLM-compatible providers.
      #
      # This runner uses RubyLLM's native conversation handling, which:
      # - Maintains conversation history internally in RubyLLM::Chat
      # - Handles tool execution automatically via registered RubyLLM::Tool classes
      # - Works with any RubyLLM-supported provider (OpenAI, Anthropic, Google, etc.)
      #
      # @example Single-turn execution
      #   runner = SimulatedConversationRunner.new(model_config: config, use_real_llm: true)
      #   output_data = runner.execute(
      #     system_prompt: "You are helpful.",
      #     max_turns: 1,
      #     first_user_message: "Hello"
      #   )
      #
      # @example Multi-turn with interlocutor
      #   runner = SimulatedConversationRunner.new(model_config: config, use_real_llm: true)
      #   output_data = runner.execute(
      #     system_prompt: "You are a doctor.",
      #     max_turns: 5,
      #     interlocutor_prompt: "You are a patient with headache.",
      #     first_user_message: "Hello doctor"
      #   )
      #
      class SimulatedConversationRunner < TestRunners::SimulatedConversationRunner
        # Execute the test
        #
        # @param params [Hash] execution parameters
        # @return [Hash] output_data with standardized format
        def execute(params)
          @all_tool_calls = []
          @mock_function_outputs = params[:mock_function_outputs]
          start_time = Time.current

          messages = execute_conversation(params)

          response_time_ms = ((Time.current - start_time) * 1000).to_i

          build_output_data(
            messages: messages,
            params: params,
            response_time_ms: response_time_ms,
            tokens: token_aggregator.aggregate_from_messages(messages),
            tools_used: tools.map(&:to_s)
          )
        end

        private

        # Execute a conversation (single-turn or multi-turn)
        #
        # RubyLLM::Chat maintains conversation history internally,
        # so we just call chat.ask() for each turn.
        #
        # @param params [Hash] execution parameters
        # @return [Array<Hash>] array of messages
        def execute_conversation(params)
          messages = []
          max_turns = params[:max_turns] || 1

          # Build RubyLLM chat instance once (with tools, system prompt, etc.)
          # Only build real chat if using real LLM
          chat = build_ruby_llm_chat(params) if use_real_llm

          (1..max_turns).each do |turn|
            # Generate user message
            user_message = if turn == 1
              params[:first_user_message]
            else
              interlocutor_simulator.generate_next_message(
                interlocutor_prompt: params[:interlocutor_prompt],
                conversation_history: messages,
                turn: turn
              )
            end

            break if user_message.nil?

            messages << ConversationMessage.new(
              role: "user",
              content: user_message,
              turn: turn
            ).to_h

            # Call LLM - RubyLLM handles tool execution automatically
            response = call_llm(chat: chat, message: user_message, turn: turn)

            # Track tool calls
            if response.tool_calls.present?
              @all_tool_calls.concat(response.tool_calls)
            end

            # Build message with standardized structure
            messages << ConversationMessage.new(
              role: "assistant",
              content: response.text,
              turn: turn,
              usage: response.usage,
              tool_calls: response.tool_calls,
              api_metadata: response.api_metadata
            ).to_h
          end

          messages
        end

        # Build a RubyLLM::Chat instance via RubyLlmService
        #
        # Delegates to RubyLlmService.build_chat for consistent chat configuration
        # across single-turn and multi-turn conversations.
        #
        # @param params [Hash] execution parameters
        # @return [RubyLLM::Chat] configured chat instance
        def build_ruby_llm_chat(params)
          RubyLlmService.build_chat(
            model: model,
            system: params[:system_prompt],
            tools: tools,
            tool_config: tool_config,
            mock_function_outputs: @mock_function_outputs,
            temperature: temperature
          )
        end

        # Call the LLM
        #
        # @param chat [RubyLLM::Chat] chat instance
        # @param message [String] user message
        # @param turn [Integer] current turn number
        # @return [NormalizedLlmResponse] normalized response
        def call_llm(chat:, message:, turn:)
          if use_real_llm
            response = chat.ask(message)
            # Pass chat.messages to extract all tool calls from conversation history
            # (RubyLLM auto-executes tools, so final message has tool_calls=nil)
            LlmResponseNormalizers::RubyLlm.normalize(response, chat_messages: chat.messages)
          else
            mock_llm_response(turn: turn)
          end
        end

        # Get the interlocutor simulator instance
        def interlocutor_simulator
          @interlocutor_simulator ||= Helpers::InterlocutorSimulator.new(use_real_llm: use_real_llm)
        end

        # Get the token aggregator instance
        def token_aggregator
          @token_aggregator ||= Helpers::TokenAggregator.new
        end
      end
    end
  end
end
