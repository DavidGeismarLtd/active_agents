# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Openai
      module Assistants
        RSpec.describe SimulatedConversationRunner, type: :service do
          let(:model_config) do
            {
              provider: "openai",
              api: "assistants",
              model: "gpt-4o",
              assistant_id: "asst_abc123",
              temperature: 0.7
            }
          end

          let(:runner) do
            described_class.new(
              model_config: model_config,
              use_real_llm: false
            )
          end

          describe "#execute" do
            let(:params) do
              {
                system_prompt: "You are helpful.",
                max_turns: 1,
                first_user_message: "Hello"
              }
            end

            it "returns output_data with messages" do
              result = runner.execute(params)

              expect(result).to be_a(Hash)
              expect(result["messages"]).to be_an(Array)
              expect(result["messages"].length).to eq(2)
            end

            it "includes user and assistant messages" do
              result = runner.execute(params)

              messages = result["messages"]
              expect(messages[0]["role"]).to eq("user")
              expect(messages[0]["content"]).to eq("Hello")
              expect(messages[1]["role"]).to eq("assistant")
            end

            it "includes thread_id in output_data" do
              result = runner.execute(params)

              expect(result).to have_key("thread_id")
              expect(result["thread_id"]).to start_with("thread_mock_")
            end

            it "includes thread_id and run_id in assistant messages api_metadata" do
              result = runner.execute(params)

              assistant_message = result["messages"].find { |m| m["role"] == "assistant" }
              expect(assistant_message["api_metadata"][:thread_id]).to start_with("thread_mock_")
              expect(assistant_message["api_metadata"][:run_id]).to start_with("run_mock_")
            end

            it "includes token usage in output_data" do
              result = runner.execute(params)

              expect(result).to have_key("tokens")
              expect(result["tokens"]).to include("prompt_tokens", "completion_tokens", "total_tokens")
            end

            it "includes response_time_ms in output_data" do
              result = runner.execute(params)

              expect(result).to have_key("response_time_ms")
              expect(result["response_time_ms"]).to be_a(Integer)
            end

            context "with multi-turn conversation" do
              let(:params) do
                {
                  system_prompt: "You are a doctor.",
                  max_turns: 2,
                  first_user_message: "Hello doctor",
                  interlocutor_prompt: "You are a patient with a headache."
                }
              end

              before do
                # Mock the interlocutor simulator
                interlocutor = instance_double(Helpers::InterlocutorSimulator)
                allow(Helpers::InterlocutorSimulator).to receive(:new).and_return(interlocutor)
                allow(interlocutor).to receive(:generate_next_message).and_return("I have a headache")
              end

              it "executes multiple turns" do
                result = runner.execute(params)

                expect(result["messages"].length).to eq(4) # 2 user + 2 assistant
                expect(result["total_turns"]).to eq(2)
              end
            end

            context "with real LLM" do
              let(:runner) do
                described_class.new(
                  model_config: model_config,
                  use_real_llm: true
                )
              end

              let(:mock_response) do
                PromptTracker::NormalizedResponse.new(
                  text: "Hello! How can I help you?",
                  usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                  model: "asst_abc123",
                  tool_calls: [],
                  file_search_results: [],
                  web_search_results: [],
                  code_interpreter_results: [],
                  api_metadata: {
                    thread_id: "thread_real123",
                    run_id: "run_real456",
                    annotations: []
                  },
                  raw_response: {
                    thread_id: "thread_real123",
                    run_id: "run_real456"
                  }
                )
              end

              before do
                allow(LlmClients::OpenaiAssistantService).to receive(:call).and_return(mock_response)
              end

              it "calls LlmClients::OpenaiAssistantService with correct parameters" do
                runner.execute(params)

                expect(LlmClients::OpenaiAssistantService).to have_received(:call).with(
                  assistant_id: "asst_abc123",
                  user_message: "Hello",
                  thread_id: nil
                )
              end

              it "uses response from LlmClients::OpenaiAssistantService" do
                result = runner.execute(params)

                assistant_message = result["messages"].find { |m| m["role"] == "assistant" }
                expect(assistant_message["content"]).to eq("Hello! How can I help you?")
                expect(assistant_message["api_metadata"][:thread_id]).to eq("thread_real123")
              end
            end
          end
        end
      end
    end
  end
end
