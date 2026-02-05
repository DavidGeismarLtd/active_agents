# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe VectorStoreService, type: :service do
    describe ".list_vector_stores" do
      it "delegates to Openai::VectorStoreOperations for :openai provider" do
        expect(Openai::VectorStoreOperations).to receive(:list_vector_stores).and_return([
          { id: "vs_123", name: "Test Store" }
        ])

        result = described_class.list_vector_stores(provider: :openai)
        expect(result).to eq([ { id: "vs_123", name: "Test Store" } ])
      end

      it "raises VectorStoreError for unsupported provider" do
        expect {
          described_class.list_vector_stores(provider: :unsupported)
        }.to raise_error(VectorStoreService::VectorStoreError, "Unsupported provider: unsupported")
      end
    end

    describe ".create_vector_store" do
      it "delegates to Openai::VectorStoreOperations for :openai provider" do
        expect(Openai::VectorStoreOperations).to receive(:create_vector_store).with(
          name: "My Store",
          file_ids: [ "file_123" ]
        ).and_return({ id: "vs_456", name: "My Store" })

        result = described_class.create_vector_store(
          provider: :openai,
          name: "My Store",
          file_ids: [ "file_123" ]
        )
        expect(result).to eq({ id: "vs_456", name: "My Store" })
      end

      it "passes empty file_ids by default" do
        expect(Openai::VectorStoreOperations).to receive(:create_vector_store).with(
          name: "My Store",
          file_ids: []
        ).and_return({ id: "vs_456", name: "My Store" })

        described_class.create_vector_store(provider: :openai, name: "My Store")
      end

      it "raises VectorStoreError for unsupported provider" do
        expect {
          described_class.create_vector_store(provider: :unsupported, name: "Test")
        }.to raise_error(VectorStoreService::VectorStoreError, "Unsupported provider: unsupported")
      end
    end

    describe ".list_vector_store_files" do
      it "delegates to Openai::VectorStoreOperations for :openai provider" do
        expect(Openai::VectorStoreOperations).to receive(:list_vector_store_files).with(
          vector_store_id: "vs_123"
        ).and_return([ { id: "file_456", filename: "doc.pdf" } ])

        result = described_class.list_vector_store_files(
          provider: :openai,
          vector_store_id: "vs_123"
        )
        expect(result).to eq([ { id: "file_456", filename: "doc.pdf" } ])
      end

      it "raises VectorStoreError for unsupported provider" do
        expect {
          described_class.list_vector_store_files(provider: :unsupported, vector_store_id: "vs_123")
        }.to raise_error(VectorStoreService::VectorStoreError, "Unsupported provider: unsupported")
      end
    end

    describe ".add_file_to_vector_store" do
      it "delegates to Openai::VectorStoreOperations for :openai provider" do
        expect(Openai::VectorStoreOperations).to receive(:add_file_to_vector_store).with(
          vector_store_id: "vs_123",
          file_id: "file_456"
        ).and_return({ id: "vsf_789", status: "completed" })

        result = described_class.add_file_to_vector_store(
          provider: :openai,
          vector_store_id: "vs_123",
          file_id: "file_456"
        )
        expect(result).to eq({ id: "vsf_789", status: "completed" })
      end

      it "raises VectorStoreError for unsupported provider" do
        expect {
          described_class.add_file_to_vector_store(
            provider: :unsupported,
            vector_store_id: "vs_123",
            file_id: "file_456"
          )
        }.to raise_error(VectorStoreService::VectorStoreError, "Unsupported provider: unsupported")
      end
    end

    describe ".get_vector_store_file_status" do
      it "delegates to Openai::VectorStoreOperations for :openai provider" do
        expect(Openai::VectorStoreOperations).to receive(:get_vector_store_file_status).with(
          vector_store_id: "vs_123",
          file_id: "file_456"
        ).and_return({ status: "completed", id: "file_456" })

        result = described_class.get_vector_store_file_status(
          provider: :openai,
          vector_store_id: "vs_123",
          file_id: "file_456"
        )
        expect(result).to eq({ status: "completed", id: "file_456" })
      end

      it "raises VectorStoreError for unsupported provider" do
        expect {
          described_class.get_vector_store_file_status(
            provider: :unsupported,
            vector_store_id: "vs_123",
            file_id: "file_456"
          )
        }.to raise_error(VectorStoreService::VectorStoreError, "Unsupported provider: unsupported")
      end
    end
  end
end
