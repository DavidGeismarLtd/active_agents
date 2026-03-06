# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Helpers
      RSpec.describe InterlocutorSimulator, type: :service do
        describe "#generate_next_message" do
          let(:interlocutor_prompt) { "You are a patient with a headache" }
          let(:conversation_history) do
            [
              { role: "user", content: "Hello doctor" },
              { role: "assistant", content: "Hello! How can I help you today?" }
            ]
          end

          context "when use_real_llm is false" do
            let(:simulator) { described_class.new(use_real_llm: false) }

            it "returns a mock message" do
              message = simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(message).to eq("I have another question.")
            end
          end

          context "when use_real_llm is true" do
            let(:simulator) { described_class.new(use_real_llm: true) }

            before do
              allow(LlmClientService).to receive(:call).and_return(
                { text: "I've been having a headache for two days." }
              )
            end

            it "uses configuration from interlocutor_simulation context" do
              simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              # Should use values from test/dummy/config/initializers/prompt_tracker.rb
              # interlocutor_simulation context
              expect(LlmClientService).to have_received(:call).with(
                hash_including(
                  provider: :openai,
                  api: :chat_completions,
                  model: "gpt-4o-mini",
                  temperature: 0.7
                )
              )
            end

            it "falls back to defaults when context is not configured" do
              # Temporarily remove the context configuration
              original_contexts = PromptTracker.configuration.contexts
              PromptTracker.configuration.contexts = {}

              simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(LlmClientService).to have_received(:call).with(
                hash_including(
                  provider: :openai,
                  api: :chat_completions,
                  model: "gpt-4o-mini",
                  temperature: 0.7
                )
              )

              # Restore original configuration
              PromptTracker.configuration.contexts = original_contexts
            end

            it "uses custom configuration when provided" do
              # Temporarily override the context configuration
              original_contexts = PromptTracker.configuration.contexts
              PromptTracker.configuration.contexts = {
                interlocutor_simulation: {
                  default_provider: :anthropic,
                  default_api: :messages,
                  default_model: "claude-3-5-sonnet-20241022",
                  default_temperature: 0.5
                }
              }

              simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(LlmClientService).to have_received(:call).with(
                hash_including(
                  provider: :anthropic,
                  api: :messages,
                  model: "claude-3-5-sonnet-20241022",
                  temperature: 0.5
                )
              )

              # Restore original configuration
              PromptTracker.configuration.contexts = original_contexts
            end

            it "includes interlocutor prompt in the simulation prompt" do
              simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(LlmClientService).to have_received(:call) do |args|
                expect(args[:prompt]).to include(interlocutor_prompt)
              end
            end

            it "includes conversation history in the simulation prompt" do
              simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(LlmClientService).to have_received(:call) do |args|
                expect(args[:prompt]).to include("User: Hello doctor")
                expect(args[:prompt]).to include("Assistant: Hello! How can I help you today?")
              end
            end

            it "returns the generated message" do
              message = simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(message).to eq("I've been having a headache for two days.")
            end

            it "returns nil when response contains [END_CONVERSATION]" do
              allow(LlmClientService).to receive(:call).and_return(
                { text: "[END_CONVERSATION]" }
              )

              message = simulator.generate_next_message(
                interlocutor_prompt: interlocutor_prompt,
                conversation_history: conversation_history,
                turn: 2
              )

              expect(message).to be_nil
            end

            it "handles conversation history with string keys" do
              history_with_strings = [
                { "role" => "user", "content" => "Hello" },
                { "role" => "assistant", "content" => "Hi there" }
              ]

              expect do
                simulator.generate_next_message(
                  interlocutor_prompt: interlocutor_prompt,
                  conversation_history: history_with_strings,
                  turn: 2
                )
              end.not_to raise_error
            end
          end
        end
      end
    end
  end
end
