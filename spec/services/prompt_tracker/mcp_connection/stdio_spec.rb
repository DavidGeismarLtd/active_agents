# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module McpConnection
    RSpec.describe Stdio do
      let(:config) do
        {
          transport: "stdio",
          command: "echo",
          args: [ "test" ],
          env: { "TEST_VAR" => "value" }
        }
      end
      let(:connection) { described_class.new(config) }

      describe "#connect" do
        it "spawns subprocess with command and args" do
          expect(Open3).to receive(:popen3).with(
            { "TEST_VAR" => "value" },
            "echo",
            "test"
          ).and_return([ double(:stdin), double(:stdout), double(:stderr), double(:wait_thr, pid: 12345, alive?: true) ])

          connection.connect
          expect(connection.connected?).to be true
        end

        it "raises ConnectionError when command fails" do
          allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, "No such file or directory")

          expect {
            connection.connect
          }.to raise_error(Base::ConnectionError, /Failed to spawn MCP server/)
        end

        it "logs connection details" do
          allow(Open3).to receive(:popen3).and_return([
            double(:stdin),
            double(:stdout),
            double(:stderr),
            double(:wait_thr, pid: 12345, alive?: true)
          ])

          expect(Rails.logger).to receive(:info).with("[McpConnection::Stdio] Spawning: echo test")
          expect(Rails.logger).to receive(:info).with("[McpConnection::Stdio] Environment: TEST_VAR")
          expect(Rails.logger).to receive(:info).with("[McpConnection::Stdio] Connected (PID: 12345)")

          connection.connect
        end
      end

      describe "#send_request" do
        let(:stdin) { StringIO.new }
        let(:stdout) { StringIO.new }
        let(:stderr) { StringIO.new }
        let(:wait_thr) { double(:wait_thr, pid: 12345, alive?: true, join: nil) }

        before do
          allow(Open3).to receive(:popen3).and_return([ stdin, stdout, stderr, wait_thr ])
          connection.connect
        end

        it "writes JSON-RPC request to stdin" do
          connection.send_request("tools/list", {})

          stdin.rewind
          request = JSON.parse(stdin.read.strip)

          expect(request).to include(
            "jsonrpc" => "2.0",
            "method" => "tools/list",
            "params" => {}
          )
        end

        it "raises ConnectionError when not connected" do
          allow(stdin).to receive(:close)
          allow(stdout).to receive(:close)
          allow(stderr).to receive(:close)
          allow(stdin).to receive(:closed?).and_return(false, true)
          allow(stdout).to receive(:closed?).and_return(false, true)
          allow(stderr).to receive(:closed?).and_return(false, true)

          connection.close

          expect {
            connection.send_request("tools/list", {})
          }.to raise_error(Base::ConnectionError, "Not connected")
        end

        it "raises RequestError on IO error" do
          allow(stdin).to receive(:puts).and_raise(IOError, "Broken pipe")

          expect {
            connection.send_request("tools/list", {})
          }.to raise_error(Base::RequestError, /Failed to send request/)
        end
      end

      describe "#receive_response" do
        let(:stdin) { StringIO.new }
        let(:stdout) { StringIO.new }
        let(:stderr) { StringIO.new }
        let(:wait_thr) { double(:wait_thr, pid: 12345, alive?: true) }

        before do
          allow(Open3).to receive(:popen3).and_return([ stdin, stdout, stderr, wait_thr ])
          connection.connect
        end

        it "reads and parses JSON response from stdout" do
          response_data = { "jsonrpc" => "2.0", "id" => 1, "result" => { "tools" => [] } }
          stdout.puts(response_data.to_json)
          stdout.rewind

          response = connection.receive_response
          expect(response).to eq(response_data)
        end

        it "raises ResponseError when stdout is closed" do
          allow(stdout).to receive(:gets).and_return(nil)

          expect {
            connection.receive_response
          }.to raise_error(Base::ResponseError, /No response from MCP server/)
        end

        it "raises ResponseError on invalid JSON" do
          stdout.puts("not valid json")
          stdout.rewind

          expect {
            connection.receive_response
          }.to raise_error(Base::ResponseError, /Invalid JSON response/)
        end
      end

      describe "#close" do
        let(:stdin) { double(:stdin, close: nil, closed?: false) }
        let(:stdout) { double(:stdout, close: nil, closed?: false) }
        let(:stderr) { double(:stderr, close: nil, closed?: false) }
        let(:wait_thr) { double(:wait_thr, pid: 12345, alive?: true, join: nil) }

        before do
          allow(Open3).to receive(:popen3).and_return([ stdin, stdout, stderr, wait_thr ])
          connection.connect
        end

        it "closes all streams and waits for process" do
          expect(stdin).to receive(:close)
          expect(stdout).to receive(:close)
          expect(stderr).to receive(:close)
          expect(wait_thr).to receive(:join)

          connection.close
          expect(connection.connected?).to be false
        end

        it "force kills process if it doesn't exit gracefully" do
          allow(wait_thr).to receive(:join).and_raise(Timeout::Error)
          expect(Process).to receive(:kill).with("KILL", 12345)

          connection.close
        end
      end

      describe "#alive?" do
        let(:wait_thr) { double(:wait_thr, pid: 12345, alive?: true) }

        it "returns false when not connected" do
          expect(connection.alive?).to be false
        end

        it "returns true when process is running" do
          allow(Open3).to receive(:popen3).and_return([
            double(:stdin),
            double(:stdout),
            double(:stderr),
            wait_thr
          ])
          connection.connect

          expect(connection.alive?).to be true
        end
      end
    end
  end
end
