# frozen_string_literal: true

require "open3"
require "json"

module PromptTracker
  module McpConnection
    # Stdio transport for MCP connections.
    #
    # Spawns a local subprocess and communicates via stdin/stdout using JSON-RPC 2.0.
    # This is used for local MCP servers like filesystem, git, sqlite, etc.
    #
    # @example Configuration
    #   {
    #     transport: "stdio",
    #     command: "npx",
    #     args: ["-y", "@modelcontextprotocol/server-filesystem"],
    #     env: { "ALLOWED_PATHS" => "/tmp" }
    #   }
    #
    # @example Usage
    #   connection = Stdio.new(config)
    #   connection.connect
    #   tools = connection.call("tools/list", {})
    #   connection.close
    #
    class Stdio < Base
      attr_reader :stdin, :stdout, :stderr, :wait_thr

      # Establish connection by spawning subprocess
      #
      # @raise [ConnectionError] if command fails to spawn
      # @return [void]
      def connect
        command = config[:command]
        args = config[:args] || []
        env = config[:env] || {}

        Rails.logger.info "[McpConnection::Stdio] Spawning: #{command} #{args.join(' ')}"
        Rails.logger.info "[McpConnection::Stdio] Environment: #{env.keys.join(', ')}"

        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(
          env,
          command,
          *args
        )

        @connected = true
        Rails.logger.info "[McpConnection::Stdio] Connected (PID: #{@wait_thr.pid})"
      rescue StandardError => e
        @connected = false
        raise ConnectionError, "Failed to spawn MCP server: #{e.message}"
      end

      # Send JSON-RPC request to subprocess stdin
      #
      # @param method [String] JSON-RPC method name
      # @param params [Hash] method parameters
      # @raise [ConnectionError] if not connected
      # @raise [RequestError] if write fails
      # @return [void]
      def send_request(method, params = {})
        raise ConnectionError, "Not connected" unless connected?

        request = build_request(method, params)
        request_json = request.to_json

        Rails.logger.debug "[McpConnection::Stdio] Sending: #{request_json}"

        @stdin.puts(request_json)
        @stdin.flush
      rescue IOError, Errno::EPIPE => e
        raise RequestError, "Failed to send request: #{e.message}"
      end

      # Receive JSON-RPC response from subprocess stdout
      #
      # @raise [ResponseError] if read fails or response is invalid
      # @return [Hash] parsed JSON-RPC response
      def receive_response
        line = @stdout.gets
        raise ResponseError, "No response from MCP server (process may have died)" if line.nil?

        Rails.logger.debug "[McpConnection::Stdio] Received: #{line.strip}"

        response = JSON.parse(line)
        validate_response(response)
        response
      rescue JSON::ParserError => e
        raise ResponseError, "Invalid JSON response: #{e.message}"
      rescue IOError => e
        raise ResponseError, "Failed to read response: #{e.message}"
      end

      # Close connection and terminate subprocess
      #
      # @return [void]
      def close
        return unless connected?

        Rails.logger.info "[McpConnection::Stdio] Closing connection (PID: #{@wait_thr.pid})"

        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
        @stderr.close unless @stderr.closed?

        # Give process time to exit gracefully
        begin
          Timeout.timeout(5) do
            @wait_thr.join
          end
        rescue Timeout::Error
          # Force kill if it doesn't exit
          Process.kill("KILL", @wait_thr.pid) rescue nil
          @wait_thr.join
        end

        @connected = false
        Rails.logger.info "[McpConnection::Stdio] Connection closed"
      rescue StandardError => e
        Rails.logger.error "[McpConnection::Stdio] Error closing connection: #{e.message}"
        @connected = false
      end

      # Check if subprocess is still alive
      #
      # @return [Boolean] true if process is running
      def alive?
        return false unless @wait_thr
        @wait_thr.alive?
      end
    end
  end
end
