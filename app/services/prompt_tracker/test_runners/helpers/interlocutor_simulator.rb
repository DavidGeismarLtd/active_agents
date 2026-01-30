# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Helpers
      # Simulates user messages in multi-turn conversational tests.
      #
      # This class uses an LLM to generate realistic user responses based on
      # a simulation prompt and conversation history. It's used to create
      # automated conversational tests without requiring manual user input.
      #
      # @example Generate next user message
      #   simulator = InterlocutorSimulator.new(use_real_llm: true)
      #   message = simulator.generate_next_message(
      #     interlocutor_prompt: "You are a patient with a headache",
      #     conversation_history: [
      #       { role: "user", content: "Hello doctor" },
      #       { role: "assistant", content: "Hello! How can I help?" }
      #     ],
      #     turn: 2
      #   )
      #   # => "I've been having a headache for two days..."
      #
      class InterlocutorSimulator
        # @param use_real_llm [Boolean] whether to use real LLM or return mock responses
        def initialize(use_real_llm: false)
          @use_real_llm = use_real_llm
        end

        # Generate the next user message in a conversation
        #
        # @param interlocutor_prompt [String] the simulation prompt describing the user's role
        # @param conversation_history [Array<Hash>] previous messages with :role and :content
        # @param turn [Integer] current turn number
        # @return [String, nil] generated message or nil to end conversation
        def generate_next_message(interlocutor_prompt:, conversation_history:, turn:)
          return mock_message(turn) unless @use_real_llm

          history_text = format_conversation_history(conversation_history)
          prompt = build_simulation_prompt(interlocutor_prompt, history_text)

          response = call_simulation_llm(prompt)
          parse_response(response)
        end

        private

        # Format conversation history for the simulation prompt
        #
        # @param conversation_history [Array<Hash>] messages with :role and :content
        # @return [String] formatted conversation text
        def format_conversation_history(conversation_history)
          conversation_history.map do |msg|
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]
            "#{role.to_s.capitalize}: #{content}"
          end.join("\n\n")
        end

        # Build the prompt for the simulation LLM
        #
        # @param interlocutor_prompt [String] the user role description
        # @param history_text [String] formatted conversation history
        # @return [String] the complete simulation prompt
        def build_simulation_prompt(interlocutor_prompt, history_text)
          <<~PROMPT
            You are simulating a user in a conversation. Based on the following context and conversation history, generate your NEXT response.

            Context: #{interlocutor_prompt}

            Conversation so far:
            #{history_text}

            If the conversation has naturally concluded, respond with exactly: [END_CONVERSATION]
            Otherwise, generate ONLY the user's next message, nothing else.
          PROMPT
        end

        # Call the LLM to generate the simulated user message
        #
        # @param prompt [String] the simulation prompt
        # @return [Hash] LLM response with :text key
        def call_simulation_llm(prompt)
          LlmClientService.call(
            provider: "openai",
            api: "chat_completions",
            model: "gpt-4o-mini",
            prompt: prompt,
            temperature: 0.7
          )
        end

        # Parse the LLM response to extract the user message
        #
        # @param response [Hash] LLM response
        # @return [String, nil] user message or nil if conversation should end
        def parse_response(response)
          text = response[:text].strip
          return nil if text.include?("[END_CONVERSATION]")
          text
        end

        # Generate a mock message for testing
        #
        # @param turn [Integer] current turn number
        # @return [String] mock message
        def mock_message(turn)
          "I have another question."
        end
      end
    end
  end
end
