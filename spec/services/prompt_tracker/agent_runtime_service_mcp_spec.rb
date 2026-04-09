# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe AgentRuntimeService, type: :service do
    describe "MCP integration" do
      let(:prompt_version) do
        create(:prompt_version,
          system_prompt: "You are a helpful assistant with file system access.",
          user_prompt: "{{message}}",
          model_config: {
            "provider" => "openai",
            "model" => "gpt-4o",
            "temperature" => 0.7
          },
          mcp_servers: [ "filesystem" ])
      end
      let(:deployed_agent) do
        create(:deployed_agent,
          prompt_version: prompt_version,
          agent_type: "conversational",
          status: "active")
      end

      before do
        # Configure MCP servers
        PromptTracker.configure do |config|
          config.mcp_servers = {
            "filesystem" => {
              transport: "stdio",
              command: "npx",
              args: [ "-y", "@modelcontextprotocol/server-filesystem" ],
              env: { "ALLOWED_PATHS" => "/tmp" }
            }
          }
        end
      end

      describe "#initialize" do
        it "initializes MCP manager when MCP servers are configured" do
          service = described_class.new(deployed_agent, "Hello", nil, {})
          expect(service.instance_variable_get(:@mcp_manager)).to be_a(McpClientManager)
        end

        it "does not initialize MCP manager when no MCP servers configured" do
          prompt_version.update!(mcp_servers: [])
          service = described_class.new(deployed_agent, "Hello", nil, {})
          expect(service.instance_variable_get(:@mcp_manager)).to be_nil
        end
      end

      describe "#execute with MCP tools" do
        let(:mcp_manager) { instance_double(McpClientManager) }
        let(:mcp_tools) do
          [
            {
              "name" => "filesystem__read_file",
              "description" => "Read a file from the filesystem",
              "parameters" => {
                "type" => "object",
                "properties" => {
                  "path" => { "type" => "string", "description" => "File path" }
                },
                "required" => [ "path" ]
              }
            }
          ]
        end

        before do
          # Mock MCP manager
          allow(McpClientManager).to receive(:new).and_return(mcp_manager)
          allow(mcp_manager).to receive(:connect_all)
          allow(mcp_manager).to receive(:list_all_tools).and_return(mcp_tools)
          allow(mcp_manager).to receive(:disconnect_all)
        end

        it "includes MCP tools in the tools array" do
          # Mock RubyLlmService to capture the tools
          captured_tools = nil
          allow(LlmClients::RubyLlmService).to receive(:call) do |**args|
            captured_tools = args[:tool_config]["functions"]
            {
              text: "I can help you read files!",
              model: "gpt-4o",
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
              tool_calls: []
            }
          end

          described_class.call(
            deployed_agent: deployed_agent,
            message: "Can you read /tmp/test.txt?"
          )

          expect(captured_tools).to include(
            hash_including("name" => "filesystem__read_file")
          )
        end

        it "executes MCP tools when called by LLM" do
          # Mock MCP tool execution
          allow(mcp_manager).to receive(:call_tool).with("filesystem__read_file", { "path" => "/tmp/test.txt" }).and_return(
            { "content" => [ { "type" => "text", "text" => "File contents here" } ], "isError" => false }
          )

          # Mock RubyLlmService to simulate tool call
          allow(LlmClients::RubyLlmService).to receive(:call) do |**args|
            # Simulate the LLM calling the MCP tool
            executor = args[:function_executor]
            tool_result = executor.call("filesystem__read_file", { "path" => "/tmp/test.txt" })

            {
              text: "The file contains: #{tool_result.dig('content', 0, 'text')}",
              model: "gpt-4o",
              usage: { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 },
              tool_calls: [
                {
                  id: "call_123",
                  function_name: "filesystem__read_file",
                  arguments: { "path" => "/tmp/test.txt" }
                }
              ]
            }
          end

          result = described_class.call(
            deployed_agent: deployed_agent,
            message: "Read /tmp/test.txt"
          )

          expect(result.success?).to be true
          expect(mcp_manager).to have_received(:call_tool).with("filesystem__read_file", { "path" => "/tmp/test.txt" })
        end

        it "creates FunctionExecution record for MCP tool calls" do
          # Mock MCP tool execution
          allow(mcp_manager).to receive(:call_tool).and_return(
            { "content" => [ { "type" => "text", "text" => "Success" } ], "isError" => false }
          )

          # Mock RubyLlmService
          allow(LlmClients::RubyLlmService).to receive(:call) do |**args|
            executor = args[:function_executor]
            executor.call("filesystem__read_file", { "path" => "/tmp/test.txt" })

            {
              text: "File read successfully",
              model: "gpt-4o",
              usage: { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 },
              tool_calls: [
                {
                  id: "call_123",
                  function_name: "filesystem__read_file",
                  arguments: { "path" => "/tmp/test.txt" }
                }
              ]
            }
          end

          expect {
            described_class.call(
              deployed_agent: deployed_agent,
              message: "Read /tmp/test.txt"
            )
          }.to change(FunctionExecution, :count).by(1)

          execution = FunctionExecution.last
          expect(execution.function_name).to eq("filesystem__read_file")
          expect(execution.function_definition_id).to be_nil  # MCP tools are virtual
          expect(execution.success).to be true
        end

        it "cleans up MCP connections after execution" do
          allow(LlmClients::RubyLlmService).to receive(:call).and_return(
            {
              text: "Done",
              model: "gpt-4o",
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
              tool_calls: []
            }
          )

          described_class.call(
            deployed_agent: deployed_agent,
            message: "Hello"
          )

          expect(mcp_manager).to have_received(:disconnect_all)
        end

        it "cleans up MCP connections even when execution fails" do
          allow(LlmClients::RubyLlmService).to receive(:call).and_raise(StandardError, "LLM error")

          expect {
            described_class.call(
              deployed_agent: deployed_agent,
              message: "Hello"
            )
          }.not_to raise_error

          expect(mcp_manager).to have_received(:disconnect_all)
        end
      end

      describe "MCP tool error handling" do
        let(:mcp_manager) { instance_double(McpClientManager) }

        before do
          allow(McpClientManager).to receive(:new).and_return(mcp_manager)
          allow(mcp_manager).to receive(:connect_all)
          allow(mcp_manager).to receive(:list_all_tools).and_return([])
          allow(mcp_manager).to receive(:disconnect_all)
        end

        it "handles MCP tool execution errors gracefully" do
          allow(mcp_manager).to receive(:call_tool).and_raise(StandardError, "MCP error")

          allow(LlmClients::RubyLlmService).to receive(:call) do |**args|
            executor = args[:function_executor]
            result = executor.call("filesystem__read_file", { "path" => "/tmp/test.txt" })

            {
              text: "Error occurred",
              model: "gpt-4o",
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
              tool_calls: []
            }
          end

          result = described_class.call(
            deployed_agent: deployed_agent,
            message: "Read file"
          )

          expect(result.success?).to be true  # Service should not fail
        end
      end
    end
  end
end
