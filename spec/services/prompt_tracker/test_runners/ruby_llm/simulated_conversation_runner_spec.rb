# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module RubyLlm
      RSpec.describe SimulatedConversationRunner, type: :service do
        let(:model_config) do
          {
            provider: "openai",
            api: "chat_completions",
            model: "gpt-4o-mini",
            temperature: 0.7,
            tools: [],
            tool_config: {}
          }
        end

        describe "#execute" do
          context "single-turn execution (mock)" do
            let(:runner) { described_class.new(model_config: model_config, use_real_llm: false) }

            it "returns output_data with expected structure" do
              params = {
                system_prompt: "You are a helpful assistant.",
                max_turns: 1,
                first_user_message: "Hello, how are you?"
              }

              output_data = runner.execute(params)

              expect(output_data["status"]).to eq("completed")
              expect(output_data["model"]).to eq("gpt-4o-mini")
              expect(output_data["provider"]).to eq("openai")
              expect(output_data["total_turns"]).to eq(1)
              expect(output_data["messages"].length).to eq(2)
            end

            it "includes user and assistant messages" do
              params = {
                system_prompt: "You are helpful.",
                max_turns: 1,
                first_user_message: "Test message"
              }

              output_data = runner.execute(params)
              messages = output_data["messages"]

              expect(messages[0]["role"]).to eq("user")
              expect(messages[0]["content"]).to eq("Test message")
              expect(messages[1]["role"]).to eq("assistant")
              expect(messages[1]["content"]).to include("Mock LLM response")
            end

            it "includes rendered prompts in output" do
              params = {
                system_prompt: "Be concise.",
                max_turns: 1,
                first_user_message: "What is 2+2?"
              }

              output_data = runner.execute(params)

              expect(output_data["rendered_system_prompt"]).to eq("Be concise.")
              expect(output_data["rendered_user_prompt"]).to eq("What is 2+2?")
            end

            it "tracks response time" do
              params = {
                system_prompt: "Be fast.",
                max_turns: 1,
                first_user_message: "Quick question"
              }

              output_data = runner.execute(params)

              expect(output_data["response_time_ms"]).to be_a(Integer)
              expect(output_data["response_time_ms"]).to be >= 0
            end
          end

          context "multi-turn execution (mock)" do
            let(:runner) { described_class.new(model_config: model_config, use_real_llm: false) }

            it "executes multiple turns" do
              params = {
                system_prompt: "You are a doctor.",
                max_turns: 3,
                first_user_message: "I have a headache.",
                interlocutor_prompt: "You are a patient."
              }

              output_data = runner.execute(params)

              # Should have 3 turns = 6 messages (3 user + 3 assistant)
              expect(output_data["total_turns"]).to eq(3)
              expect(output_data["messages"].length).to eq(6)
            end

            it "maintains conversation history" do
              params = {
                system_prompt: "You are helpful.",
                max_turns: 2,
                first_user_message: "Hello",
                interlocutor_prompt: "Respond naturally."
              }

              output_data = runner.execute(params)
              messages = output_data["messages"]

              # Verify alternating roles
              expect(messages[0]["role"]).to eq("user")
              expect(messages[1]["role"]).to eq("assistant")
              expect(messages[2]["role"]).to eq("user")
              expect(messages[3]["role"]).to eq("assistant")
            end

            it "includes turn numbers in messages" do
              params = {
                system_prompt: "Track turns.",
                max_turns: 2,
                first_user_message: "Turn 1",
                interlocutor_prompt: "Continue conversation."
              }

              output_data = runner.execute(params)
              messages = output_data["messages"]

              expect(messages[0]["turn"]).to eq(1)
              expect(messages[1]["turn"]).to eq(1)
              expect(messages[2]["turn"]).to eq(2)
              expect(messages[3]["turn"]).to eq(2)
            end
          end

          context "with tools (mock)" do
            let(:model_config_with_tools) do
              {
                provider: "openai",
                api: "chat_completions",
                model: "gpt-4o-mini",
                temperature: 0.7,
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    {
                      "name" => "get_weather",
                      "description" => "Get weather for a city",
                      "parameters" => {
                        "type" => "object",
                        "properties" => { "city" => { "type" => "string" } },
                        "required" => [ "city" ]
                      }
                    }
                  ]
                }
              }
            end
          end
        end
      end
    end
  end
end
