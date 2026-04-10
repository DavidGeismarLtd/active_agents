# frozen_string_literal: true

module PromptTracker
  # Manager for MCP (Model Context Protocol) client connections.
  #
  # This service manages the lifecycle of multiple MCP server connections,
  # provides unified tool discovery and execution, and handles connection pooling.
  #
  # MCP tools are exposed to the LLM with a double-underscore prefix to prevent
  # conflicts with database functions:
  # - Original MCP tool: `read_file`
  # - Exposed to LLM: `filesystem__read_file`
  #
  # @example Usage in AgentRuntimeService
  #   manager = McpClientManager.new(["filesystem", "weather_api"])
  #   manager.connect_all
  #
  #   tools = manager.list_all_tools
  #   result = manager.call_tool("filesystem__read_file", { "path" => "/tmp/data.txt" })
  #
  #   manager.disconnect_all
  #
  class McpClientManager
    class ManagerError < StandardError; end
    class ServerNotFoundError < ManagerError; end
    class ToolNotFoundError < ManagerError; end

    TOOL_NAME_SEPARATOR = "__"

    attr_reader :server_names, :connections, :tools_cache

    # Initialize manager with server names
    #
    # @param server_names [Array<String>] names of MCP servers to connect to
    def initialize(server_names)
      @server_names = Array(server_names)
      @connections = {}
      @tools_cache = {}
    end

    # Connect to all configured MCP servers
    #
    # @return [Hash] connection status for each server
    # @raise [ManagerError] if any connection fails
    def connect_all
      results = {}

      server_names.each do |server_name|
        connection = create_connection(server_name)
        connection.connect
        @connections[server_name] = connection
        results[server_name] = { success: true }
        Rails.logger.info "[McpClientManager] Connected to server: #{server_name}"
      end

      results
    end

    # Fetch tools from all connected servers
    #
    # Returns tools in OpenAI/Anthropic function calling format with server name prefix.
    #
    # @return [Array<Hash>] array of tool definitions
    def list_all_tools
      all_tools = []

      @connections.each do |server_name, connection|
        response = connection.call("tools/list", {})
        server_tools = response["tools"] || []

        server_tools.each do |tool|
          all_tools << convert_tool_to_llm_format(server_name, tool)
        end

        @tools_cache[server_name] = server_tools

        Rails.logger.info "[McpClientManager] Discovered #{server_tools.length} tools from #{server_name}"
      end

      all_tools
    end

    # Execute a tool call on the appropriate MCP server
    #
    # @param tool_name [String] prefixed tool name (e.g., "filesystem__read_file")
    # @param arguments [Hash] tool arguments
    # @return [Hash] tool execution result
    # @raise [ToolNotFoundError] if tool or server not found
    def call_tool(tool_name, arguments)
      server_name, original_tool_name = parse_tool_name(tool_name)

      connection = @connections[server_name]
      raise ServerNotFoundError, "MCP server '#{server_name}' not connected" unless connection

      Rails.logger.info "[McpClientManager] Calling #{server_name}::#{original_tool_name}"

      response = connection.call("tools/call", {
        name: original_tool_name,
        arguments: arguments
      })

      Rails.logger.info "[McpClientManager] Tool call successful"
      response
    rescue McpConnection::Base::ResponseError => e
      Rails.logger.error "[McpClientManager] Tool execution error: #{e.message}"
      raise ManagerError, "Tool execution failed: #{e.message}"
    end

    # Disconnect from all MCP servers
    #
    # @return [void]
    def disconnect_all
      @connections.each do |server_name, connection|
        connection.close
        Rails.logger.info "[McpClientManager] Disconnected from #{server_name}"
      rescue StandardError => e
        Rails.logger.error "[McpClientManager] Error disconnecting from #{server_name}: #{e.message}"
      end

      @connections.clear
      @tools_cache.clear
    end

    private

    # Create connection instance for a server
    #
    # @param server_name [String] server name
    # @return [McpConnection::Base] connection instance
    # @raise [ServerNotFoundError] if server not configured
    def create_connection(server_name)
      config = PromptTracker.configuration.mcp_server_config(server_name)
      raise ServerNotFoundError, "MCP server '#{server_name}' not configured" unless config

      case config[:transport]
      when "stdio"
        McpConnection::Stdio.new(config)
      when "http"
        McpConnection::Http.new(config)
      else
        raise ManagerError, "Unknown transport type: #{config[:transport]}"
      end
    end

    # Convert MCP tool schema to LLM function calling format
    def convert_tool_to_llm_format(server_name, tool)
      {
        "name" => build_prefixed_tool_name(server_name, tool["name"]),
        "description" => tool["description"] || "MCP tool from #{server_name}",
        "parameters" => tool["inputSchema"] || { "type" => "object", "properties" => {} }
      }
    end

    # Build prefixed tool name
    #
    # @param server_name [String] server name
    # @param tool_name [String] original tool name
    # @return [String] prefixed tool name (e.g., "filesystem__read_file")
    def build_prefixed_tool_name(server_name, tool_name)
      "#{server_name}#{TOOL_NAME_SEPARATOR}#{tool_name}"
    end

    # Parse prefixed tool name into server and tool components
    #
    # @param prefixed_name [String] prefixed tool name
    # @return [Array<String>] [server_name, tool_name]
    # @raise [ToolNotFoundError] if name format is invalid
    def parse_tool_name(prefixed_name)
      parts = prefixed_name.split(TOOL_NAME_SEPARATOR, 2)

      if parts.length != 2
        raise ToolNotFoundError, "Invalid MCP tool name format: #{prefixed_name}"
      end

      parts
    end
  end
end
