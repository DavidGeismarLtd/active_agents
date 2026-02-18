# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    module Responses
      RSpec.describe FunctionCallHandler, type: :service do
        let(:model) { "gpt-4o" }
        let(:tools) { [ :web_search, :functions ] }
        let(:tool_config) { { "functions" => [] } }
        let(:use_real_llm) { false }
        let(:handler) do
          described_class.new(
            model: model,
            tools: tools,
            tool_config: tool_config,
            use_real_llm: use_real_llm
          )
        end

        describe "#process_with_function_handling" do
          context "when response has no function calls" do
            let(:initial_response) do
              {
                text: "Final response",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                tool_calls: []
              }
            end

            it "returns the initial response immediately" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              expect(result[:final_response]).to eq(initial_response)
              expect(result[:all_tool_calls]).to eq([])
              expect(result[:all_responses]).to eq([ initial_response ])
            end
          end

          context "when response has function calls" do
            let(:initial_response) do
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
                ]
              }
            end

            before do
              # Mock the second response (after function execution)
              allow(handler).to receive(:call_api_with_function_outputs).and_return(
                {
                  text: "The weather is sunny",
                  response_id: "resp_124",
                  usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                  tool_calls: []
                }
              )
            end

            it "executes function calls and returns final response" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              expect(result[:final_response][:text]).to eq("The weather is sunny")
              expect(result[:all_tool_calls].length).to eq(1)
              expect(result[:all_tool_calls][0][:function_name]).to eq("get_weather")
              expect(result[:all_responses].length).to eq(2)
            end

            it "calls API with paired function_call and function_call_output items" do
              handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              # The Responses API requires BOTH the original function_call AND the function_call_output
              expect(handler).to have_received(:call_api_with_function_outputs).with(
                [
                  hash_including(
                    type: "function_call",
                    call_id: "call_1",
                    name: "get_weather"
                  ),
                  hash_including(
                    type: "function_call_output",
                    call_id: "call_1"
                  )
                ],
                "resp_123"
              )
            end
          end

          context "when hitting iteration limit" do
            let(:response_with_calls) do
              {
                text: "",
                response_id: "resp_#{SecureRandom.hex(4)}",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_#{SecureRandom.hex(4)}", function_name: "test", arguments: {} }
                ]
              }
            end

            before do
              # Always return a response with function calls to trigger infinite loop
              allow(handler).to receive(:call_api_with_function_outputs).and_return(response_with_calls)
              allow(Rails.logger).to receive(:warn)
            end

            it "stops after MAX_ITERATIONS and logs warning" do
              result = handler.process_with_function_handling(
                initial_response: response_with_calls,
                previous_response_id: "resp_000",
                turn: 1
              )

              # Should have initial response + MAX_ITERATIONS additional responses
              expect(result[:all_responses].length).to eq(described_class::MAX_ITERATIONS + 1)
              expect(Rails.logger).to have_received(:warn).with(
                /\[FunctionCallHandler\].*Iteration limit.*reached/
              )
            end

            it "includes pending tool calls in all_tool_calls when limit is hit" do
              result = handler.process_with_function_handling(
                initial_response: response_with_calls,
                previous_response_id: "resp_000",
                turn: 1
              )

              # Should have MAX_ITERATIONS tool calls from inside the loop
              # PLUS 1 final pending tool call from the response that triggered the exit
              expect(result[:all_tool_calls].length).to eq(described_class::MAX_ITERATIONS + 1)

              # The final response should still have tool_calls present
              expect(result[:final_response][:tool_calls]).to be_present
            end
          end

          context "when use_real_llm is true" do
            let(:use_real_llm) { true }
            let(:initial_response) do
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
                ]
              }
            end

            before do
              allow(LlmClients::OpenaiResponseService).to receive(:call_with_context).and_return(
                {
                  text: "The weather is sunny",
                  response_id: "resp_124",
                  usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                  tool_calls: []
                }
              )
            end

            it "calls LlmClients::OpenaiResponseService with function outputs" do
              handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              expect(LlmClients::OpenaiResponseService).to have_received(:call_with_context)
            end
          end
        end

        describe "delegation to FunctionInputBuilder" do
          # These tests verify that the handler correctly integrates with FunctionInputBuilder
          # Detailed tests for input building are in function_input_builder_spec.rb

          it "uses FunctionInputBuilder to build continuation input" do
            initial_response = {
              text: "",
              response_id: "resp_123",
              usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
              tool_calls: [
                { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
              ]
            }

            allow(handler).to receive(:call_api_with_function_outputs).and_return(
              { text: "Done", response_id: "resp_124", usage: {}, tool_calls: [] }
            )

            handler.process_with_function_handling(
              initial_response: initial_response,
              previous_response_id: "resp_000"
            )

            # Verify the input_builder was used correctly by checking the API call
            expect(handler).to have_received(:call_api_with_function_outputs).with(
              array_including(
                hash_including(type: "function_call", name: "get_weather"),
                hash_including(type: "function_call_output", call_id: "call_1")
              ),
              "resp_123"
            )
          end
        end

        describe "custom mock_function_outputs integration" do
          # These tests verify that custom mocks are passed through to the executor
          # Detailed tests for function execution are in function_executor_spec.rb

          let(:mock_function_outputs) do
            {
              "get_weather" => { temperature: 72, condition: "Sunny" }
            }
          end

          let(:handler_with_mocks) do
            described_class.new(
              model: model,
              tools: tools,
              tool_config: tool_config,
              use_real_llm: use_real_llm,
              mock_function_outputs: mock_function_outputs
            )
          end

          it "uses custom mock outputs in the continuation input" do
            initial_response = {
              text: "",
              response_id: "resp_123",
              usage: {},
              tool_calls: [
                { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
              ]
            }

            allow(handler_with_mocks).to receive(:call_api_with_function_outputs).and_return(
              { text: "Done", response_id: "resp_124", usage: {}, tool_calls: [] }
            )

            handler_with_mocks.process_with_function_handling(
              initial_response: initial_response,
              previous_response_id: "resp_000"
            )

            # Verify the custom mock was used in the output
            expect(handler_with_mocks).to have_received(:call_api_with_function_outputs) do |input_items, _|
              output_item = input_items.find { |item| item[:type] == "function_call_output" }
              parsed = JSON.parse(output_item[:output])
              expect(parsed["temperature"]).to eq(72)
              expect(parsed["condition"]).to eq("Sunny")
            end
          end
        end

        describe "logging" do
          let(:initial_response) do
            {
              text: "",
              response_id: "resp_123",
              usage: {},
              tool_calls: [
                { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
              ]
            }
          end

          before do
            allow(handler).to receive(:call_api_with_function_outputs).and_return(
              { text: "Done", response_id: "resp_124", usage: {}, tool_calls: [] }
            )
            allow(Rails.logger).to receive(:debug).and_yield
          end

          it "logs function calls received" do
            expect(Rails.logger).to receive(:debug) do |&block|
              message = block.call
              expect(message).to include("FunctionCallHandler")
              expect(message).to include("get_weather")
            end.at_least(:once)

            handler.process_with_function_handling(
              initial_response: initial_response,
              previous_response_id: "resp_000"
            )
          end

          it "logs continuation input" do
            expect(Rails.logger).to receive(:debug) do |&block|
              message = block.call
              expect(message).to include("continuation request") if message.include?("continuation")
            end.at_least(:once)

            handler.process_with_function_handling(
              initial_response: initial_response,
              previous_response_id: "resp_000"
            )
          end
        end
      end
    end
  end
end
