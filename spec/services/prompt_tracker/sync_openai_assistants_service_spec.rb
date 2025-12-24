# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe SyncOpenaiAssistantsService do
    let(:service) { described_class.new }
    let(:mock_client) { instance_double(OpenAI::Client) }

    let(:mock_assistants_response) do
      {
        "data" => [
          {
            "id" => "asst_123",
            "name" => "Customer Support Assistant",
            "description" => "Helps with customer inquiries",
            "instructions" => "You are a helpful customer support assistant.",
            "model" => "gpt-4o",
            "tools" => [],
            "file_ids" => [],
            "temperature" => 0.7,
            "top_p" => 1.0,
            "response_format" => "auto",
            "tool_resources" => {}
          },
          {
            "id" => "asst_456",
            "name" => "Code Review Assistant",
            "description" => "Reviews code for quality",
            "instructions" => "You are a code review assistant.",
            "model" => "gpt-4o-mini",
            "tools" => [ { "type" => "code_interpreter" } ],
            "file_ids" => [],
            "temperature" => 0.5,
            "top_p" => 1.0,
            "response_format" => "auto",
            "tool_resources" => {}
          }
        ]
      }
    end

    before do
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:assistants).and_return(mock_client)
      allow(mock_client).to receive(:list).and_return(mock_assistants_response)
    end

    describe ".call" do
      it "returns a result hash with counts" do
        result = described_class.call

        expect(result).to include(
          created: 2,
          updated: 0,
          total: 2,
          assistants: be_an(Array)
        )
      end

      it "creates new assistants from OpenAI API" do
        expect {
          described_class.call
        }.to change(PromptTracker::Openai::Assistant, :count).by(2)
      end

      it "stores assistant metadata correctly" do
        described_class.call

        assistant = PromptTracker::Openai::Assistant.find_by(assistant_id: "asst_123")
        expect(assistant).to be_present
        expect(assistant.name).to eq("Customer Support Assistant")
        expect(assistant.description).to eq("Helps with customer inquiries")
        expect(assistant.metadata["instructions"]).to eq("You are a helpful customer support assistant.")
        expect(assistant.metadata["model"]).to eq("gpt-4o")
        expect(assistant.metadata["temperature"]).to eq(0.7)
      end

      context "when assistants already exist" do
        before do
          PromptTracker::Openai::Assistant.create!(
            assistant_id: "asst_123",
            name: "Old Name",
            description: "Old description",
            metadata: {}
          )
        end

        it "updates existing assistants" do
          expect {
            described_class.call
          }.to change(PromptTracker::Openai::Assistant, :count).by(1) # Only creates asst_456
        end

        it "returns correct counts" do
          result = described_class.call

          expect(result[:created]).to eq(1)
          expect(result[:updated]).to eq(1)
          expect(result[:total]).to eq(2)
        end

        it "updates assistant metadata" do
          described_class.call

          assistant = PromptTracker::Openai::Assistant.find_by(assistant_id: "asst_123")
          expect(assistant.name).to eq("Customer Support Assistant")
          expect(assistant.description).to eq("Helps with customer inquiries")
        end
      end

      context "when API key is not set" do
        before do
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
        end

        it "raises SyncError" do
          expect {
            described_class.call
          }.to raise_error(SyncOpenaiAssistantsService::SyncError, /OPENAI_API_KEY/)
        end
      end

      context "when API call fails" do
        before do
          allow(mock_client).to receive(:list).and_raise(StandardError, "API error")
        end

        it "raises SyncError" do
          expect {
            described_class.call
          }.to raise_error(SyncOpenaiAssistantsService::SyncError, /Failed to fetch assistants/)
        end
      end
    end
  end
end
