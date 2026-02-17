# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Anthropic
    module Messages
      RSpec.describe FunctionCallHandler, type: :service do
        let(:model) { "claude-3-5-sonnet-20241022" }
        let(:tools) { [ :functions ] }
        let(:tool_config) { { "functions" => [ { "name" => "get_weather" } ] } }
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
          let(:conversation_history) do
            [ { role: "user", content: "What's the weather?" } ]
          end

          context "when response has no tool calls" do
            let(:initial_response) do
              NormalizedLlmResponse.new(
                text: "I can help with that!",
                usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                model: model,
                tool_calls: [],
                file_search_results: [],
                web_search_results: [],
                code_interpreter_results: [],
                api_metadata: {},
                raw_response: {}
              )
            end

            it "returns the initial response as final" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:final_response]).to eq(initial_response)
            end

            it "returns empty tool_calls array" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:all_tool_calls]).to be_empty
            end

            it "returns single response in all_responses" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:all_responses]).to eq([ initial_response ])
            end
          end

          context "when response has tool calls" do
            let(:tool_calls) do
              [
                {
                  id: "toolu_01abc",
                  type: "function",
                  function_name: "get_weather",
                  arguments: { location: "Berlin" }
                }
              ]
            end

            let(:initial_response) do
              NormalizedLlmResponse.new(
                text: "",
                usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                model: model,
                tool_calls: tool_calls,
                file_search_results: [],
                web_search_results: [],
                code_interpreter_results: [],
                api_metadata: {},
                raw_response: {}
              )
            end

            it "collects all tool calls" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:all_tool_calls]).to include(tool_calls.first)
            end

            it "returns mock response as final when not using real LLM" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:final_response][:text]).to eq("Mock response after function call")
            end

            it "returns multiple responses in all_responses" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              expect(result[:all_responses].length).to eq(2)
            end

            it "returns updated history with tool messages" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              # Original + assistant tool_use + user tool_result
              expect(result[:updated_history].length).to eq(3)
            end

            it "builds correct assistant tool_use message" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              assistant_msg = result[:updated_history][1]
              expect(assistant_msg[:role]).to eq("assistant")
              expect(assistant_msg[:content]).to be_an(Array)

              tool_use_block = assistant_msg[:content].first
              expect(tool_use_block[:type]).to eq("tool_use")
              expect(tool_use_block[:id]).to eq("toolu_01abc")
              expect(tool_use_block[:name]).to eq("get_weather")
            end

            it "builds correct user tool_result message" do
              result = handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history
              )

              user_msg = result[:updated_history][2]
              expect(user_msg[:role]).to eq("user")

              tool_result_block = user_msg[:content].first
              expect(tool_result_block[:type]).to eq("tool_result")
              expect(tool_result_block[:tool_use_id]).to eq("toolu_01abc")
            end
          end

          context "with MAX_ITERATIONS limit" do
            let(:never_ending_tool_calls) do
              [ { id: "toolu_loop", type: "function", function_name: "loop_func", arguments: {} } ]
            end

            let(:response_with_tools) do
              NormalizedLlmResponse.new(
                text: "",
                usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                model: model,
                tool_calls: never_ending_tool_calls,
                file_search_results: [],
                web_search_results: [],
                code_interpreter_results: [],
                api_metadata: {},
                raw_response: {}
              )
            end

            it "stops after MAX_ITERATIONS" do
              # Mock the handler to always return tool calls
              allow(handler).to receive(:mock_response).and_return(response_with_tools)

              result = handler.process_with_function_handling(
                initial_response: response_with_tools,
                conversation_history: conversation_history
              )

              # Should have MAX_ITERATIONS + 1 responses (initial + 10 iterations)
              expect(result[:all_responses].length).to eq(FunctionCallHandler::MAX_ITERATIONS + 1)
            end
          end

          context "when using real LLM" do
            let(:use_real_llm) { true }
            let(:initial_response) do
              NormalizedLlmResponse.new(
                text: "",
                usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                model: model,
                tool_calls: [ { id: "toolu_real", type: "function", function_name: "get_weather", arguments: {} } ],
                file_search_results: [],
                web_search_results: [],
                code_interpreter_results: [],
                api_metadata: {},
                raw_response: {}
              )
            end

            let(:api_response) do
              NormalizedLlmResponse.new(
                text: "The weather is sunny.",
                usage: { prompt_tokens: 50, completion_tokens: 30, total_tokens: 80 },
                model: model,
                tool_calls: [],
                file_search_results: [],
                web_search_results: [],
                code_interpreter_results: [],
                api_metadata: {},
                raw_response: {}
              )
            end

            before do
              allow(AnthropicMessagesService).to receive(:call).and_return(api_response)
            end

            it "calls AnthropicMessagesService with updated history" do
              handler.process_with_function_handling(
                initial_response: initial_response,
                conversation_history: conversation_history,
                system_prompt: "You are helpful."
              )

              expect(AnthropicMessagesService).to have_received(:call).with(
                hash_including(
                  model: model,
                  system: "You are helpful.",
                  tools: [ :functions ]
                )
              )
            end
          end
        end
      end
    end
  end
end
