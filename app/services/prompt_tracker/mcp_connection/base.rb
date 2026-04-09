# frozen_string_literal: true

module PromptTracker
  module McpConnection
    # Base class for MCP (Model Context Protocol) connections.
    #
    # MCP connections handle communication with MCP servers using JSON-RPC 2.0 protocol.
    # Subclasses implement specific transport mechanisms (stdio, HTTP).
    #
    # @abstract Subclass and override {#connect}, {#send_request}, {#receive_response}, and {#close}
    #
    # @example Subclass implementation
    #   class Stdio < Base
    #     def connect
    #       # Spawn subprocess with Open3.popen3
    #     end
    #
    #     def send_request(method, params = {})
    #       # Write JSON-RPC request to stdin
    #     end
    #
    #     def receive_response
    #       # Read JSON-RPC response from stdout
    #     end
    #
    #     def close
    #       # Close subprocess handles
    #     end
    #   end
    #
    class Base
      class ConnectionError < StandardError; end
      class RequestError < StandardError; end
      class ResponseError < StandardError; end

      attr_reader :config, :connected

      # Initialize connection with configuration
      #
      # @param config [Hash] connection configuration
      # @option config [String] :transport Transport type ("stdio" or "http")
      def initialize(config)
        @config = config
        @connected = false
        @request_id = 0
      end

      # Establish connection to MCP server
      #
      # @abstract Subclass must implement
      # @raise [NotImplementedError] if not overridden
      # @return [void]
      def connect
        raise NotImplementedError, "#{self.class} must implement #connect"
      end

      # Send JSON-RPC 2.0 request to server
      #
      # @abstract Subclass must implement
      # @param method [String] JSON-RPC method name (e.g., "tools/list", "tools/call")
      # @param params [Hash] method parameters
      # @raise [NotImplementedError] if not overridden
      # @return [void]
      def send_request(method, params = {})
        raise NotImplementedError, "#{self.class} must implement #send_request"
      end

      # Receive JSON-RPC 2.0 response from server
      #
      # @abstract Subclass must implement
      # @raise [NotImplementedError] if not overridden
      # @return [Hash] parsed JSON-RPC response
      def receive_response
        raise NotImplementedError, "#{self.class} must implement #receive_response"
      end

      # Close connection to MCP server
      #
      # @abstract Subclass must implement
      # @raise [NotImplementedError] if not overridden
      # @return [void]
      def close
        raise NotImplementedError, "#{self.class} must implement #close"
      end

      # Check if connection is established
      #
      # @return [Boolean] true if connected
      def connected?
        @connected
      end

      # Make a complete request-response cycle
      #
      # @param method [String] JSON-RPC method name
      # @param params [Hash] method parameters
      # @return [Hash] response result
      # @raise [ConnectionError] if not connected
      # @raise [ResponseError] if response contains error
      def call(method, params = {})
        raise ConnectionError, "Not connected" unless connected?

        send_request(method, params)
        response = receive_response

        if response["error"]
          raise ResponseError, "MCP error: #{response['error']['message']}"
        end

        response["result"]
      end

      protected

      # Generate next request ID
      #
      # @return [Integer] next request ID
      def next_id
        @request_id += 1
      end

      # Build JSON-RPC 2.0 request
      #
      # @param method [String] method name
      # @param params [Hash] parameters
      # @return [Hash] JSON-RPC request
      def build_request(method, params = {})
        {
          jsonrpc: "2.0",
          id: next_id,
          method: method,
          params: params
        }
      end

      # Validate JSON-RPC response
      #
      # @param response [Hash] parsed response
      # @raise [ResponseError] if response is invalid
      # @return [void]
      def validate_response(response)
        unless response.is_a?(Hash) && response["jsonrpc"] == "2.0"
          raise ResponseError, "Invalid JSON-RPC response: #{response.inspect}"
        end
      end
    end
  end
end
