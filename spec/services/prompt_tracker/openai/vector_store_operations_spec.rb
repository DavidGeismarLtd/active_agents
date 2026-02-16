# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    RSpec.describe VectorStoreOperations, type: :service do
      let(:mock_client) { instance_double(OpenAI::Client) }
      let(:mock_vector_stores) { double("vector_stores") }
      let(:mock_vector_store_files) { double("vector_store_files") }
      let(:mock_files) { double("files") }

      before do
        # Stub configuration to provide API key
        allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test_api_key")

        # Stub OpenAI client
        allow(OpenAI::Client).to receive(:new).with(access_token: "test_api_key").and_return(mock_client)
        allow(mock_client).to receive(:vector_stores).and_return(mock_vector_stores)
        allow(mock_client).to receive(:vector_store_files).and_return(mock_vector_store_files)
        allow(mock_client).to receive(:files).and_return(mock_files)

        # Reset memoized client between tests
        described_class.instance_variable_set(:@client, nil)
      end

      describe ".list_vector_stores" do
        it "returns list of vector stores" do
          allow(mock_vector_stores).to receive(:list).and_return({
            "data" => [
              {
                "id" => "vs_123",
                "name" => "Test Store",
                "status" => "completed",
                "file_counts" => { "total" => 5 },
                "created_at" => 1234567890
              }
            ]
          })

          result = described_class.list_vector_stores

          expect(result).to eq([
            {
              id: "vs_123",
              name: "Test Store",
              status: "completed",
              file_counts: { "total" => 5 },
              created_at: Time.at(1234567890)
            }
          ])
        end

        it "returns empty array when no data" do
          allow(mock_vector_stores).to receive(:list).and_return({})

          result = described_class.list_vector_stores
          expect(result).to eq([])
        end
      end

      describe ".retrieve_vector_store" do
        it "returns vector store data" do
          allow(mock_vector_stores).to receive(:retrieve).with(id: "vs_123").and_return({
            "id" => "vs_123",
            "name" => "My Documents",
            "status" => "completed",
            "file_counts" => { "total" => 10 },
            "created_at" => 1234567890
          })

          result = described_class.retrieve_vector_store(id: "vs_123")

          expect(result).to eq({
            id: "vs_123",
            name: "My Documents",
            status: "completed",
            file_counts: { "total" => 10 },
            created_at: Time.at(1234567890)
          })
        end

        it "handles nil created_at" do
          allow(mock_vector_stores).to receive(:retrieve).with(id: "vs_123").and_return({
            "id" => "vs_123",
            "name" => "My Documents",
            "status" => "completed",
            "file_counts" => nil,
            "created_at" => nil
          })

          result = described_class.retrieve_vector_store(id: "vs_123")

          expect(result[:id]).to eq("vs_123")
          expect(result[:name]).to eq("My Documents")
          expect(result[:created_at]).to be_nil
        end
      end

      describe ".create_vector_store" do
        it "creates vector store without file_ids" do
          allow(mock_vector_stores).to receive(:create).with(
            parameters: { name: "My Store" }
          ).and_return({
            "id" => "vs_456",
            "name" => "My Store",
            "status" => "completed",
            "file_counts" => { "total" => 0 },
            "created_at" => 1234567890
          })

          result = described_class.create_vector_store(name: "My Store")

          expect(result).to eq({
            id: "vs_456",
            name: "My Store",
            status: "completed",
            file_counts: { "total" => 0 },
            created_at: Time.at(1234567890)
          })
        end

        it "creates vector store with file_ids" do
          allow(mock_vector_stores).to receive(:create).with(
            parameters: { name: "My Store", file_ids: [ "file_123" ] }
          ).and_return({
            "id" => "vs_456",
            "name" => "My Store",
            "status" => "in_progress",
            "file_counts" => { "total" => 1 },
            "created_at" => 1234567890
          })

          result = described_class.create_vector_store(name: "My Store", file_ids: [ "file_123" ])

          expect(result[:id]).to eq("vs_456")
          expect(result[:status]).to eq("in_progress")
        end
      end

      describe ".list_vector_store_files" do
        it "returns list of files with details" do
          allow(mock_vector_store_files).to receive(:list).with(
            vector_store_id: "vs_123"
          ).and_return({
            "data" => [
              {
                "id" => "file_456",
                "vector_store_id" => "vs_123",
                "status" => "completed",
                "created_at" => 1234567890
              }
            ]
          })

          allow(Rails.cache).to receive(:fetch).with("openai_file_file_456", expires_in: 1.hour).and_return({
            "filename" => "document.pdf",
            "bytes" => 12345
          })

          result = described_class.list_vector_store_files(vector_store_id: "vs_123")

          expect(result).to eq([
            {
              id: "file_456",
              vector_store_id: "vs_123",
              status: "completed",
              filename: "document.pdf",
              bytes: 12345,
              created_at: Time.at(1234567890)
            }
          ])
        end

        it "returns empty array when no data" do
          allow(mock_vector_store_files).to receive(:list).and_return({})

          result = described_class.list_vector_store_files(vector_store_id: "vs_123")
          expect(result).to eq([])
        end
      end

      describe ".add_file_to_vector_store" do
        it "adds file to vector store" do
          allow(mock_vector_store_files).to receive(:create).with(
            vector_store_id: "vs_123",
            parameters: { file_id: "file_456" }
          ).and_return({
            "id" => "vsf_789",
            "vector_store_id" => "vs_123",
            "status" => "in_progress",
            "created_at" => 1234567890
          })

          result = described_class.add_file_to_vector_store(
            vector_store_id: "vs_123",
            file_id: "file_456"
          )

          expect(result).to eq({
            id: "vsf_789",
            vector_store_id: "vs_123",
            status: "in_progress",
            created_at: Time.at(1234567890)
          })
        end
      end

      describe ".get_vector_store_file_status" do
        it "returns file status" do
          allow(mock_vector_store_files).to receive(:retrieve).with(
            vector_store_id: "vs_123",
            id: "file_456"
          ).and_return({
            "id" => "file_456",
            "vector_store_id" => "vs_123",
            "status" => "completed",
            "last_error" => nil
          })

          result = described_class.get_vector_store_file_status(
            vector_store_id: "vs_123",
            file_id: "file_456"
          )

          expect(result).to eq({
            status: "completed",
            id: "file_456",
            vector_store_id: "vs_123",
            last_error: nil
          })
        end

        it "returns error information when file processing failed" do
          allow(mock_vector_store_files).to receive(:retrieve).with(
            vector_store_id: "vs_123",
            id: "file_456"
          ).and_return({
            "id" => "file_456",
            "vector_store_id" => "vs_123",
            "status" => "failed",
            "last_error" => { "message" => "File too large" }
          })

          result = described_class.get_vector_store_file_status(
            vector_store_id: "vs_123",
            file_id: "file_456"
          )

          expect(result[:status]).to eq("failed")
          expect(result[:last_error]).to eq({ "message" => "File too large" })
        end
      end
    end
  end
end
