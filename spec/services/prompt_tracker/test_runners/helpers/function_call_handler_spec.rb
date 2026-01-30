# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Helpers
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

            it "calls API with function outputs" do
              handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              expect(handler).to have_received(:call_api_with_function_outputs).with(
                array_including(
                  hash_including(
                    type: "function_call_output",
                    call_id: "call_1"
                  )
                ),
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
                /Function call iteration limit.*reached/
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
              allow(OpenaiResponseService).to receive(:call_with_context).and_return(
                {
                  text: "The weather is sunny",
                  response_id: "resp_124",
                  usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                  tool_calls: []
                }
              )
            end

            it "calls OpenaiResponseService with function outputs" do
              handler.process_with_function_handling(
                initial_response: initial_response,
                previous_response_id: "resp_000",
                turn: 1
              )

              expect(OpenaiResponseService).to have_received(:call_with_context)
            end
          end
        end
      end
    end
  end
end
