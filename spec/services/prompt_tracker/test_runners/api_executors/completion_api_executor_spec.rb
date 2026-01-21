# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module ApiExecutors
      RSpec.describe CompletionApiExecutor, type: :service do
        let(:model_config) do
          { "provider" => "openai", "api" => "chat", "model" => "gpt-4o", "temperature" => 0.7 }
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
          context "single-turn mode (max_turns=1)" do
            let(:params) do
              {
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
              expect(messages[1]["content"]).to include("Mock LLM response")
            end

            it "includes provider and model in output" do
              result = executor.execute(params)

              expect(result["provider"]).to eq("openai")
              expect(result["model"]).to eq("gpt-4o")
            end

            it "sets status to completed" do
              result = executor.execute(params)

              expect(result["status"]).to eq("completed")
            end

            it "calculates total_turns correctly" do
              result = executor.execute(params)

              expect(result["total_turns"]).to eq(1)
            end

            it "records response_time_ms" do
              result = executor.execute(params)

              expect(result["response_time_ms"]).to be >= 0
            end
          end

          context "multi-turn mode (max_turns>1)" do
            let(:params) do
              {
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

            it "alternates user and assistant roles" do
              result = executor.execute(params)

              messages = result["messages"]
              messages.each_with_index do |msg, idx|
                expected_role = idx.even? ? "user" : "assistant"
                expect(msg["role"]).to eq(expected_role)
              end
            end

            it "assigns turn numbers correctly" do
              result = executor.execute(params)

              messages = result["messages"]
              expect(messages[0]["turn"]).to eq(1)
              expect(messages[1]["turn"]).to eq(1)
              expect(messages[2]["turn"]).to eq(2)
              expect(messages[3]["turn"]).to eq(2)
            end

            it "calculates total_turns based on assistant messages" do
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
                usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                model: "gpt-4o",
                raw: {}
              }
            end

            before do
              allow(LlmClientService).to receive(:call).and_return(mock_response)
            end

            it "calls LlmClientService with correct parameters" do
              params = {
                system_prompt: "You are helpful.",
                max_turns: 1,
                first_user_message: "Hello"
              }

              expect(LlmClientService).to receive(:call).with(
                provider: "openai",
                api: "chat",
                model: "gpt-4o",
                prompt: "Hello",
                system_prompt: "You are helpful.",
                temperature: 0.7,
                tools: nil
              ).and_return(mock_response)

              executor.execute(params)
            end
          end
        end
      end
    end
  end
end
