# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    RSpec.describe ConversationRunner, type: :service do
      let(:assistant_id) { "asst_test123" }
      let(:interlocutor_simulation_prompt) { "You are a patient with a severe headache. Respond naturally to the doctor's questions." }
      let(:max_turns) { 3 }

      let(:runner) do
        described_class.new(
          assistant_id: assistant_id,
          interlocutor_simulation_prompt: interlocutor_simulation_prompt,
          max_turns: max_turns
        )
      end

      describe "#initialize" do
        it "sets instance variables" do
          expect(runner.assistant_id).to eq(assistant_id)
          expect(runner.interlocutor_simulation_prompt).to eq(interlocutor_simulation_prompt)
          expect(runner.max_turns).to eq(max_turns)
          expect(runner.thread_id).to be_nil
          expect(runner.messages).to eq([])
        end

        it "defaults max_turns to 5" do
          runner = described_class.new(
            assistant_id: assistant_id,
            interlocutor_simulation_prompt: interlocutor_simulation_prompt
          )
          expect(runner.max_turns).to eq(5)
        end
      end

      describe "#run!" do
        let(:mock_client) { double("OpenAI::Client") }
        let(:mock_threads) { double("threads") }
        let(:mock_messages) { double("messages") }
        let(:mock_runs) { double("runs") }

        before do
          # Mock the API key through configuration
          allow(PromptTracker.configuration).to receive(:openai_assistants_api_key).and_return("test-api-key")
          allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test-api-key")

          # Stub the OpenAI module and Client class
          openai_module = Module.new
          openai_client_class = Class.new do
            def self.new(*args, **kwargs)
              # This will be stubbed by the mock below
            end
          end
          stub_const("OpenAI", openai_module)
          stub_const("OpenAI::Client", openai_client_class)

          allow(OpenAI::Client).to receive(:new).and_return(mock_client)
          allow(mock_client).to receive(:threads).and_return(mock_threads)
          allow(mock_client).to receive(:messages).and_return(mock_messages)
          allow(mock_client).to receive(:runs).and_return(mock_runs)
        end

        it "creates a thread and runs a conversation" do
          # Mock LLM service for generating user messages
          # First call generates initial message, second call returns [END] to stop conversation
          allow(PromptTracker::LlmClientService).to receive(:call).and_return(
            { text: "I have a severe headache" },
            { text: "[END]" }
          )

          # Mock thread creation
          allow(mock_threads).to receive(:create).and_return({ "id" => "thread_123" })

          # Mock user message creation
          allow(mock_messages).to receive(:create).and_return({ "id" => "msg_user_1" })

          # Mock run creation
          allow(mock_runs).to receive(:create).and_return({ "id" => "run_1", "status" => "queued" })

          # Mock run completion
          allow(mock_runs).to receive(:retrieve).and_return({ "id" => "run_1", "status" => "completed" })

          # Mock assistant message retrieval - only return the latest assistant message
          allow(mock_messages).to receive(:list).and_return({
            "data" => [
              {
                "id" => "msg_asst_1",
                "role" => "assistant",
                "content" => [
                  {
                    "type" => "text",
                    "text" => { "value" => "I'm sorry to hear that. Can you describe the pain?" }
                  }
                ]
              }
            ]
          })

          result = runner.run!

          expect(result[:status]).to eq("completed")
          expect(result[:thread_id]).to eq("thread_123")
          expect(result[:messages].length).to eq(2) # 1 user + 1 assistant
          expect(result[:messages][0][:role]).to eq("user")
          expect(result[:messages][0][:content]).to eq("I have a severe headache")
          expect(result[:messages][1][:role]).to eq("assistant")
          expect(result[:messages][1][:content]).to include("describe the pain")
        end

        it "handles errors gracefully" do
          # Mock LLM service
          allow(PromptTracker::LlmClientService).to receive(:call).and_return(
            { text: "I have a severe headache" }
          )

          allow(mock_threads).to receive(:create).and_raise(StandardError.new("API Error"))

          expect { runner.run! }.to raise_error(StandardError, "API Error")
        end

        it "stops after max_turns" do
          # Mock LLM service to return initial message, then [END] to end conversation
          allow(PromptTracker::LlmClientService).to receive(:call).and_return(
            { text: "I have a severe headache" },
            { text: "[END]" } # Return [END] to end conversation
          )

          allow(mock_threads).to receive(:create).and_return({ "id" => "thread_123" })
          allow(mock_messages).to receive(:create).and_return({ "id" => "msg_1" })
          allow(mock_runs).to receive(:create).and_return({ "id" => "run_1", "status" => "queued" })
          allow(mock_runs).to receive(:retrieve).and_return({ "id" => "run_1", "status" => "completed" })
          allow(mock_messages).to receive(:list).and_return({
            "data" => [
              {
                "role" => "assistant",
                "content" => [ { "type" => "text", "text" => { "value" => "Response" } } ]
              }
            ]
          })

          result = runner.run!

          # Should only have 1 turn since generate_next_user_message returns nil
          expect(result[:total_turns]).to eq(1)
        end
      end

      describe "#extract_message_content" do
        it "extracts text from message content" do
          message = {
            "content" => [
              { "type" => "text", "text" => { "value" => "Hello" } },
              { "type" => "text", "text" => { "value" => "World" } }
            ]
          }

          content = runner.send(:extract_message_content, message)
          expect(content).to eq("Hello\nWorld")
        end

        it "returns empty string for nil content" do
          message = { "content" => nil }
          content = runner.send(:extract_message_content, message)
          expect(content).to eq("")
        end

        it "returns empty string for empty content" do
          message = { "content" => [] }
          content = runner.send(:extract_message_content, message)
          expect(content).to eq("")
        end

        it "filters only text blocks" do
          message = {
            "content" => [
              { "type" => "text", "text" => { "value" => "Text content" } },
              { "type" => "image", "image" => { "url" => "http://example.com/image.jpg" } }
            ]
          }

          content = runner.send(:extract_message_content, message)
          expect(content).to eq("Text content")
        end
      end

      # Real API integration test
      # Run with: REAL_API=true rspec spec/services/prompt_tracker/openai/conversation_runner_spec.rb:175
      describe "Real API Integration", if: ENV["REAL_API"] == "true" do
        let(:real_assistant_id) { "asst_Rp8RFTBJuMsJgtPaODCFsalw" }
        let(:interlocutor_prompt) do
          <<~PROMPT
            You are simulating a patient talking to a medical assistant.
            You have a severe headache and are seeking medical advice.
            Respond naturally to the assistant's questions.
            Keep your responses concise (1-2 sentences).
            After 2-3 exchanges, say you feel better and thank the assistant.
          PROMPT
        end

        it "runs a real multi-turn conversation" do
          runner = described_class.new(
            assistant_id: real_assistant_id,
            interlocutor_simulation_prompt: interlocutor_prompt,
            max_turns: 3
          )

          result = runner.run!

          expect(result).to be_a(Hash)
          expect(result[:status]).to eq("completed")
          expect(result[:thread_id]).to be_present
          expect(result[:messages]).to be_an(Array)
          expect(result[:total_turns]).to be > 0

          # Should have alternating user/assistant messages
          expect(result[:messages].first[:role]).to eq("user")
          if result[:messages].size > 1
            expect(result[:messages].second[:role]).to eq("assistant")
          end

          # Each message should have required fields
          result[:messages].each do |message|
            expect(message).to have_key(:role)
            expect(message).to have_key(:content)
            expect(message).to have_key(:turn)
            expect(message).to have_key(:timestamp)
            expect(message[:content]).to be_present
          end

          # Metadata should be present
          expect(result[:metadata]).to include(
            assistant_id: real_assistant_id,
            max_turns: 3
          )
          expect(result[:metadata][:completed_at]).to be_present

          # Print conversation for debugging
          puts "\n" + "=" * 80
          puts "REAL CONVERSATION TRANSCRIPT"
          puts "=" * 80
          result[:messages].each do |msg|
            puts "\n[#{msg[:role].upcase}] (Turn #{msg[:turn]})"
            puts msg[:content]
            puts "-" * 80
          end
          puts "\nTotal turns: #{result[:total_turns]}"
          puts "Thread ID: #{result[:thread_id]}"
          puts "=" * 80 + "\n"
        end

        it "respects max_turns limit" do
          runner = described_class.new(
            assistant_id: real_assistant_id,
            interlocutor_simulation_prompt: "You are a patient with a headache. Keep responses very short.",
            max_turns: 2
          )

          result = runner.run!

          # Should not exceed max_turns
          assistant_messages = result[:messages].select { |m| m[:role] == "assistant" }
          expect(assistant_messages.count).to be <= 2
        end
      end
    end
  end
end
