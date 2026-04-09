# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module McpConnection
    RSpec.describe Base do
      let(:config) { { transport: "test" } }
      let(:connection) { TestConnection.new(config) }

      # Create a test subclass since Base is abstract
      class TestConnection < Base
        def connect
          @connected = true
        end

        def send_request(method, params = {})
          # Test implementation
        end

        def receive_response
          { "jsonrpc" => "2.0", "id" => 1, "result" => { "test" => "data" } }
        end

        def close
          @connected = false
        end
      end

      describe "#initialize" do
        it "sets config" do
          expect(connection.config).to eq(config)
        end

        it "sets connected to false" do
          expect(connection.connected?).to be false
        end

        it "initializes request_id to 0" do
          expect(connection.instance_variable_get(:@request_id)).to eq(0)
        end
      end

      describe "#connected?" do
        it "returns false initially" do
          expect(connection.connected?).to be false
        end

        it "returns true after connect" do
          connection.connect
          expect(connection.connected?).to be true
        end

        it "returns false after close" do
          connection.connect
          connection.close
          expect(connection.connected?).to be false
        end
      end

      describe "#call" do
        before { connection.connect }
        after { connection.close }

        it "sends request and receives response" do
          allow(connection).to receive(:send_request)
          allow(connection).to receive(:receive_response).and_return({
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => { "tools" => [] }
          })

          result = connection.call("tools/list", {})
          expect(result).to eq({ "tools" => [] })
        end

        it "raises ConnectionError when not connected" do
          connection.close
          expect {
            connection.call("tools/list", {})
          }.to raise_error(Base::ConnectionError, "Not connected")
        end

        it "raises ResponseError when response contains error" do
          allow(connection).to receive(:send_request)
          allow(connection).to receive(:receive_response).and_return({
            "jsonrpc" => "2.0",
            "id" => 1,
            "error" => { "code" => -32601, "message" => "Method not found" }
          })

          expect {
            connection.call("invalid/method", {})
          }.to raise_error(Base::ResponseError, "MCP error: Method not found")
        end
      end

      describe "#build_request" do
        it "builds valid JSON-RPC 2.0 request" do
          request = connection.send(:build_request, "tools/list", {})

          expect(request).to include(
            jsonrpc: "2.0",
            method: "tools/list",
            params: {},
            id: 1
          )
        end

        it "increments request ID for each call" do
          request1 = connection.send(:build_request, "method1", {})
          request2 = connection.send(:build_request, "method2", {})

          expect(request1[:id]).to eq(1)
          expect(request2[:id]).to eq(2)
        end

        it "includes params in request" do
          params = { "path" => "/tmp/test.txt" }
          request = connection.send(:build_request, "read_file", params)

          expect(request[:params]).to eq(params)
        end
      end

      describe "#validate_response" do
        it "does not raise for valid response with result" do
          response = {
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => { "data" => "test" }
          }

          expect {
            connection.send(:validate_response, response)
          }.not_to raise_error
        end

        it "raises ResponseError for missing jsonrpc field" do
          response = { "id" => 1, "result" => {} }

          expect {
            connection.send(:validate_response, response)
          }.to raise_error(Base::ResponseError, /Invalid JSON-RPC response/)
        end

        it "raises ResponseError for wrong jsonrpc version" do
          response = { "jsonrpc" => "1.0", "id" => 1, "result" => {} }

          expect {
            connection.send(:validate_response, response)
          }.to raise_error(Base::ResponseError, /Invalid JSON-RPC response/)
        end
      end
    end
  end
end
