# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module LlmResponseNormalizers
    RSpec.describe RubyLlm, type: :service do
      describe ".normalize" do
        # Create a mock RubyLLM::Message response
        def create_mock_response(attrs = {})
          defaults = {
            content: "Hello! How can I help you?",
            input_tokens: 10,
            output_tokens: 20,
            model_id: "claude-3-5-sonnet-20241022",
            id: "msg_123",
            stop_reason: "end_turn",
            tool_calls: nil
          }

          double("RubyLLM::Message", defaults.merge(attrs)).tap do |mock|
            mock_attrs = defaults.merge(attrs)
            allow(mock).to receive(:respond_to?).with(:tool_calls).and_return(true)
            allow(mock).to receive(:respond_to?).with(:id).and_return(mock_attrs[:id].present?)
            allow(mock).to receive(:respond_to?).with(:stop_reason).and_return(mock_attrs[:stop_reason].present?)
          end
        end

        context "with basic text response" do
          let(:mock_response) { create_mock_response }

          it "extracts text content" do
            result = described_class.normalize(mock_response)
            expect(result.text).to eq("Hello! How can I help you?")
          end

          it "extracts usage information" do
            result = described_class.normalize(mock_response)
            expect(result.usage[:prompt_tokens]).to eq(10)
            expect(result.usage[:completion_tokens]).to eq(20)
            expect(result.usage[:total_tokens]).to eq(30)
          end

          it "extracts model" do
            result = described_class.normalize(mock_response)
            expect(result.model).to eq("claude-3-5-sonnet-20241022")
          end

          it "extracts api_metadata" do
            result = described_class.normalize(mock_response)
            expect(result.api_metadata[:message_id]).to eq("msg_123")
            expect(result.api_metadata[:stop_reason]).to eq("end_turn")
          end

          it "stores raw_response" do
            result = described_class.normalize(mock_response)
            expect(result.raw_response).to eq(mock_response)
          end

          it "returns empty arrays for unsupported features" do
            result = described_class.normalize(mock_response)
            expect(result.file_search_results).to eq([])
            expect(result.web_search_results).to eq([])
            expect(result.code_interpreter_results).to eq([])
            expect(result.tool_calls).to eq([])
          end
        end

        context "with tool calls in response" do
          # RubyLLM stores tool_calls as a hash: { "id" => ToolCall object }
          def create_tool_call(id:, name:, arguments:)
            double("RubyLLM::ToolCall", id: id, name: name, arguments: arguments)
          end

          let(:tool_call) { create_tool_call(id: "toolu_01", name: "get_weather", arguments: { "location" => "Berlin" }) }
          let(:mock_response) do
            create_mock_response(
              tool_calls: { "toolu_01" => tool_call }
            )
          end

          it "extracts tool calls" do
            result = described_class.normalize(mock_response)

            expect(result.tool_calls.length).to eq(1)
            expect(result.tool_calls[0][:id]).to eq("toolu_01")
            expect(result.tool_calls[0][:type]).to eq("function")
            expect(result.tool_calls[0][:function_name]).to eq("get_weather")
            expect(result.tool_calls[0][:arguments]).to eq({ "location" => "Berlin" })
          end
        end

        context "with multiple tool calls" do
          def create_tool_call(id:, name:, arguments:)
            double("RubyLLM::ToolCall", id: id, name: name, arguments: arguments)
          end

          let(:tool_call_1) { create_tool_call(id: "toolu_01", name: "get_weather", arguments: { "location" => "Berlin" }) }
          let(:tool_call_2) { create_tool_call(id: "toolu_02", name: "get_time", arguments: { "timezone" => "Europe/Berlin" }) }
          let(:mock_response) do
            create_mock_response(
              tool_calls: {
                "toolu_01" => tool_call_1,
                "toolu_02" => tool_call_2
              }
            )
          end

          it "extracts all tool calls" do
            result = described_class.normalize(mock_response)

            expect(result.tool_calls.length).to eq(2)
            function_names = result.tool_calls.map { |tc| tc[:function_name] }
            expect(function_names).to include("get_weather", "get_time")
          end
        end

        context "with chat_messages containing tool calls" do
          def create_tool_call(id:, name:, arguments:)
            double("RubyLLM::ToolCall", id: id, name: name, arguments: arguments)
          end

          def create_chat_message(role:, tool_calls: nil)
            double("RubyLLM::Message", role: role, tool_calls: tool_calls)
          end

          let(:tool_call_1) { create_tool_call(id: "toolu_01", name: "search_kb", arguments: { "query" => "iPad boot" }) }
          let(:tool_call_2) { create_tool_call(id: "toolu_02", name: "search_kb", arguments: { "query" => "iPad startup" }) }

          let(:chat_messages) do
            [
              create_chat_message(role: :system, tool_calls: nil),
              create_chat_message(role: :user, tool_calls: nil),
              create_chat_message(role: :assistant, tool_calls: { "toolu_01" => tool_call_1 }),
              create_chat_message(role: :tool, tool_calls: nil),
              create_chat_message(role: :assistant, tool_calls: { "toolu_02" => tool_call_2 }),
              create_chat_message(role: :tool, tool_calls: nil),
              create_chat_message(role: :assistant, tool_calls: nil) # Final response
            ]
          end

          let(:mock_response) do
            # Final response has no tool_calls (tools were auto-executed)
            create_mock_response(tool_calls: nil)
          end

          it "extracts tool calls from conversation history" do
            result = described_class.normalize(mock_response, chat_messages: chat_messages)

            expect(result.tool_calls.length).to eq(2)
            expect(result.tool_calls[0][:id]).to eq("toolu_01")
            expect(result.tool_calls[0][:function_name]).to eq("search_kb")
            expect(result.tool_calls[1][:id]).to eq("toolu_02")
            expect(result.tool_calls[1][:function_name]).to eq("search_kb")
          end

          it "prefers chat_messages over response.tool_calls when both present" do
            # Even if response has tool_calls, chat_messages takes precedence
            response_with_tools = create_mock_response(
              tool_calls: { "other" => create_tool_call(id: "other", name: "other_func", arguments: {}) }
            )

            result = described_class.normalize(response_with_tools, chat_messages: chat_messages)

            # Should extract from history, not from response
            expect(result.tool_calls.length).to eq(2)
            expect(result.tool_calls.map { |tc| tc[:function_name] }).to all(eq("search_kb"))
          end
        end

        context "with nil content" do
          let(:mock_response) { create_mock_response(content: nil) }

          it "returns empty string for text" do
            result = described_class.normalize(mock_response)
            expect(result.text).to eq("")
          end
        end

        context "with nil tokens" do
          let(:mock_response) { create_mock_response(input_tokens: nil, output_tokens: nil) }

          it "returns zero for usage tokens" do
            result = described_class.normalize(mock_response)
            expect(result.usage[:prompt_tokens]).to eq(0)
            expect(result.usage[:completion_tokens]).to eq(0)
            expect(result.usage[:total_tokens]).to eq(0)
          end
        end
      end
    end
  end
end
