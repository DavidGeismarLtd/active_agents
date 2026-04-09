# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module McpConnection
    RSpec.describe Http do
      let(:config) do
        {
          transport: "http",
          url: "https://mcp.example.com/api",
          headers: { "Authorization" => "Bearer test-token" },
          timeout: 30
        }
      end
      let(:connection) { described_class.new(config) }
      let(:http_mock) { instance_double(Net::HTTP) }

      describe "#connect" do
        before do
          allow(Net::HTTP).to receive(:new).and_return(http_mock)
          allow(http_mock).to receive(:use_ssl=)
          allow(http_mock).to receive(:read_timeout=)
          allow(http_mock).to receive(:open_timeout=)
          allow(http_mock).to receive(:use_ssl?).and_return(true)
          allow(http_mock).to receive(:verify_mode=)
          allow(http_mock).to receive(:start)
        end

        it "creates HTTP connection with correct host and port" do
          expect(Net::HTTP).to receive(:new).with("mcp.example.com", 443).and_return(http_mock)

          connection.connect
        end

        it "enables SSL for https URLs" do
          expect(http_mock).to receive(:use_ssl=).with(true)
          expect(http_mock).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)

          connection.connect
        end

        it "sets timeouts from config" do
          expect(http_mock).to receive(:read_timeout=).with(30)
          expect(http_mock).to receive(:open_timeout=).with(30)

          connection.connect
        end

        it "starts HTTP connection" do
          expect(http_mock).to receive(:start)

          connection.connect
          expect(connection.connected?).to be true
        end

        it "raises ConnectionError for invalid URL" do
          invalid_config = config.merge(url: "not a url")
          invalid_connection = described_class.new(invalid_config)

          expect {
            invalid_connection.connect
          }.to raise_error(Base::ConnectionError, /Invalid URL/)
        end

        it "raises ConnectionError when URL is missing" do
          no_url_config = config.except(:url)
          no_url_connection = described_class.new(no_url_config)

          expect {
            no_url_connection.connect
          }.to raise_error(Base::ConnectionError, /Missing URL for HTTP transport/)
        end
      end

      describe "#send_request" do
        let(:response_mock) do
          instance_double(Net::HTTPSuccess).tap do |mock|
            allow(mock).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
            allow(mock).to receive(:code).and_return("200")
            allow(mock).to receive(:message).and_return("OK")
            allow(mock).to receive(:body).and_return('{"jsonrpc":"2.0","id":1,"result":{}}')
          end
        end

        before do
          allow(Net::HTTP).to receive(:new).and_return(http_mock)
          allow(http_mock).to receive(:use_ssl=)
          allow(http_mock).to receive(:read_timeout=)
          allow(http_mock).to receive(:open_timeout=)
          allow(http_mock).to receive(:use_ssl?).and_return(true)
          allow(http_mock).to receive(:verify_mode=)
          allow(http_mock).to receive(:start)
          allow(http_mock).to receive(:started?).and_return(true)
          allow(http_mock).to receive(:finish)
          allow(http_mock).to receive(:request).and_return(response_mock)
          connection.connect
        end

        it "sends POST request with JSON-RPC payload" do
          expect(http_mock).to receive(:request) do |request|
            expect(request).to be_a(Net::HTTP::Post)
            expect(request["Content-Type"]).to eq("application/json")
            expect(request["Authorization"]).to eq("Bearer test-token")

            body = JSON.parse(request.body)
            expect(body["method"]).to eq("tools/list")
            expect(body["jsonrpc"]).to eq("2.0")

            response_mock
          end

          connection.send_request("tools/list", {})
        end

        it "raises ConnectionError when not connected" do
          connection.close

          expect {
            connection.send_request("tools/list", {})
          }.to raise_error(Base::ConnectionError, "Not connected")
        end

        it "raises RequestError on HTTP error" do
          error_response = instance_double(Net::HTTPBadRequest)
          allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
          allow(error_response).to receive(:code).and_return("400")
          allow(error_response).to receive(:message).and_return("Bad Request")
          allow(http_mock).to receive(:request).and_return(error_response)

          expect {
            connection.send_request("tools/list", {})
          }.to raise_error(Base::RequestError, "HTTP 400: Bad Request")
        end
      end

      describe "#receive_response" do
        let(:response_mock) do
          instance_double(Net::HTTPSuccess).tap do |mock|
            allow(mock).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
            allow(mock).to receive(:code).and_return("200")
            allow(mock).to receive(:message).and_return("OK")
            allow(mock).to receive(:body).and_return('{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}')
          end
        end

        before do
          allow(Net::HTTP).to receive(:new).and_return(http_mock)
          allow(http_mock).to receive(:use_ssl=)
          allow(http_mock).to receive(:read_timeout=)
          allow(http_mock).to receive(:open_timeout=)
          allow(http_mock).to receive(:use_ssl?).and_return(true)
          allow(http_mock).to receive(:verify_mode=)
          allow(http_mock).to receive(:start)
          allow(http_mock).to receive(:started?).and_return(true)
          allow(http_mock).to receive(:finish)
          allow(http_mock).to receive(:request).and_return(response_mock)
          connection.connect
          connection.send_request("tools/list", {})
        end

        it "parses JSON response from HTTP body" do
          response = connection.receive_response

          expect(response).to eq({
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => { "tools" => [] }
          })
        end

        it "raises ResponseError when no response available" do
          new_connection = described_class.new(config)
          allow(Net::HTTP).to receive(:new).and_return(http_mock)
          allow(http_mock).to receive(:start)
          new_connection.connect

          expect {
            new_connection.receive_response
          }.to raise_error(Base::ResponseError, "No response available")
        end

        it "raises ResponseError on invalid JSON" do
          invalid_response = instance_double(Net::HTTPSuccess)
          allow(invalid_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(invalid_response).to receive(:body).and_return("not json")
          allow(http_mock).to receive(:request).and_return(invalid_response)
          connection.send_request("tools/list", {})

          expect {
            connection.receive_response
          }.to raise_error(Base::ResponseError, /Invalid JSON response/)
        end
      end

      describe "#close" do
        before do
          allow(Net::HTTP).to receive(:new).and_return(http_mock)
          allow(http_mock).to receive(:use_ssl=)
          allow(http_mock).to receive(:read_timeout=)
          allow(http_mock).to receive(:open_timeout=)
          allow(http_mock).to receive(:use_ssl?).and_return(true)
          allow(http_mock).to receive(:verify_mode=)
          allow(http_mock).to receive(:start)
          allow(http_mock).to receive(:started?).and_return(true)
          allow(http_mock).to receive(:finish)
          connection.connect
        end

        it "finishes HTTP connection" do
          expect(http_mock).to receive(:finish)

          connection.close
          expect(connection.connected?).to be false
        end

        it "handles errors gracefully" do
          allow(http_mock).to receive(:finish).and_raise(StandardError, "Connection error")

          expect {
            connection.close
          }.not_to raise_error

          expect(connection.connected?).to be false
        end
      end
    end
  end
end
