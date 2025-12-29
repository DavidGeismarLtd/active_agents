# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe AssistantPlaygroundService do
    # Mock the API key to avoid initialization errors
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-api-key")
      allow(ENV).to receive(:[]).with("OPENAI_LOUNA_API_KEY").and_return(nil)
    end

    let(:service) { described_class.new }

    describe "#create_assistant" do
      it "creates an assistant via OpenAI API and saves to database" do
        # Mock OpenAI client
        mock_client = double("OpenAI::Client")
        mock_assistants = double("assistants")

        allow(service).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:assistants).and_return(mock_assistants)

        # Mock API response
        api_response = {
          "id" => "asst_test123",
          "name" => "Test Assistant",
          "description" => "A test assistant",
          "instructions" => "You are helpful",
          "model" => "gpt-4o",
          "tools" => [],
          "file_ids" => [],
          "temperature" => 1.0,
          "top_p" => 1.0,
          "response_format" => nil,
          "tool_resources" => {}
        }

        allow(mock_assistants).to receive(:create).with(parameters: anything).and_return(api_response)

        # Call service
        result = service.create_assistant(
          name: "Test Assistant",
          description: "A test assistant",
          instructions: "You are helpful",
          model: "gpt-4o"
        )

        # Verify result
        expect(result[:success]).to be true
        expect(result[:assistant]).to be_a(PromptTracker::Openai::Assistant)
        expect(result[:assistant].assistant_id).to eq("asst_test123")
        expect(result[:assistant].name).to eq("Test Assistant")
        expect(result[:assistant].metadata["model"]).to eq("gpt-4o")
      end

      it "returns error on API failure" do
        # Mock OpenAI client to raise error
        mock_client = double("OpenAI::Client")
        mock_assistants = double("assistants")

        allow(service).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:assistants).and_return(mock_assistants)
        allow(mock_assistants).to receive(:create).and_raise(StandardError.new("API Error"))

        result = service.create_assistant(name: "Test")

        expect(result[:success]).to be false
        expect(result[:error]).to include("API Error")
      end
    end

    describe "#update_assistant" do
      let!(:assistant) { create(:openai_assistant, assistant_id: "asst_existing") }

      it "updates an assistant via OpenAI API" do
        # Mock OpenAI client
        mock_client = double("OpenAI::Client")
        mock_assistants = double("assistants")

        allow(service).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:assistants).and_return(mock_assistants)

        # Mock API response
        api_response = {
          "id" => "asst_existing",
          "name" => "Updated Name",
          "description" => "Updated description",
          "instructions" => "Updated instructions",
          "model" => "gpt-4o",
          "tools" => [ { "type" => "code_interpreter" } ],
          "file_ids" => [],
          "temperature" => 0.7,
          "top_p" => 0.9,
          "response_format" => nil,
          "tool_resources" => {}
        }

        allow(mock_assistants).to receive(:modify).with(id: "asst_existing", parameters: anything).and_return(api_response)

        # Call service
        result = service.update_assistant(
          "asst_existing",
          name: "Updated Name",
          instructions: "Updated instructions",
          temperature: 0.7
        )

        # Verify result
        expect(result[:success]).to be true
        expect(result[:assistant].name).to eq("Updated Name")
        expect(result[:assistant].metadata["instructions"]).to eq("Updated instructions")
        expect(result[:assistant].metadata["temperature"]).to eq(0.7)
      end
    end

    describe "#create_thread" do
      it "creates a new thread via OpenAI API" do
        # Mock OpenAI client
        mock_client = double("OpenAI::Client")
        mock_threads = double("threads")

        allow(service).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:threads).and_return(mock_threads)
        allow(mock_threads).to receive(:create).and_return({ "id" => "thread_123" })

        result = service.create_thread

        expect(result[:success]).to be true
        expect(result[:thread_id]).to eq("thread_123")
      end
    end

    describe "#send_message" do
      it "sends a message and returns assistant response" do
        # Mock OpenAI client
        mock_client = double("OpenAI::Client")
        mock_messages = double("messages")
        mock_runs = double("runs")

        allow(service).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:messages).and_return(mock_messages)
        allow(mock_client).to receive(:runs).and_return(mock_runs)

        # Mock message creation
        allow(mock_messages).to receive(:create).and_return({ "id" => "msg_123" })

        # Mock run creation
        allow(mock_runs).to receive(:create).and_return({ "id" => "run_123", "status" => "queued" })

        # Mock run completion
        allow(service).to receive(:wait_for_completion).and_return({
          "id" => "run_123",
          "status" => "completed",
          "usage" => { "total_tokens" => 100 }
        })

        # Mock message list
        allow(mock_messages).to receive(:list).and_return({
          "data" => [
            {
              "role" => "assistant",
              "content" => [ { "text" => { "value" => "Hello!" } } ],
              "created_at" => Time.now.to_i
            }
          ]
        })

        result = service.send_message(
          thread_id: "thread_123",
          assistant_id: "asst_123",
          content: "Hi"
        )

        expect(result[:success]).to be true
        expect(result[:message][:content]).to eq("Hello!")
        expect(result[:usage]).to be_present
      end
    end
  end
end
