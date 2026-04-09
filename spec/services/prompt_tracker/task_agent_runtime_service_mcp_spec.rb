# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::TaskAgentRuntimeService, "MCP Integration", type: :service do
  let(:prompt_version) do
    create(:prompt_version,
           system_prompt: "You are a helpful task automation assistant.",
           model_config: {
             provider: "openai",
             model: "gpt-4",
             temperature: 0.7
           },
           mcp_servers: [ "filesystem", "github" ])
  end

  let(:task_agent) do
    create(:deployed_agent,
           :task_agent,
           prompt_version: prompt_version,
           task_config: {
             initial_prompt: "Read the file at /tmp/test.txt",
             execution: {
               max_iterations: 3,
               timeout_seconds: 60
             }
           })
  end

  let(:task_run) { create(:task_run, deployed_agent: task_agent) }

  describe "MCP manager initialization" do
    it "initializes MCP manager when servers are configured" do
      # Mock MCP manager
      mock_manager = instance_double(PromptTracker::McpClientManager)
      allow(PromptTracker::McpClientManager).to receive(:new).with([ "filesystem", "github" ]).and_return(mock_manager)
      allow(mock_manager).to receive(:connect_all).and_return({ "filesystem" => { success: true }, "github" => { success: true } })
      allow(mock_manager).to receive(:list_all_tools).and_return([])
      allow(mock_manager).to receive(:disconnect_all)

      # Mock LLM to return immediately
      mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:call).and_return(
        PromptTracker::NormalizedLlmResponse.new(
          text: "Done",
          model: "gpt-4",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          tool_calls: [],
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: {},
          raw_response: nil
        )
      )

      described_class.call(task_agent: task_agent, task_run: task_run)

      expect(PromptTracker::McpClientManager).to have_received(:new).with([ "filesystem", "github" ])
      expect(mock_manager).to have_received(:connect_all)
      expect(mock_manager).to have_received(:disconnect_all)
    end

    it "does not initialize MCP manager when no servers configured" do
      prompt_version.update!(mcp_servers: [])

      allow(PromptTracker::McpClientManager).to receive(:new)

      # Mock LLM to return immediately
      mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:call).and_return(
        PromptTracker::NormalizedLlmResponse.new(
          text: "Done",
          model: "gpt-4",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          tool_calls: [],
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: {},
          raw_response: nil
        )
      )

      described_class.call(task_agent: task_agent, task_run: task_run)

      expect(PromptTracker::McpClientManager).not_to have_received(:new)
    end

    it "handles MCP manager initialization errors gracefully" do
      allow(PromptTracker::McpClientManager).to receive(:new).and_raise(StandardError.new("Connection failed"))

      # Mock LLM to return immediately
      mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:call).and_return(
        PromptTracker::NormalizedLlmResponse.new(
          text: "Done",
          model: "gpt-4",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          tool_calls: [],
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: {},
          raw_response: nil
        )
      )

      result = described_class.call(task_agent: task_agent, task_run: task_run)

      # Should still complete successfully even if MCP fails to initialize
      expect(result[:success]).to be true
    end
  end

  describe "MCP tool discovery" do
    it "includes MCP tools in the tools array" do
      # Mock MCP manager
      mock_manager = instance_double(PromptTracker::McpClientManager)
      allow(PromptTracker::McpClientManager).to receive(:new).and_return(mock_manager)
      allow(mock_manager).to receive(:connect_all).and_return({})
      allow(mock_manager).to receive(:list_all_tools).and_return([
        {
          "name" => "filesystem__read_file",
          "description" => "Read a file from the filesystem",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "path" => { "type" => "string" }
            }
          }
        }
      ])
      allow(mock_manager).to receive(:disconnect_all)

      # Capture the tool_config passed to LLM
      captured_tool_config = nil
      mock_service = instance_double(PromptTracker::LlmClients::RubyLlmService)
      allow(PromptTracker::LlmClients::RubyLlmService).to receive(:new) do |**args|
        captured_tool_config = args[:tool_config]
        mock_service
      end
      allow(mock_service).to receive(:call).and_return(
        PromptTracker::NormalizedLlmResponse.new(
          text: "Done",
          model: "gpt-4",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
          tool_calls: [],
          file_search_results: [],
          web_search_results: [],
          code_interpreter_results: [],
          api_metadata: {},
          raw_response: nil
        )
      )

      described_class.call(task_agent: task_agent, task_run: task_run)

      # The tools are passed in tool_config["functions"]
      functions = captured_tool_config["functions"]
      expect(functions).to include(
        hash_including(
          "name" => "filesystem__read_file",
          "description" => "Read a file from the filesystem"
        )
      )
    end
  end

  describe "MCP helper methods" do
    let(:service) { described_class.new(task_agent: task_agent, task_run: task_run) }

    describe "#mcp_tool?" do
      it "returns true for MCP tool names with double underscore when manager exists" do
        mock_manager = instance_double(PromptTracker::McpClientManager)
        service.instance_variable_set(:@mcp_manager, mock_manager)

        expect(service.send(:mcp_tool?, "filesystem__read_file")).to be true
        expect(service.send(:mcp_tool?, "github__create_issue")).to be true
      end

      it "returns false for regular function names" do
        mock_manager = instance_double(PromptTracker::McpClientManager)
        service.instance_variable_set(:@mcp_manager, mock_manager)

        expect(service.send(:mcp_tool?, "get_weather")).to be false
        expect(service.send(:mcp_tool?, "create_plan")).to be false
      end

      it "returns false when MCP manager is not initialized" do
        service.instance_variable_set(:@mcp_manager, nil)
        expect(service.send(:mcp_tool?, "filesystem__read_file")).to be false
      end
    end

    describe "#execute_mcp_tool" do
      let(:mock_manager) { instance_double(PromptTracker::McpClientManager) }

      before do
        service.instance_variable_set(:@mcp_manager, mock_manager)
      end

      it "calls the MCP manager and creates FunctionExecution" do
        allow(mock_manager).to receive(:call_tool).with("filesystem__read_file", { "path" => "/tmp/test.txt" }).and_return(
          { "content" => [ { "type" => "text", "text" => "File contents" } ], "isError" => false }
        )

        expect {
          result = service.send(:execute_mcp_tool, "filesystem__read_file", { "path" => "/tmp/test.txt" })
          expect(result["isError"]).to be false
        }.to change(PromptTracker::FunctionExecution, :count).by(1)

        execution = PromptTracker::FunctionExecution.last
        expect(execution.function_definition).to be_nil
          expect(execution.function_name).to eq("filesystem__read_file")
        expect(execution.success).to be true
        expect(execution.deployed_agent).to eq(task_agent)
        expect(execution.task_run).to eq(task_run)
      end

      it "handles MCP tool errors" do
        allow(mock_manager).to receive(:call_tool).and_return(
          { "content" => [ { "type" => "text", "text" => "Access denied" } ], "isError" => true }
        )

        expect {
          result = service.send(:execute_mcp_tool, "filesystem__read_file", { "path" => "/etc/passwd" })
          expect(result["isError"]).to be true
        }.to change(PromptTracker::FunctionExecution, :count).by(1)

        execution = PromptTracker::FunctionExecution.last
        expect(execution.success).to be false
        expect(execution.error_message).to eq("Access denied")
          expect(execution.function_name).to eq("filesystem__read_file")
      end
    end

    describe "#fetch_mcp_tools" do
      it "returns tools from MCP manager" do
        mock_manager = instance_double(PromptTracker::McpClientManager)
        service.instance_variable_set(:@mcp_manager, mock_manager)

        allow(mock_manager).to receive(:list_all_tools).and_return([
          { "name" => "filesystem__read_file", "description" => "Read a file" }
        ])

        tools = service.send(:fetch_mcp_tools)
        expect(tools).to eq([ { "name" => "filesystem__read_file", "description" => "Read a file" } ])
      end

      it "returns empty array when MCP manager is nil" do
        service.instance_variable_set(:@mcp_manager, nil)
        expect(service.send(:fetch_mcp_tools)).to eq([])
      end
    end
  end
end
