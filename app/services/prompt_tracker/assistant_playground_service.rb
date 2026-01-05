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

    # Upload a file to OpenAI for use with assistants
    #
    # @param file [File, ActionDispatch::Http::UploadedFile] the file to upload
    # @return [Hash] result with :success, :file_id, :file keys
    def upload_file(file)
      response = client.files.upload(
        parameters: {
          file: file.respond_to?(:tempfile) ? file.tempfile : file,
          purpose: "assistants"
        }
      )

      {
        success: true,
        file_id: response["id"],
        file: {
          id: response["id"],
          filename: response["filename"],
          bytes: response["bytes"],
          purpose: response["purpose"],
          status: response["status"],
          created_at: response["created_at"] ? Time.at(response["created_at"]) : nil
        }
      }
    rescue => e
      Rails.logger.error "Failed to upload file: #{e.message}"
      { success: false, error: e.message }
    end

    # List files uploaded to OpenAI
    #
    # @param purpose [String] filter by purpose (default: "assistants")
    # @return [Hash] result with :success, :files keys
    def list_files(purpose: "assistants")
      response = client.files.list

      files = response["data"].select { |f| f["purpose"] == purpose }.map do |f|
        {
          id: f["id"],
          filename: f["filename"],
          bytes: f["bytes"],
          purpose: f["purpose"],
          status: f["status"],
          created_at: f["created_at"] ? Time.at(f["created_at"]) : nil
        }
      end

      { success: true, files: files }
    rescue => e
      Rails.logger.error "Failed to list files: #{e.message}"
      { success: false, error: e.message }
    end

    # Delete a file from OpenAI
    #
    # @param file_id [String] the file ID to delete
    # @return [Hash] result with :success key
    def delete_file(file_id)
      client.files.delete(id: file_id)
      { success: true }
    rescue => e
      Rails.logger.error "Failed to delete file: #{e.message}"
      { success: false, error: e.message }
    end

    # Create a vector store
    #
    # @param name [String] the vector store name
    # @param file_ids [Array<String>] optional file IDs to add immediately
    # @return [Hash] result with :success, :vector_store_id, :vector_store keys
    def create_vector_store(name:, file_ids: [])
      params = { name: name }
      params[:file_ids] = file_ids if file_ids.present?

      response = client.vector_stores.create(parameters: params)

      {
        success: true,
        vector_store_id: response["id"],
        vector_store: {
          id: response["id"],
          name: response["name"],
          status: response["status"],
          file_counts: response["file_counts"],
          created_at: response["created_at"] ? Time.at(response["created_at"]) : nil
        }
      }
    rescue => e
      Rails.logger.error "Failed to create vector store: #{e.message}"
      { success: false, error: e.message }
    end

    # List vector stores
    #
    # @return [Hash] result with :success, :vector_stores keys
    def list_vector_stores
      response = client.vector_stores.list

      vector_stores = response["data"].map do |vs|
        {
          id: vs["id"],
          name: vs["name"],
          status: vs["status"],
          file_counts: vs["file_counts"],
          created_at: vs["created_at"] ? Time.at(vs["created_at"]) : nil
        }
      end

      { success: true, vector_stores: vector_stores }
    rescue => e
      Rails.logger.error "Failed to list vector stores: #{e.message}"
      { success: false, error: e.message }
    end

    # Add a file to a vector store
    #
    # @param vector_store_id [String] the vector store ID
    # @param file_id [String] the file ID to add
    # @return [Hash] result with :success, :vector_store_file keys
    def add_file_to_vector_store(vector_store_id:, file_id:)
      response = client.vector_store_files.create(
        vector_store_id: vector_store_id,
        parameters: { file_id: file_id }
      )

      {
        success: true,
        vector_store_file: {
          id: response["id"],
          vector_store_id: response["vector_store_id"],
          status: response["status"],
          created_at: response["created_at"] ? Time.at(response["created_at"]) : nil
        }
      }
    rescue => e
      Rails.logger.error "Failed to add file to vector store: #{e.message}"
      { success: false, error: e.message }
    end

    # Get vector store file status
    #
    # @param vector_store_id [String] the vector store ID
    # @param file_id [String] the file ID
    # @return [Hash] result with :success, :status keys
    def get_vector_store_file_status(vector_store_id:, file_id:)
      response = client.vector_store_files.retrieve(
        vector_store_id: vector_store_id,
        id: file_id
      )

      {
        success: true,
        status: response["status"],
        vector_store_file: {
          id: response["id"],
          vector_store_id: response["vector_store_id"],
          status: response["status"],
          last_error: response["last_error"]
        }
      }
    rescue => e
      Rails.logger.error "Failed to get vector store file status: #{e.message}"
      { success: false, error: e.message }
    end

    # List files in a vector store
    #
    # @param vector_store_id [String] the vector store ID
    # @return [Hash] result with :success, :files keys
    def list_vector_store_files(vector_store_id:)
      response = client.vector_store_files.list(vector_store_id: vector_store_id)

      files = response["data"].map do |vsf|
        # Get file details to include filename (cached to avoid N+1 API calls)
        file_details = Rails.cache.fetch("openai_file_#{vsf['id']}", expires_in: 1.hour) do
          client.files.retrieve(id: vsf["id"])
        end

        {
          id: vsf["id"],
          vector_store_id: vsf["vector_store_id"],
          status: vsf["status"],
          filename: file_details["filename"],
          bytes: file_details["bytes"],
          created_at: vsf["created_at"] ? Time.at(vsf["created_at"]) : nil
        }
      end

      { success: true, files: files }
    rescue => e
      Rails.logger.error "Failed to list vector store files: #{e.message}"
      { success: false, error: e.message, files: [] }
    end

    # Attach a vector store to an assistant for file_search
    #
    # @param assistant_id [String] the assistant ID
    # @param vector_store_ids [Array<String>] vector store IDs to attach
    # @return [Hash] result with :success key
    def attach_vector_store_to_assistant(assistant_id:, vector_store_ids:)
      response = client.assistants.modify(
        id: assistant_id,
        parameters: {
          tools: [ { type: "file_search" } ],
          tool_resources: {
            file_search: {
              vector_store_ids: vector_store_ids
            }
          }
        }
      )

      # Update database
      assistant = PromptTracker::Openai::Assistant.find_by(assistant_id: assistant_id)
      if assistant
        assistant.update!(metadata: build_metadata_from_response(response))
      end

      { success: true, api_response: response }
    rescue => e
      Rails.logger.error "Failed to attach vector store: #{e.message}"
      { success: false, error: e.message }
    end

    # Get run steps for a completed run (includes file_search details)
    #
    # @param thread_id [String] the thread ID
    # @param run_id [String] the run ID
    # @return [Hash] result with :success, :run_steps keys
    def get_run_steps(thread_id:, run_id:)
      response = client.run_steps.list(
        thread_id: thread_id,
        run_id: run_id,
        parameters: { order: "asc" }
      )

      run_steps = response["data"].map do |step|
        {
          id: step["id"],
          type: step["type"],
          status: step["status"],
          step_details: step["step_details"],
          created_at: step["created_at"] ? Time.at(step["created_at"]) : nil,
          completed_at: step["completed_at"] ? Time.at(step["completed_at"]) : nil
        }
      end

      { success: true, run_steps: run_steps }
    rescue => e
      Rails.logger.error "Failed to get run steps: #{e.message}"
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
