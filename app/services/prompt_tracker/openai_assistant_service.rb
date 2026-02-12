# frozen_string_literal: true

module PromptTracker
  # Service for calling OpenAI Assistants API.
  #
  # OpenAI Assistants API is different from Chat Completions API:
  # - Creates a thread for conversation
  # - Runs an assistant on that thread
  # - Waits for completion (can take time)
  # - Retrieves the assistant's response
  #
  # This service provides a consistent interface matching LlmClientService.
  #
  # @example Call an assistant
  #   response = OpenaiAssistantService.call(
  #     assistant_id: "asst_abc123",
  #     prompt: "What's the weather in Berlin?"
  #   )
  #   response[:text]  # => "The current weather in Berlin is..."
  #
  class OpenaiAssistantService
    class AssistantError < StandardError; end

    # Call an OpenAI Assistant
    #
    # @param assistant_id [String] the assistant ID (starts with "asst_")
    # @param prompt [String] the user message
    # @param timeout [Integer] maximum seconds to wait for completion (default: 60)
    # @return [Hash] response with :text, :usage, :model, :raw keys
    # @raise [AssistantError] if API call fails or times out
    def self.call(assistant_id:, prompt:, timeout: 60)
      new(assistant_id: assistant_id, prompt: prompt, timeout: timeout).call
    end

    attr_reader :assistant_id, :prompt, :timeout, :client

    def initialize(assistant_id:, prompt:, timeout: 60)
      @assistant_id = assistant_id
      @prompt = prompt
      @timeout = timeout
      @client = build_client
    end

    # Execute the assistant API call
    #
    # @return [Hash] response with :text, :usage, :model, :raw keys
    def call
      thread_id = create_thread
      add_message(thread_id)
      run_id = run_assistant(thread_id)
      wait_for_completion(thread_id, run_id)
      retrieve_response(thread_id, run_id)
    end

    private

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    def build_client
      require "openai"

      # Use configuration API key, fallback to ENV for backward compatibility
      api_key = PromptTracker.configuration.api_key_for(:openai)
      raise AssistantError, "OpenAI API key not configured" if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end

    # Create a new thread
    #
    # @return [String] thread ID
    def create_thread
      response = client.threads.create
      response["id"]
    rescue => e
      raise AssistantError, "Failed to create thread: #{e.message}"
    end

    # Add user message to thread
    #
    # @param thread_id [String] the thread ID
    # @return [Hash] message response
    def add_message(thread_id)
      client.messages.create(
        thread_id: thread_id,
        parameters: {
          role: "user",
          content: prompt
        }
      )
    rescue => e
      raise AssistantError, "Failed to add message: #{e.message}"
    end

    # Run the assistant on the thread
    #
    # @param thread_id [String] the thread ID
    # @return [String] run ID
    def run_assistant(thread_id)
      response = client.runs.create(
        thread_id: thread_id,
        parameters: {
          assistant_id: assistant_id
        }
      )
      response["id"]
    rescue => e
      raise AssistantError, "Failed to run assistant: #{e.message}"
    end

    # Wait for the assistant run to complete
    #
    # @param thread_id [String] the thread ID
    # @param run_id [String] the run ID
    # @return [Hash] final run status
    def wait_for_completion(thread_id, run_id)
      start_time = Time.now

      loop do
        run = client.runs.retrieve(thread_id: thread_id, id: run_id)
        status = run["status"]

        case status
        when "completed"
          return run
        when "failed"
          error_msg = run.dig("last_error", "message") || "Unknown error"
          raise AssistantError, "Assistant run failed: #{error_msg}"
        when "cancelled"
          raise AssistantError, "Assistant run was cancelled"
        when "expired"
          raise AssistantError, "Assistant run expired"
        when "requires_action"
          # Tool calls not yet implemented
          raise AssistantError, "Assistant requires action (tool calls not yet supported)"
        end

        # Check timeout
        if Time.now - start_time > timeout
          raise AssistantError, "Assistant run timed out after #{timeout} seconds"
        end

        # Poll every second
        sleep 1
      end
    rescue AssistantError
      raise
    rescue => e
      raise AssistantError, "Error waiting for completion: #{e.message}"
    end

    # Retrieve the assistant's response
    #
    # @param thread_id [String] the thread ID
    # @param run_id [String] the run ID
    # @return [Hash] normalized response
    def retrieve_response(thread_id, run_id)
      # Get the latest message (assistant's response)
      messages_response = client.messages.list(
        thread_id: thread_id,
        parameters: { order: "desc", limit: 1 }
      )

      assistant_message = messages_response["data"].first
      content = assistant_message.dig("content", 0, "text", "value")

      # Get usage from the run
      run = client.runs.retrieve(thread_id: thread_id, id: run_id)
      usage = run["usage"] || {}

      # Return in standard format matching LlmClientService
      {
        text: content,
        usage: {
          prompt_tokens: usage["prompt_tokens"] || 0,
          completion_tokens: usage["completion_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0
        },
        model: assistant_id,
        raw: {
          thread_id: thread_id,
          run_id: run_id,
          assistant_message: assistant_message,
          run: run
        }
      }
    rescue => e
      raise AssistantError, "Failed to retrieve response: #{e.message}"
    end
  end
end
