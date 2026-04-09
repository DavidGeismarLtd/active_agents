# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe McpClientManager do
    let(:filesystem_config) do
      {
        transport: "stdio",
        command: "npx",
        args: [ "-y", "@modelcontextprotocol/server-filesystem" ],
        env: { "ALLOWED_PATHS" => "/tmp" }
      }
    end

    let(:weather_config) do
      {
        transport: "http",
        url: "https://weather.example.com/api",
        headers: { "Authorization" => "Bearer test-token" }
      }
    end

    before do
      PromptTracker.configure do |config|
        config.mcp_servers = {
          "filesystem" => filesystem_config,
          "weather" => weather_config
        }
      end
    end

    describe "#initialize" do
      it "accepts array of server names" do
        manager = described_class.new([ "filesystem", "weather" ])
        expect(manager.server_names).to eq([ "filesystem", "weather" ])
      end

      it "accepts single server name" do
        manager = described_class.new("filesystem")
        expect(manager.server_names).to eq([ "filesystem" ])
      end

      it "initializes empty connections hash" do
        manager = described_class.new([ "filesystem" ])
        expect(manager.connections).to eq({})
      end

      it "initializes empty tools cache" do
        manager = described_class.new([ "filesystem" ])
        expect(manager.tools_cache).to eq({})
      end
    end

    describe "#connect_all" do
      let(:manager) { described_class.new([ "filesystem" ]) }
      let(:connection_mock) { instance_double(McpConnection::Stdio, connect: nil) }

      it "creates and connects to all configured servers" do
        expect(McpConnection::Stdio).to receive(:new).with(filesystem_config).and_return(connection_mock)
        expect(connection_mock).to receive(:connect)

        result = manager.connect_all

        expect(result).to eq({
          "filesystem" => { success: true }
        })
        expect(manager.connections["filesystem"]).to eq(connection_mock)
      end

      it "raises ManagerError when connection fails" do
        allow(McpConnection::Stdio).to receive(:new).and_raise(StandardError, "Connection failed")

        expect {
          manager.connect_all
        }.to raise_error(McpClientManager::ManagerError, /Failed to connect to MCP server 'filesystem'/)
      end

      it "creates HTTP connection for http transport" do
        manager = described_class.new([ "weather" ])
        http_connection = instance_double(McpConnection::Http, connect: nil)

        expect(McpConnection::Http).to receive(:new).with(weather_config).and_return(http_connection)
        expect(http_connection).to receive(:connect)

        manager.connect_all
      end

      it "raises ManagerError for unconfigured server" do
        manager = described_class.new([ "nonexistent" ])

        expect {
          manager.connect_all
        }.to raise_error(McpClientManager::ManagerError, /Failed to connect to MCP server 'nonexistent'/)
      end
    end

    describe "#list_all_tools" do
      let(:manager) { described_class.new([ "filesystem" ]) }
      let(:connection_mock) { instance_double(McpConnection::Stdio) }

      let(:mcp_tools_response) do
        {
          "tools" => [
            {
              "name" => "read_file",
              "description" => "Read a file",
              "inputSchema" => {
                "type" => "object",
                "properties" => {
                  "path" => { "type" => "string" }
                },
                "required" => [ "path" ]
              }
            },
            {
              "name" => "write_file",
              "description" => "Write a file",
              "inputSchema" => {
                "type" => "object",
                "properties" => {
                  "path" => { "type" => "string" },
                  "content" => { "type" => "string" }
                }
              }
            }
          ]
        }
      end

      before do
        allow(McpConnection::Stdio).to receive(:new).and_return(connection_mock)
        allow(connection_mock).to receive(:connect)
        manager.connect_all
      end

      it "fetches tools from all connected servers" do
        expect(connection_mock).to receive(:call).with("tools/list", {}).and_return(mcp_tools_response)

        tools = manager.list_all_tools

        expect(tools.length).to eq(2)
      end

      it "prefixes tool names with server name" do
        allow(connection_mock).to receive(:call).and_return(mcp_tools_response)

        tools = manager.list_all_tools

        expect(tools[0]["name"]).to eq("filesystem__read_file")
        expect(tools[1]["name"]).to eq("filesystem__write_file")
      end

      it "converts MCP tool schema to LLM format" do
        allow(connection_mock).to receive(:call).and_return(mcp_tools_response)

        tools = manager.list_all_tools

        expect(tools[0]).to include(
          "name" => "filesystem__read_file",
          "description" => "Read a file",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "path" => { "type" => "string" }
            },
            "required" => [ "path" ]
          }
        )
      end

      it "caches tools for each server" do
        allow(connection_mock).to receive(:call).and_return(mcp_tools_response)

        manager.list_all_tools

        expect(manager.tools_cache["filesystem"]).to eq(mcp_tools_response["tools"])
      end

      it "raises ManagerError when tool discovery fails" do
        allow(connection_mock).to receive(:call).and_raise(StandardError, "Discovery failed")

        expect {
          manager.list_all_tools
        }.to raise_error(McpClientManager::ManagerError, /Failed to list tools from 'filesystem'/)
      end
    end

    describe "#call_tool" do
      let(:manager) { described_class.new([ "filesystem" ]) }
      let(:connection_mock) { instance_double(McpConnection::Stdio) }

      before do
        allow(McpConnection::Stdio).to receive(:new).and_return(connection_mock)
        allow(connection_mock).to receive(:connect)
        manager.connect_all
      end

      it "routes tool call to correct server" do
        expect(connection_mock).to receive(:call).with(
          "tools/call",
          {
            name: "read_file",
            arguments: { "path" => "/tmp/test.txt" }
          }
        ).and_return({ "content" => "file contents" })

        result = manager.call_tool("filesystem__read_file", { "path" => "/tmp/test.txt" })

        expect(result).to eq({ "content" => "file contents" })
      end

      it "parses prefixed tool name correctly" do
        expect(connection_mock).to receive(:call).with(
          "tools/call",
          {
            name: "write_file",
            arguments: { "path" => "/tmp/test.txt", "content" => "data" }
          }
        ).and_return({ "success" => true })

        manager.call_tool("filesystem__write_file", { "path" => "/tmp/test.txt", "content" => "data" })
      end

      it "raises ServerNotFoundError when server not connected" do
        expect {
          manager.call_tool("nonexistent__tool", {})
        }.to raise_error(McpClientManager::ServerNotFoundError, /MCP server 'nonexistent' not connected/)
      end

      it "raises ToolNotFoundError for invalid tool name format" do
        expect {
          manager.call_tool("invalid_tool_name", {})
        }.to raise_error(McpClientManager::ToolNotFoundError, /Invalid MCP tool name format/)
      end

      it "raises ManagerError when tool execution fails" do
        allow(connection_mock).to receive(:call).and_raise(
          McpConnection::Base::ResponseError,
          "Tool execution failed"
        )

        expect {
          manager.call_tool("filesystem__read_file", { "path" => "/tmp/test.txt" })
        }.to raise_error(McpClientManager::ManagerError, /Tool execution failed/)
      end
    end

    describe "#disconnect_all" do
      let(:manager) { described_class.new([ "filesystem", "weather" ]) }
      let(:filesystem_connection) { instance_double(McpConnection::Stdio, connect: nil, close: nil) }
      let(:weather_connection) { instance_double(McpConnection::Http, connect: nil, close: nil) }

      before do
        allow(McpConnection::Stdio).to receive(:new).and_return(filesystem_connection)
        allow(McpConnection::Http).to receive(:new).and_return(weather_connection)
        manager.connect_all
      end

      it "closes all connections" do
        expect(filesystem_connection).to receive(:close)
        expect(weather_connection).to receive(:close)

        manager.disconnect_all
      end

      it "clears connections hash" do
        manager.disconnect_all

        expect(manager.connections).to be_empty
      end

      it "clears tools cache" do
        manager.instance_variable_set(:@tools_cache, { "filesystem" => [] })

        manager.disconnect_all

        expect(manager.tools_cache).to be_empty
      end

      it "handles errors gracefully when closing connections" do
        allow(filesystem_connection).to receive(:close).and_raise(StandardError, "Close failed")

        expect {
          manager.disconnect_all
        }.not_to raise_error

        expect(manager.connections).to be_empty
      end
    end

    describe "private methods" do
      let(:manager) { described_class.new([ "filesystem" ]) }

      describe "#build_prefixed_tool_name" do
        it "builds prefixed name with double underscore" do
          result = manager.send(:build_prefixed_tool_name, "filesystem", "read_file")
          expect(result).to eq("filesystem__read_file")
        end
      end

      describe "#parse_tool_name" do
        it "parses prefixed name into server and tool" do
          server, tool = manager.send(:parse_tool_name, "filesystem__read_file")
          expect(server).to eq("filesystem")
          expect(tool).to eq("read_file")
        end

        it "handles tool names with underscores" do
          server, tool = manager.send(:parse_tool_name, "filesystem__read_text_file")
          expect(server).to eq("filesystem")
          expect(tool).to eq("read_text_file")
        end

        it "raises ToolNotFoundError for invalid format" do
          expect {
            manager.send(:parse_tool_name, "invalid")
          }.to raise_error(McpClientManager::ToolNotFoundError)
        end
      end

      describe "#convert_tool_to_llm_format" do
        it "converts MCP tool to LLM format" do
          mcp_tool = {
            "name" => "read_file",
            "description" => "Read a file",
            "inputSchema" => {
              "type" => "object",
              "properties" => { "path" => { "type" => "string" } }
            }
          }

          result = manager.send(:convert_tool_to_llm_format, "filesystem", mcp_tool)

          expect(result).to eq({
            "name" => "filesystem__read_file",
            "description" => "Read a file",
            "parameters" => {
              "type" => "object",
              "properties" => { "path" => { "type" => "string" } }
            }
          })
        end

        it "provides default description when missing" do
          mcp_tool = { "name" => "test_tool" }

          result = manager.send(:convert_tool_to_llm_format, "server", mcp_tool)

          expect(result["description"]).to eq("MCP tool from server")
        end

        it "provides default parameters when inputSchema missing" do
          mcp_tool = { "name" => "test_tool" }

          result = manager.send(:convert_tool_to_llm_format, "server", mcp_tool)

          expect(result["parameters"]).to eq({ "type" => "object", "properties" => {} })
        end
      end
    end
  end
end
