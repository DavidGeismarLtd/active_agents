# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Anthropic
      module Messages
        RSpec.describe SimulatedConversationRunner, type: :service do
          let(:model_config) do
            {
              provider: "anthropic",
              api: "messages",
              model: "claude-3-5-sonnet-20241022",
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
                expect(output_data["model"]).to eq("claude-3-5-sonnet-20241022")
                expect(output_data["provider"]).to eq("anthropic")
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
                expect(messages[1]["content"]).to include("Mock Anthropic Messages API response")
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
                expect(messages.map { |m| m["role"] }).to eq(%w[user assistant user assistant])
              end
            end

            context "assistant message structure" do
              let(:runner) { described_class.new(model_config: model_config, use_real_llm: false) }

              it "includes all expected fields in assistant messages" do
                params = {
                  system_prompt: "You are helpful.",
                  max_turns: 1,
                  first_user_message: "Hello"
                }

                output_data = runner.execute(params)
                assistant_msg = output_data["messages"].find { |m| m["role"] == "assistant" }

                expect(assistant_msg).to have_key("usage")
                expect(assistant_msg).to have_key("tool_calls")
                expect(assistant_msg).to have_key("api_metadata")
                expect(assistant_msg["file_search_results"]).to eq([])
                expect(assistant_msg["code_interpreter_results"]).to eq([])
              end

              it "includes api_metadata with message_id" do
                params = {
                  system_prompt: "You are helpful.",
                  max_turns: 1,
                  first_user_message: "Hello"
                }

                output_data = runner.execute(params)
                assistant_msg = output_data["messages"].find { |m| m["role"] == "assistant" }

                expect(assistant_msg["api_metadata"][:message_id]).to start_with("msg_mock_")
              end
            end

            context "token aggregation" do
              let(:runner) { described_class.new(model_config: model_config, use_real_llm: false) }

              it "aggregates tokens across turns" do
                params = {
                  system_prompt: "Test",
                  max_turns: 2,
                  first_user_message: "Hello",
                  interlocutor_prompt: "Respond"
                }

                output_data = runner.execute(params)

                expect(output_data["tokens"]).to be_present
                expect(output_data["tokens"]["prompt_tokens"]).to be > 0
                expect(output_data["tokens"]["completion_tokens"]).to be > 0
              end
            end
          end
        end
      end
    end
  end
end
