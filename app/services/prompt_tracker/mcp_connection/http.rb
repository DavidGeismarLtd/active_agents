# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PromptTracker
  module McpConnection
    # HTTP transport for MCP connections.
    #
    # Connects to remote MCP servers via HTTP/HTTPS using JSON-RPC 2.0.
    # Supports static API key authentication via Authorization header.
    #
    # @example Configuration
    #   {
    #     transport: "http",
    #     url: "https://mcp.example.com/api",
    #     headers: { "Authorization" => "Bearer sk-..." }
    #   }
    #
    class Http < Base
      attr_reader :uri, :http, :last_response

      # Establish HTTP connection
      #
      # @raise [ConnectionError] if URL is invalid or connection fails
      # @return [void]
      def connect
        url = config[:url]
        raise ConnectionError, "Missing URL for HTTP transport" if url.blank?

        @uri = URI.parse(url)
        @http = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl = @uri.scheme == "https"
        @http.read_timeout = config[:timeout] || 30
        @http.open_timeout = config[:timeout] || 30

        if @http.use_ssl?
          @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        Rails.logger.info "[McpConnection::Http] Connecting to #{@uri}"

        @http.start
        @connected = true

        Rails.logger.info "[McpConnection::Http] Connected to #{@uri.host}"
      rescue URI::InvalidURIError => e
        raise ConnectionError, "Invalid URL: #{e.message}"
      rescue StandardError => e
        @connected = false
        raise ConnectionError, "Failed to connect to MCP server: #{e.message}"
      end

      # Send JSON-RPC request via HTTP POST
      #
      # @param method [String] JSON-RPC method name
      # @param params [Hash] method parameters
      # @return [void]
      def send_request(method, params = {})
        raise ConnectionError, "Not connected" unless connected?

        request = build_http_request(method, params)

        @last_response = @http.request(request)

        unless @last_response.is_a?(Net::HTTPSuccess)
          raise RequestError, "HTTP #{@last_response.code}: #{@last_response.message}"
        end
      rescue Net::HTTPError, SocketError, Timeout::Error => e
        raise RequestError, "Failed to send request: #{e.message}"
      end

      # Receive JSON-RPC response from HTTP response body
      #
      # @return [Hash] parsed JSON-RPC response
      def receive_response
        raise ResponseError, "No response available" unless @last_response

        body = @last_response.body

        response = JSON.parse(body)
        validate_response(response)
        response
      rescue JSON::ParserError => e
        raise ResponseError, "Invalid JSON response: #{e.message}"
      end

      # Close HTTP connection
      #
      # @return [void]
      def close
        return unless connected?

        Rails.logger.info "[McpConnection::Http] Closing connection to #{@uri.host}"

        @http.finish if @http.started?
        @connected = false

        Rails.logger.info "[McpConnection::Http] Connection closed"
      rescue StandardError => e
        Rails.logger.error "[McpConnection::Http] Error closing connection: #{e.message}"
        @connected = false
      end

      private

      # Build HTTP POST request with JSON-RPC payload
      #
      # @param method [String] JSON-RPC method name
      # @param params [Hash] method parameters
      # @return [Net::HTTP::Post] HTTP request object
      def build_http_request(method, params)
        request = Net::HTTP::Post.new(@uri.path.presence || "/")
        request["Content-Type"] = "application/json"

        if config[:headers].present?
          config[:headers].each do |key, value|
            request[key] = value
          end
        end

        rpc_request = build_request(method, params)
        request.body = rpc_request.to_json

        request
      end
    end
  end
end
