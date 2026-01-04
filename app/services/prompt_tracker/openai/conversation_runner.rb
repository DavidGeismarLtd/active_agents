# frozen_string_literal: true

module PromptTracker
  module Openai
    # Service for running multi-turn conversations with OpenAI Assistants.
    #
    # This service:
    # 1. Creates a thread with the OpenAI Assistants API
    # 2. Uses an LLM to simulate realistic user messages based on a simulation prompt
    # 3. Waits for assistant responses
    # 4. Continues conversation for specified number of turns
    # 5. Returns conversation history with metadata
    #
    # @example Run a conversation
    #   runner = ConversationRunner.new(
    #     assistant_id: "asst_abc123",
    #     interlocutor_simulation_prompt: "You are a patient with a headache. Respond naturally.",
    #     max_turns: 5
    #   )
    #   result = runner.run!
    #   # => {
    #   #   messages: [
    #   #     { role: "user", content: "I have a severe headache", turn: 1 },
    #   #     { role: "assistant", content: "I'm sorry to hear...", turn: 1 }
    #   #   ],
    #   #   thread_id: "thread_xyz",
    #   #   total_turns: 2,
    #   #   status: "completed"
    #   # }
    #
    class ConversationRunner
      attr_reader :assistant_id, :interlocutor_simulation_prompt, :max_turns, :thread_id, :messages, :run_steps

      # Initialize the conversation runner
      #
      # @param assistant_id [String] OpenAI assistant ID (e.g., "asst_abc123")
      # @param interlocutor_simulation_prompt [String] Prompt describing how to simulate the user/patient
      # @param max_turns [Integer] Maximum number of conversation turns (default: 5)
      def initialize(assistant_id:, interlocutor_simulation_prompt:, max_turns: 5)
        @assistant_id = assistant_id
        @interlocutor_simulation_prompt = interlocutor_simulation_prompt
        @max_turns = max_turns
        @thread_id = nil
        @messages = []
        @run_steps = []
      end

      # Run the conversation
      #
      # @return [Hash] conversation result with messages, thread_id, status
      def run!
        Rails.logger.info "🎬 ConversationRunner: Starting conversation with assistant #{@assistant_id}"
        Rails.logger.info "🎬 ConversationRunner: Max turns: #{@max_turns}"
        Rails.logger.info "🎬 ConversationRunner: Simulation prompt: #{@interlocutor_simulation_prompt[0..100]}..."

        # Create a new thread
        Rails.logger.info "🧵 ConversationRunner: Creating thread..."
        create_thread!
        Rails.logger.info "🧵 ConversationRunner: Thread created: #{@thread_id}"

        # Generate and send initial user message using LLM
        Rails.logger.info "🤖 ConversationRunner: Generating initial user message..."
        initial_message = generate_initial_user_message
        Rails.logger.info "💬 ConversationRunner: Generated initial message: #{initial_message}"

        send_user_message(initial_message, turn: 1)
        Rails.logger.info "✅ ConversationRunner: Sent initial user message (turn 1)"

        # Get assistant response
        Rails.logger.info "🤖 ConversationRunner: Getting assistant response (turn 1)..."
        get_assistant_response(turn: 1)
        Rails.logger.info "✅ ConversationRunner: Got assistant response (turn 1)"

        # Continue conversation for remaining turns
        (2..max_turns.to_i).each do |turn|
          Rails.logger.info "🔄 ConversationRunner: Starting turn #{turn}..."

          # Generate next user message based on conversation history
          Rails.logger.info "🤖 ConversationRunner: Generating next user message (turn #{turn})..."
          next_user_message = generate_next_user_message(turn)

          if next_user_message.nil?
            Rails.logger.info "🛑 ConversationRunner: Conversation ended naturally at turn #{turn}"
            break
          end

          Rails.logger.info "💬 ConversationRunner: Generated message: #{next_user_message}"
          send_user_message(next_user_message, turn: turn)
          Rails.logger.info "✅ ConversationRunner: Sent user message (turn #{turn})"

          Rails.logger.info "🤖 ConversationRunner: Getting assistant response (turn #{turn})..."
          get_assistant_response(turn: turn)
          Rails.logger.info "✅ ConversationRunner: Got assistant response (turn #{turn})"
        end

        Rails.logger.info "🎉 ConversationRunner: Conversation completed successfully!"
        Rails.logger.info "📊 ConversationRunner: Total messages: #{@messages.count}"
        Rails.logger.info "📊 ConversationRunner: Total assistant turns: #{@messages.count { |m| m[:role] == 'assistant' }}"
        Rails.logger.info "📊 ConversationRunner: Total run steps: #{@run_steps.count}"

        # Return conversation result
        {
          messages: @messages,
          thread_id: @thread_id,
          total_turns: @messages.count { |m| m[:role] == "assistant" },
          status: "completed",
          run_steps: @run_steps,
          metadata: {
            assistant_id: @assistant_id,
            max_turns: @max_turns,
            interlocutor_simulation_prompt: @interlocutor_simulation_prompt,
            completed_at: Time.current.iso8601
          }
        }
        # rescue => e
        #   {
        #     messages: @messages,
        #     thread_id: @thread_id,
        #     total_turns: @messages.count { |m| m[:role] == "assistant" },
        #     status: "error",
        #     error: "#{e.class}: #{e.message}",
        #     metadata: {
        #       assistant_id: @assistant_id,
        #       max_turns: @max_turns,
        #       failed_at: Time.current.iso8601
        #     }
        #   }
      end

      private

      # Create a new thread with OpenAI
      def create_thread!
        Rails.logger.info "🧵 ConversationRunner: Creating OpenAI thread..."
        client = openai_client
        response = client.threads.create
        @thread_id = response["id"]
        Rails.logger.info "🧵 ConversationRunner: Thread created successfully: #{@thread_id}"
        Rails.logger.debug "🧵 ConversationRunner: Thread details: #{response.inspect}"
      end

      # Send a user message to the thread
      #
      # @param content [String] the message content
      # @param turn [Integer] the conversation turn number
      def send_user_message(content, turn:)
        Rails.logger.info "📤 ConversationRunner: Sending user message to thread #{@thread_id}..."
        client = openai_client

        result = client.messages.create(
          thread_id: @thread_id,
          parameters: {
            role: "user",
            content: content
          }
        )
        Rails.logger.info "📤 ConversationRunner: User message sent successfully"
        Rails.logger.debug "📤 ConversationRunner: API response: #{result.inspect}"

        @messages << {
          role: "user",
          content: content,
          turn: turn,
          timestamp: Time.current.iso8601
        }
      end

      # Get assistant response by running the thread
      #
      # @param turn [Integer] the conversation turn number
      def get_assistant_response(turn:)
        Rails.logger.info "🏃 ConversationRunner: Creating run for assistant #{@assistant_id}..."
        client = openai_client

        # Create a run
        run = client.runs.create(
          thread_id: @thread_id,
          parameters: {
            assistant_id: @assistant_id
          }
        )
        run_id = run["id"]
        Rails.logger.info "🏃 ConversationRunner: Run created: #{run_id}"
        Rails.logger.debug "🏃 ConversationRunner: Run details: #{run.inspect}"

        # Wait for completion
        Rails.logger.info "⏳ ConversationRunner: Waiting for run completion..."
        run = wait_for_run_completion(run_id)
        Rails.logger.info "✅ ConversationRunner: Run completed with status: #{run['status']}"

        # Fetch run steps to capture file_search details
        Rails.logger.info "📋 ConversationRunner: Fetching run steps..."
        fetch_and_store_run_steps(run_id, turn)

        # Get the latest assistant message
        Rails.logger.info "📥 ConversationRunner: Fetching latest assistant message..."
        messages_response = client.messages.list(
          thread_id: @thread_id,
          parameters: { limit: 1, order: "desc" }
        )
        Rails.logger.debug "📥 ConversationRunner: Messages response: #{messages_response.inspect}"

        latest_message = messages_response["data"].first
        Rails.logger.info "📥 ConversationRunner: Latest message role: #{latest_message&.dig('role')}"

        if latest_message && latest_message["role"] == "assistant"
          content = extract_message_content(latest_message)
          Rails.logger.info "📥 ConversationRunner: Extracted assistant message: #{content[0..100]}..."

          @messages << {
            role: "assistant",
            content: content,
            turn: turn,
            timestamp: Time.current.iso8601,
            run_id: run_id
          }
        else
          Rails.logger.warn "⚠️ ConversationRunner: No assistant message found in response!"
        end
      end

      # Fetch run steps and store them for later analysis
      #
      # @param run_id [String] the run ID
      # @param turn [Integer] the conversation turn number
      def fetch_and_store_run_steps(run_id, turn)
        client = openai_client

        response = client.run_steps.list(
          thread_id: @thread_id,
          run_id: run_id,
          parameters: { order: "asc" }
        )

        response["data"].each do |step|
          step_data = {
            id: step["id"],
            run_id: run_id,
            turn: turn,
            type: step["type"],
            status: step["status"],
            step_details: step["step_details"],
            created_at: step["created_at"] ? Time.at(step["created_at"]) : nil,
            completed_at: step["completed_at"] ? Time.at(step["completed_at"]) : nil
          }

          # Extract file_search results if present
          if step["type"] == "tool_calls"
            tool_calls = step.dig("step_details", "tool_calls") || []
            file_search_calls = tool_calls.select { |tc| tc["type"] == "file_search" }

            if file_search_calls.any?
              step_data[:file_search_results] = file_search_calls.map do |tc|
                {
                  id: tc["id"],
                  results: tc.dig("file_search", "results") || []
                }
              end
              Rails.logger.info "🔍 ConversationRunner: Found file_search with #{file_search_calls.count} calls"
            end
          end

          @run_steps << step_data
        end

        Rails.logger.info "📋 ConversationRunner: Stored #{response['data'].count} run steps for turn #{turn}"
      rescue => e
        Rails.logger.warn "⚠️ ConversationRunner: Failed to fetch run steps: #{e.message}"
      end

      # Wait for a run to complete
      #
      # @param run_id [String] the run ID
      # @return [Hash] the completed run object
      def wait_for_run_completion(run_id)
        Rails.logger.info "⏳ ConversationRunner: Waiting for run #{run_id} to complete..."
        client = openai_client
        max_attempts = 30
        attempts = 0

        loop do
          run = client.runs.retrieve(thread_id: @thread_id, id: run_id)
          status = run["status"]
          attempts += 1

          Rails.logger.debug "⏳ ConversationRunner: Poll ##{attempts} - Run status: #{status}"

          if %w[completed failed cancelled expired].include?(status)
            if status == "completed"
              Rails.logger.info "✅ ConversationRunner: Run completed successfully after #{attempts} polls"
            else
              Rails.logger.error "❌ ConversationRunner: Run ended with status: #{status}"
              Rails.logger.error "❌ ConversationRunner: Run details: #{run.inspect}"
            end
            return run
          end

          if attempts >= max_attempts
            Rails.logger.error "❌ ConversationRunner: Run timed out after #{max_attempts} attempts"
            raise "Run timed out after #{max_attempts} attempts"
          end

          Rails.logger.debug "⏳ ConversationRunner: Run still #{status}, continuing to wait..."
          sleep 1
        end
      end

      # Extract message content from OpenAI message object
      #
      # @param message [Hash] the message object from OpenAI
      # @return [String] the message content
      def extract_message_content(message)
        content = message["content"]
        return "" if content.nil? || content.empty?

        # Content is an array of content blocks
        text_blocks = content.select { |block| block["type"] == "text" }
        text_blocks.map { |block| block.dig("text", "value") }.join("\n")
      end

      # Generate initial user message using LLM based on the interlocutor simulation prompt
      #
      # @return [String] the first user message
      def generate_initial_user_message
        Rails.logger.info "🧠 ConversationRunner: Building initial user simulation prompt..."
        prompt = build_user_simulation_prompt(turn: 1, is_initial: true)
        Rails.logger.info "🧠 ConversationRunner: Prompt built (#{prompt.length} chars)"
        Rails.logger.debug "🧠 ConversationRunner: Full prompt:\n#{prompt}"

        Rails.logger.info "🌐 ConversationRunner: Calling LLM (gpt-4o-mini) to generate initial message..."
        response = LlmClientService.call(
          provider: "openai",
          model: "gpt-4o-mini",
          prompt: prompt,
          temperature: 0.8
        )
        Rails.logger.info "🌐 ConversationRunner: LLM response received"
        Rails.logger.debug "🌐 ConversationRunner: Response: #{response.inspect}"

        message = response[:text].strip
        Rails.logger.info "✅ ConversationRunner: Generated initial message: #{message}"
        message
      end

      # Generate the next user message based on conversation history
      #
      # This uses an LLM to simulate a realistic user response based on the conversation.
      #
      # @param turn [Integer] the current turn number
      # @return [String, nil] the next user message, or nil to end conversation
      def generate_next_user_message(turn)
        Rails.logger.info "🧠 ConversationRunner: Building user simulation prompt for turn #{turn}..."
        prompt = build_user_simulation_prompt(turn: turn, is_initial: false)
        Rails.logger.info "🧠 ConversationRunner: Prompt built (#{prompt.length} chars)"
        Rails.logger.debug "🧠 ConversationRunner: Full prompt:\n#{prompt}"

        Rails.logger.info "🌐 ConversationRunner: Calling LLM (gpt-4o-mini) to generate next message..."
        response = LlmClientService.call(
          provider: "openai",
          model: "gpt-4o-mini",
          prompt: prompt,
          temperature: 0.8
        )
        Rails.logger.info "🌐 ConversationRunner: LLM response received"
        Rails.logger.debug "🌐 ConversationRunner: Response: #{response.inspect}"

        message = response[:text].strip
        Rails.logger.info "💬 ConversationRunner: Generated message: #{message}"

        # If LLM indicates conversation should end, return nil
        if message.downcase.include?("[end conversation]")
          Rails.logger.info "🛑 ConversationRunner: Message contains [END CONVERSATION] - ending conversation"
          return nil
        end

        if message.downcase.include?("[end]")
          Rails.logger.info "🛑 ConversationRunner: Message contains [END] - ending conversation"
          return nil
        end

        if message.empty?
          Rails.logger.info "🛑 ConversationRunner: Message is empty - ending conversation"
          return nil
        end

        message
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

            This is the start of a conversation. Generate the first message that the user/patient would send.

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

      # Get OpenAI client
      #
      # @return [OpenAI::Client] the OpenAI client
      def openai_client
        api_key = PromptTracker.configuration.openai_assistants_api_key ||
                  PromptTracker.configuration.api_key_for(:openai) ||
                  ENV["OPENAI_API_KEY"]
        @openai_client ||= OpenAI::Client.new(access_token: api_key)
      end
    end
  end
end
