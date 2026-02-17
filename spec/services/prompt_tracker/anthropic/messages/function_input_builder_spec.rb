# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Anthropic
    module Messages
      RSpec.describe FunctionInputBuilder, type: :service do
        let(:executor) { instance_double(Openai::Responses::FunctionExecutor) }
        let(:builder) { described_class.new(executor: executor) }

        describe "#build_tool_result_message" do
          let(:tool_calls) do
            [
              {
                id: "toolu_01abc123",
                function_name: "get_weather",
                arguments: { location: "Berlin" }
              }
            ]
          end

          before do
            allow(executor).to receive(:execute).and_return('{"temperature": 72, "condition": "sunny"}')
          end

          it "returns a user message with role" do
            result = builder.build_tool_result_message(tool_calls)

            expect(result[:role]).to eq("user")
          end

          it "returns content array with tool_result blocks" do
            result = builder.build_tool_result_message(tool_calls)

            expect(result[:content]).to be_an(Array)
            expect(result[:content].length).to eq(1)
          end

          it "builds correct tool_result format" do
            result = builder.build_tool_result_message(tool_calls)
            tool_result = result[:content].first

            expect(tool_result[:type]).to eq("tool_result")
            expect(tool_result[:tool_use_id]).to eq("toolu_01abc123")
            expect(tool_result[:content]).to eq('{"temperature": 72, "condition": "sunny"}')
          end

          it "calls executor for each tool call" do
            builder.build_tool_result_message(tool_calls)

            expect(executor).to have_received(:execute).with(tool_calls.first)
          end

          context "with multiple tool calls" do
            let(:tool_calls) do
              [
                { id: "toolu_01", function_name: "get_weather", arguments: { location: "Berlin" } },
                { id: "toolu_02", function_name: "get_time", arguments: { timezone: "CET" } }
              ]
            end

            before do
              allow(executor).to receive(:execute).with(tool_calls[0]).and_return('{"temp": 20}')
              allow(executor).to receive(:execute).with(tool_calls[1]).and_return('{"time": "14:00"}')
            end

            it "builds tool_result for each call" do
              result = builder.build_tool_result_message(tool_calls)

              expect(result[:content].length).to eq(2)
              expect(result[:content][0][:tool_use_id]).to eq("toolu_01")
              expect(result[:content][1][:tool_use_id]).to eq("toolu_02")
            end

            it "preserves order of results" do
              result = builder.build_tool_result_message(tool_calls)

              expect(result[:content][0][:content]).to eq('{"temp": 20}')
              expect(result[:content][1][:content]).to eq('{"time": "14:00"}')
            end
          end
        end

        describe "#build_tool_result_blocks" do
          let(:tool_calls) do
            [
              { id: "toolu_123", function_name: "test_func", arguments: {} }
            ]
          end

          before do
            allow(executor).to receive(:execute).and_return("result")
          end

          it "returns an array of tool_result blocks" do
            blocks = builder.build_tool_result_blocks(tool_calls)

            expect(blocks).to be_an(Array)
            expect(blocks.first[:type]).to eq("tool_result")
          end
        end

        describe "output formatting" do
          let(:tool_calls) do
            [ { id: "toolu_123", function_name: "test", arguments: {} } ]
          end

          context "when executor returns a Hash" do
            before do
              allow(executor).to receive(:execute).and_return({ key: "value" })
            end

            it "converts Hash to JSON string" do
              result = builder.build_tool_result_message(tool_calls)

              expect(result[:content].first[:content]).to eq('{"key":"value"}')
            end
          end

          context "when executor returns a String" do
            before do
              allow(executor).to receive(:execute).and_return("plain text result")
            end

            it "uses the string as-is" do
              result = builder.build_tool_result_message(tool_calls)

              expect(result[:content].first[:content]).to eq("plain text result")
            end
          end
        end
      end
    end
  end
end
