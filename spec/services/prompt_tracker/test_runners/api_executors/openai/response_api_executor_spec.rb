# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module ApiExecutors
      module Openai
        RSpec.describe ResponseApiExecutor, type: :service do
          let(:model_config) do
            { "provider" => "openai_responses", "model" => "gpt-4o", "temperature" => 0.7 }
          end

          let(:executor) do
            described_class.new(
              model_config: model_config,
              use_real_llm: false
            )
          end

          describe "#initialize" do
            it "sets instance variables" do
              expect(executor.model_config).to eq(model_config.with_indifferent_access)
              expect(executor.use_real_llm).to be false
            end
          end

          describe "#execute" do
            context "single-turn mode" do
              let(:params) do
                {
                  mode: :single_turn,
                  system_prompt: "You are helpful.",
                  max_turns: 1,
                  first_user_message: "Hello, how are you?"
                }
              end

              it "returns output_data with messages array" do
                result = executor.execute(params)

                expect(result).to be_a(Hash)
                expect(result["messages"]).to be_an(Array)
                expect(result["messages"].length).to eq(2)
              end

              it "includes user and assistant messages" do
                result = executor.execute(params)

                messages = result["messages"]
                expect(messages[0]["role"]).to eq("user")
                expect(messages[0]["content"]).to eq("Hello, how are you?")
                expect(messages[1]["role"]).to eq("assistant")
                expect(messages[1]["content"]).to include("Mock Response API response")
              end

              it "uses openai_responses as provider" do
                result = executor.execute(params)

                expect(result["provider"]).to eq("openai_responses")
              end

              it "includes response_id in assistant messages" do
                result = executor.execute(params)

                assistant_msg = result["messages"].find { |m| m["role"] == "assistant" }
                expect(assistant_msg["response_id"]).to start_with("resp_mock_")
              end

              it "stores previous_response_id in output" do
                result = executor.execute(params)

                expect(result["previous_response_id"]).to start_with("resp_mock_")
              end

              it "includes tools_used in output" do
                result = executor.execute(params)

                expect(result["tools_used"]).to be_an(Array)
              end
            end

            context "conversational mode" do
              let(:params) do
                {
                  mode: :conversational,
                  system_prompt: "You are a helpful doctor.",
                  max_turns: 3,
                  interlocutor_prompt: "You are a patient with a headache.",
                  first_user_message: "I have a headache."
                }
              end

              it "runs multiple turns" do
                result = executor.execute(params)

                messages = result["messages"]
                expect(messages.length).to eq(6)  # 3 turns × 2 messages each
              end

              it "includes response_id in each assistant message" do
                result = executor.execute(params)

                assistant_messages = result["messages"].select { |m| m["role"] == "assistant" }
                assistant_messages.each do |msg|
                  expect(msg["response_id"]).to start_with("resp_mock_")
                end
              end

              it "calculates total_turns correctly" do
                result = executor.execute(params)

                expect(result["total_turns"]).to eq(3)
              end
            end

            context "with real LLM" do
              let(:executor) do
                described_class.new(
                  model_config: model_config,
                  use_real_llm: true
                )
              end

              let(:mock_response) do
                {
                  text: "Hello! I'm doing well, thanks for asking.",
                  response_id: "resp_abc123",
                  usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                  model: "gpt-4o",
                  tool_calls: [],
                  raw: {}
                }
              end

              before do
                allow(OpenaiResponseService).to receive(:call).and_return(mock_response)
                allow(OpenaiResponseService).to receive(:call_with_context).and_return(mock_response)
              end

              it "calls OpenaiResponseService.call for first turn" do
                params = {
                  mode: :single_turn,
                  system_prompt: "You are helpful.",
                  first_user_message: "Hello"
                }

                expect(OpenaiResponseService).to receive(:call).with(
                  model: "gpt-4o",
                  user_prompt: "Hello",
                  system_prompt: "You are helpful.",
                  tools: [],
                  tool_config: {},
                  temperature: 0.7
                ).and_return(mock_response)

                executor.execute(params)
              end

              context "with function calls" do
                let(:function_call_response) do
                  {
                    text: "",
                    response_id: "resp_func123",
                    usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                    model: "gpt-4o",
                    tool_calls: [
                      {
                        id: "call_abc123",
                        type: "function",
                        function_name: "get_weather",
                        arguments: { "city" => "London" }
                      }
                    ],
                    raw: {}
                  }
                end

                let(:final_response) do
                  {
                    text: "The weather in London is sunny.",
                    response_id: "resp_final456",
                    usage: { prompt_tokens: 20, completion_tokens: 8, total_tokens: 28 },
                    model: "gpt-4o",
                    tool_calls: [],
                    raw: {}
                  }
                end

                it "handles function calls by executing them and sending results back" do
                  # Reset the before block's stubs
                  RSpec::Mocks.space.proxy_for(OpenaiResponseService).reset

                  params = {
                    mode: :single_turn,
                    system_prompt: "You are helpful.",
                    first_user_message: "What's the weather in London?"
                  }

                  # First call returns a function call
                  expect(OpenaiResponseService).to receive(:call).with(
                    model: "gpt-4o",
                    user_prompt: "What's the weather in London?",
                    system_prompt: "You are helpful.",
                    tools: [],
                    tool_config: {},
                    temperature: 0.7
                  ).and_return(function_call_response)

                  # Second call sends function output and gets final response
                  expect(OpenaiResponseService).to receive(:call_with_context).with(
                    model: "gpt-4o",
                    user_prompt: array_including(
                      hash_including(
                        type: "function_call_output",
                        call_id: "call_abc123"
                      )
                    ),
                    previous_response_id: "resp_func123",
                    tools: [],
                    tool_config: {}
                  ).and_return(final_response)

                  result = executor.execute(params)

                  # Should have final text response
                  assistant_msg = result["messages"].find { |m| m["role"] == "assistant" }
                  expect(assistant_msg["content"]).to eq("The weather in London is sunny.")

                  # Should include the function call that was made
                  expect(assistant_msg["tool_calls"]).to be_an(Array)
                  expect(assistant_msg["tool_calls"].length).to eq(1)
                  expect(assistant_msg["tool_calls"].first[:function_name]).to eq("get_weather")
                  expect(assistant_msg["tool_calls"].first[:id]).to eq("call_abc123")
                end
              end
            end
          end
        end
      end
    end
  end
end
