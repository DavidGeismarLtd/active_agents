# frozen_string_literal: true

module PromptTracker
  module Openai
    # Service for running multi-turn conversations using OpenAI Response API.
    #
    # This service:
    # 1. Uses the Response API with previous_response_id for conversation state
    # 2. Uses an LLM to simulate realistic user messages based on a simulation prompt
    # 3. Continues conversation for specified number of turns
    # 4. Returns conversation history with metadata
    #
    # @example Run a conversation
    #   runner = ResponseApiConversationRunner.new(
    #     model: "gpt-4o",
    #     system_prompt: "You are a helpful medical assistant.",
    #     interlocutor_simulation_prompt: "You are a patient with a headache.",
    #     max_turns: 5,
    #     tools: [:web_search]
    #   )
    #   result = runner.run!
    #   result.messages        # => [{ role: "user", content: "..." }, ...]
    #   result.total_turns     # => 5
    #   result.completed?      # => true
    #
    class ResponseApiConversationRunner
      attr_reader :model, :system_prompt, :interlocutor_simulation_prompt,
                  :max_turns, :tools, :temperature, :messages, :previous_response_id

      # Initialize the conversation runner
      #
      # @param model [String] OpenAI model ID (e.g., "gpt-4o")
      # @param system_prompt [String] System instructions for the assistant
      # @param interlocutor_simulation_prompt [String] Prompt describing how to simulate the user
      # @param max_turns [Integer] Maximum number of conversation turns (default: 5)
      # @param tools [Array<Symbol>] Response API tools (:web_search, :file_search, :code_interpreter)
      # @param temperature [Float] Temperature for the assistant (default: 0.7)
      def initialize(
        model:,
        system_prompt:,
        interlocutor_simulation_prompt:,
        max_turns: 5,
        tools: [],
        temperature: 0.7
      )
        @model = model
        @system_prompt = system_prompt
        @interlocutor_simulation_prompt = interlocutor_simulation_prompt
        @max_turns = max_turns
        @tools = tools
        @temperature = temperature
        @messages = []
        @previous_response_id = nil
      end

      # Run the conversation
      #
      # @return [ConversationResult] conversation result object
      def run!
        Rails.logger.info "🎬 ResponseApiConversationRunner: Starting conversation"
        Rails.logger.info "🎬 Model: #{@model}, Max turns: #{@max_turns}"

        # Generate and send initial user message
        initial_message = generate_initial_user_message
        send_user_message(initial_message, turn: 1)

        # Get assistant response
        get_assistant_response(turn: 1)

        # Continue conversation for remaining turns
        (2..max_turns.to_i).each do |turn|
          Rails.logger.info "🔄 ResponseApiConversationRunner: Starting turn #{turn}..."

          # Generate next user message based on conversation history
          next_user_message = generate_next_user_message(turn)

          if next_user_message.nil?
            Rails.logger.info "🛑 Conversation ended naturally at turn #{turn}"
            break
          end

          send_user_message(next_user_message, turn: turn)
          get_assistant_response(turn: turn)
        end

        Rails.logger.info "🎉 ResponseApiConversationRunner: Conversation completed!"

        build_result(status: "completed")
      end

      private

      # Send a user message and record it
      #
      # @param content [String] the message content
      # @param turn [Integer] the conversation turn number
      def send_user_message(content, turn:)
        @messages << {
          role: "user",
          content: content,
          turn: turn,
          timestamp: Time.current.iso8601
        }
      end

      # Get assistant response using Response API
      #
      # @param turn [Integer] the conversation turn number
      def get_assistant_response(turn:)
        last_user_message = @messages.last[:content]

        response = if @previous_response_id.nil?
          # First turn - use call with system prompt
          OpenaiResponseService.call(
            model: @model,
            user_prompt: last_user_message,
            system_prompt: @system_prompt,
            tools: @tools,
            temperature: @temperature
          )
        else
          # Subsequent turns - use call_with_context
          OpenaiResponseService.call_with_context(
            model: @model,
            user_prompt: last_user_message,
            previous_response_id: @previous_response_id,
            tools: @tools,
            temperature: @temperature
          )
        end

        # Store response ID for next turn
        @previous_response_id = response[:response_id]

        @messages << {
          role: "assistant",
          content: response[:text],
          turn: turn,
          timestamp: Time.current.iso8601,
          response_id: response[:response_id],
          tool_calls: response[:tool_calls],
          usage: response[:usage]
        }
      end

      # Generate initial user message using LLM
      #
      # @return [String] the first user message
      def generate_initial_user_message
        prompt = build_user_simulation_prompt(turn: 1, is_initial: true)

        response = LlmClientService.call(
          provider: "openai",
          api: "chat_completions",
          model: "gpt-4o-mini",
          prompt: prompt,
          temperature: 0.8
        )

        response[:text].strip
      end

      # Generate the next user message based on conversation history
      #
      # @param turn [Integer] the current turn number
      # @return [String, nil] the next user message, or nil to end conversation
      def generate_next_user_message(turn)
        prompt = build_user_simulation_prompt(turn: turn, is_initial: false)

        response = LlmClientService.call(
          provider: "openai",
          api: "chat_completions",
          model: "gpt-4o-mini",
          prompt: prompt,
          temperature: 0.8
        )

        message = response[:text].strip
        return nil if should_end_conversation?(message)

        message
      end

      # Check if conversation should end based on message content
      #
      # @param message [String] the generated message
      # @return [Boolean]
      def should_end_conversation?(message)
        return true if message.empty?
        return true if message.downcase.include?("[end conversation]")
        return true if message.downcase.include?("[end]")

        false
      end

      # Build the prompt for simulating user messages
      #
      # @param turn [Integer] the current turn number
      # @param is_initial [Boolean] whether this is the first message
      # @return [String] the prompt for the LLM
      def build_user_simulation_prompt(turn:, is_initial:)
        if is_initial
          <<~PROMPT
            #{interlocutor_simulation_prompt}

            This is the start of a conversation. Generate the first message that the user would send.

            IMPORTANT:
            - Respond with ONLY the user's message (no explanations, no meta-commentary)
            - Keep it natural and conversational
            - Keep it concise (1-3 sentences)
            - Do NOT include labels like "User:" or "Patient:"

            Generate the first user message now:
          PROMPT
        else
          <<~PROMPT
            #{interlocutor_simulation_prompt}

            CONVERSATION HISTORY:
            #{format_conversation_history}

            Based on the conversation above, generate the next user message (turn #{turn}).

            IMPORTANT:
            - Respond with ONLY the user's message (no explanations, no meta-commentary)
            - Keep it natural and conversational
            - Keep it concise (1-3 sentences)
            - Do NOT include labels like "User:" or "Patient:"
            - If the conversation should end naturally (e.g., user is satisfied, issue resolved), respond with exactly: [END CONVERSATION]

            Generate the next user message now:
          PROMPT
        end
      end

      # Format conversation history for the LLM prompt
      #
      # @return [String] formatted conversation history
      def format_conversation_history
        return "No messages yet." if @messages.empty?

        @messages.map do |msg|
          "#{msg[:role].upcase}: #{msg[:content]}"
        end.join("\n\n")
      end

      # Build the conversation result object
      #
      # @param status [String] the conversation status
      # @return [ConversationResult]
      def build_result(status:)
        ConversationResult.new(
          messages: @messages,
          total_turns: @messages.count { |m| m[:role] == "assistant" },
          status: status,
          previous_response_id: @previous_response_id,
          metadata: {
            model: @model,
            max_turns: @max_turns,
            interlocutor_simulation_prompt: @interlocutor_simulation_prompt,
            tools: @tools,
            completed_at: Time.current.iso8601
          }
        )
      end
    end
  end
end
