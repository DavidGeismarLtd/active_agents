# frozen_string_literal: true

module PromptTracker
  # Service for managing OpenAI Assistants in the playground.
  #
  # Provides methods for:
  # - Creating and updating assistants via OpenAI API
  # - Managing conversation threads
  # - Sending messages and running assistants
  # - Loading thread message history
  #
  # @example Create a new assistant
  #   service = AssistantPlaygroundService.new
  #   result = service.create_assistant(
  #     name: "Support Bot",
  #     instructions: "You are helpful",
  #     model: "gpt-4o",
  #     tools: ["file_search"]
  #   )
  #
  class AssistantPlaygroundService
    class PlaygroundError < StandardError; end

    attr_reader :client

    def initialize
      @client = build_client
    end

    # Create a new assistant via OpenAI API
    #
    # @param params [Hash] assistant parameters
    # @option params [String] :name Assistant name (required)
    # @option params [String] :description Assistant description
    # @option params [String] :instructions System instructions
    # @option params [String] :model Model to use (e.g., "gpt-4o")
    # @option params [Array<String>] :tools Tools to enable
    # @option params [Float] :temperature Sampling temperature (0-2)
    # @option params [Float] :top_p Nucleus sampling (0-1)
    # @option params [String] :response_format Response format type
    # @option params [Hash] :metadata Custom metadata
    # @return [Hash] result with :success, :assistant, :api_response keys
    def create_assistant(params)
      response = client.assistants.create(
        parameters: build_assistant_params(params)
      )

      # Save to database
      # Skip fetch_from_openai callback since we already have the data from the create response
      assistant = PromptTracker::Openai::Assistant.new(
        assistant_id: response["id"],
        name: response["name"],
        description: response["description"],
        metadata: build_metadata_from_response(response)
      )
      assistant.skip_fetch_from_openai = true
      assistant.save!

      { success: true, assistant: assistant, api_response: response }
    rescue => e
      Rails.logger.error "Failed to create assistant: #{e.message}"
      { success: false, error: e.message }
    end

    # Update existing assistant via OpenAI API
    #
    # @param assistant_id [String] the assistant ID to update
    # @param params [Hash] assistant parameters to update
    # @return [Hash] result with :success, :assistant, :api_response keys
    def update_assistant(assistant_id, params)
      response = client.assistants.modify(
        id: assistant_id,
        parameters: build_assistant_params(params)
      )

      # Update database
      assistant = PromptTracker::Openai::Assistant.find_by(assistant_id: assistant_id)
      raise PlaygroundError, "Assistant not found in database" unless assistant

      assistant.update!(
        name: response["name"],
        description: response["description"],
        metadata: build_metadata_from_response(response)
      )

      { success: true, assistant: assistant, api_response: response }
    rescue => e
      Rails.logger.error "Failed to update assistant #{assistant_id}: #{e.message}"
      { success: false, error: e.message }
    end

    # Create a new thread for conversation
    #
    # @return [Hash] result with :success, :thread_id keys
    def create_thread
      response = client.threads.create
      { success: true, thread_id: response["id"] }
    rescue => e
      Rails.logger.error "Failed to create thread: #{e.message}"
      { success: false, error: e.message }
    end

    # Send message and run assistant
    #
    # @param thread_id [String] the thread ID
    # @param assistant_id [String] the assistant ID
    # @param content [String] the message content
    # @param timeout [Integer] maximum seconds to wait for completion
    # @return [Hash] result with :success, :message, :usage keys
    def send_message(thread_id:, assistant_id:, content:, timeout: 60)
      # Add user message
      client.messages.create(
        thread_id: thread_id,
        parameters: {
          role: "user",
          content: content
        }
      )

      # Run assistant
      run = client.runs.create(
        thread_id: thread_id,
        parameters: { assistant_id: assistant_id }
      )

      # Wait for completion
      final_run = wait_for_completion(thread_id, run["id"], timeout)

      # Get assistant's response
      messages = client.messages.list(
        thread_id: thread_id,
        parameters: { order: "desc", limit: 1 }
      )

      assistant_message = messages["data"].first

      {
        success: true,
        message: {
          role: "assistant",
          content: assistant_message.dig("content", 0, "text", "value"),
          created_at: Time.at(assistant_message["created_at"]),
          run_id: run["id"]
        },
        usage: final_run["usage"]
      }
    rescue => e
      Rails.logger.error "Failed to send message: #{e.message}"
      { success: false, error: e.message }
    end

    # Load thread messages
    #
    # @param thread_id [String] the thread ID
    # @param limit [Integer] maximum number of messages to load
    # @return [Hash] result with :success, :messages keys
    def load_messages(thread_id:, limit: 50)
      response = client.messages.list(
        thread_id: thread_id,
        parameters: { order: "asc", limit: limit }
      )

      messages = response["data"].map do |msg|
        {
          role: msg["role"],
          content: msg.dig("content", 0, "text", "value"),
          created_at: Time.at(msg["created_at"])
        }
      end

      { success: true, messages: messages }
    rescue => e
      Rails.logger.error "Failed to load messages: #{e.message}"
      { success: false, error: e.message }
    end

    private

    # Build OpenAI client
    #
    # @return [OpenAI::Client] configured client
    def build_client
      require "openai"

      # Try OPENAI_LOUNA_API_KEY first (used in existing code), fallback to OPENAI_API_KEY
      api_key = PromptTracker.configuration.openai_assistants_api_key
      raise PlaygroundError, "OpenAI API key not configured" if api_key.blank?

      OpenAI::Client.new(access_token: api_key)
    end

    # Build assistant parameters for API call
    #
    # @param params [Hash] input parameters
    # @return [Hash] formatted parameters for OpenAI API
    def build_assistant_params(params)
      api_params = {}

      api_params[:name] = params[:name] if params[:name].present?
      api_params[:description] = params[:description] if params[:description].present?
      api_params[:instructions] = params[:instructions] if params[:instructions].present?
      api_params[:model] = params[:model] if params[:model].present?
      api_params[:tools] = build_tools_array(params[:tools]) if params[:tools].present?
      api_params[:temperature] = params[:temperature].to_f if params[:temperature].present?
      api_params[:top_p] = params[:top_p].to_f if params[:top_p].present?
      api_params[:response_format] = build_response_format(params[:response_format]) if params[:response_format].present?
      api_params[:metadata] = params[:metadata] if params[:metadata].present?

      api_params
    end

    # Build tools array from tool names
    #
    # @param tools_param [Array<String>] array of tool names
    # @return [Array<Hash>] array of tool objects
    def build_tools_array(tools_param)
      return [] if tools_param.blank?

      tools = []
      tools << { type: "file_search" } if tools_param.include?("file_search")
      tools << { type: "code_interpreter" } if tools_param.include?("code_interpreter")
      # Functions will be added in future enhancement
      tools
    end

    # Build response format object
    #
    # @param format [String] format type
    # @return [Hash, nil] response format object or nil
    def build_response_format(format)
      return nil if format.blank? || format == "auto"
      { type: format }
    end

    # Build metadata hash from API response
    #
    # @param response [Hash] API response
    # @return [Hash] metadata hash
    def build_metadata_from_response(response)
      {
        instructions: response["instructions"],
        model: response["model"],
        tools: response["tools"] || [],
        file_ids: response["file_ids"] || [],
        temperature: response["temperature"],
        top_p: response["top_p"],
        response_format: response["response_format"],
        tool_resources: response["tool_resources"] || {},
        last_synced_at: Time.current.iso8601
      }
    end

    # Wait for assistant run to complete
    #
    # @param thread_id [String] the thread ID
    # @param run_id [String] the run ID
    # @param timeout [Integer] maximum seconds to wait
    # @return [Hash] final run status
    # @raise [PlaygroundError] if run fails or times out
    def wait_for_completion(thread_id, run_id, timeout)
      start_time = Time.now

      loop do
        run = client.runs.retrieve(thread_id: thread_id, id: run_id)
        status = run["status"]

        case status
        when "completed"
          return run
        when "failed"
          error_msg = run.dig("last_error", "message") || "Unknown error"
          raise PlaygroundError, "Run failed: #{error_msg}"
        when "cancelled"
          raise PlaygroundError, "Run was cancelled"
        when "expired"
          raise PlaygroundError, "Run expired"
        when "requires_action"
          raise PlaygroundError, "Tool calls not yet supported in playground"
        end

        # Check timeout
        if Time.now - start_time > timeout
          raise PlaygroundError, "Run timed out after #{timeout} seconds"
        end

        # Poll every second
        sleep 1
      end
    end
  end
end
