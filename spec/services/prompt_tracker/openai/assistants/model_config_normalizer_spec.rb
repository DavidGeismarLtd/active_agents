# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    module Assistants
      RSpec.describe ModelConfigNormalizer do
        describe ".normalize" do
          let(:base_assistant_data) do
            {
              "id" => "asst_abc123",
              "model" => "gpt-4o",
              "name" => "Math Tutor",
              "description" => "Helps with math problems",
              "temperature" => 0.8,
              "top_p" => 0.9
            }
          end

          context "with tools in OpenAI hash format" do
            let(:assistant_data) do
              base_assistant_data.merge(
                "tools" => [
                  { "type" => "file_search", "file_search" => { "ranking_options" => { "ranker" => "auto" } } },
                  { "type" => "code_interpreter" }
                ],
                "tool_resources" => {
                  "file_search" => {
                    "vector_store_ids" => [ "vs_123", "vs_456" ]
                  }
                }
              )
            end

            let(:openai_client) { instance_double(OpenAI::Client) }
            let(:vector_stores_api) { instance_double("VectorStores") }

            before do
              # Mock OpenAI client and vector store API calls
              allow_any_instance_of(described_class).to receive(:openai_client).and_return(openai_client)
              allow(openai_client).to receive(:vector_stores).and_return(vector_stores_api)

              # Mock vector store retrieval calls
              allow(vector_stores_api).to receive(:retrieve).with(id: "vs_123").and_return({
                "id" => "vs_123",
                "name" => "Product Documentation"
              })
              allow(vector_stores_api).to receive(:retrieve).with(id: "vs_456").and_return({
                "id" => "vs_456",
                "name" => "Support Articles"
              })
            end

            it "normalizes tools to string array" do
              result = described_class.normalize(assistant_data)

              expect(result[:tools]).to eq([ "file_search", "code_interpreter" ])
            end

            it "preserves tool_resources as-is" do
              result = described_class.normalize(assistant_data)

              expect(result[:tool_resources]).to eq({
                "file_search" => {
                  "vector_store_ids" => [ "vs_123", "vs_456" ]
                }
              })
            end

            it "creates unified tool_config with vector store names" do
              result = described_class.normalize(assistant_data)

              expect(result[:tool_config]).to eq({
                "file_search" => {
                  "vector_store_ids" => [ "vs_123", "vs_456" ],
                  "vector_stores" => [
                    { "id" => "vs_123", "name" => "Product Documentation" },
                    { "id" => "vs_456", "name" => "Support Articles" }
                  ]
                }
              })
            end

            it "falls back to ID as name when API call fails" do
              # Mock API failure for one vector store
              allow(vector_stores_api).to receive(:retrieve).with(id: "vs_123").and_raise(StandardError.new("API Error"))

              result = described_class.normalize(assistant_data)

              expect(result[:tool_config]["file_search"]["vector_stores"]).to include(
                { "id" => "vs_123", "name" => "vs_123" }  # Falls back to ID
              )
              expect(result[:tool_config]["file_search"]["vector_stores"]).to include(
                { "id" => "vs_456", "name" => "Support Articles" }  # Successful fetch
              )
            end

            it "sets correct provider and api" do
              result = described_class.normalize(assistant_data)

              expect(result[:provider]).to eq("openai")
              expect(result[:api]).to eq("assistants")
            end

            it "includes assistant_id" do
              result = described_class.normalize(assistant_data)

              expect(result[:assistant_id]).to eq("asst_abc123")
            end

            it "includes model configuration" do
              result = described_class.normalize(assistant_data)

              expect(result[:model]).to eq("gpt-4o")
              expect(result[:temperature]).to eq(0.8)
              expect(result[:top_p]).to eq(0.9)
            end

            it "includes metadata with assistant info" do
              result = described_class.normalize(assistant_data)

              expect(result[:metadata]).to include(
                name: "Math Tutor",
                description: "Helps with math problems"
              )
              expect(result[:metadata][:synced_at]).to be_present
            end
          end

          context "with tools in legacy string format" do
            let(:assistant_data) do
              base_assistant_data.merge(
                "tools" => [ "file_search", "code_interpreter" ]
              )
            end

            it "preserves string array format" do
              result = described_class.normalize(assistant_data)

              expect(result[:tools]).to eq([ "file_search", "code_interpreter" ])
            end
          end

          context "with mixed tool formats" do
            let(:assistant_data) do
              base_assistant_data.merge(
                "tools" => [
                  { "type" => "file_search" },
                  "code_interpreter",
                  { "type" => "functions", "function" => { "name" => "get_weather" } }
                ]
              )
            end

            it "normalizes all tools to strings" do
              result = described_class.normalize(assistant_data)

              expect(result[:tools]).to eq([ "file_search", "code_interpreter", "functions" ])
            end
          end

          context "with no tools" do
            let(:assistant_data) { base_assistant_data }

            it "returns empty tools array" do
              result = described_class.normalize(assistant_data)

              expect(result[:tools]).to eq([])
            end

            it "returns empty tool_resources hash" do
              result = described_class.normalize(assistant_data)

              expect(result[:tool_resources]).to eq({})
            end

            it "returns empty tool_config hash" do
              result = described_class.normalize(assistant_data)

              expect(result[:tool_config]).to eq({})
            end
          end

          context "with nil or invalid tool entries" do
            let(:assistant_data) do
              base_assistant_data.merge(
                "tools" => [
                  { "type" => "file_search" },
                  nil,
                  { "type" => "" },
                  { "no_type_key" => "value" },
                  "code_interpreter"
                ]
              )
            end

            it "filters out nil and invalid entries" do
              result = described_class.normalize(assistant_data)

              expect(result[:tools]).to eq([ "file_search", "code_interpreter" ])
            end
          end

          context "with default temperature and top_p" do
            let(:assistant_data) do
              base_assistant_data.except("temperature", "top_p")
            end

            it "uses default values" do
              result = described_class.normalize(assistant_data)

              expect(result[:temperature]).to eq(0.7)
              expect(result[:top_p]).to eq(1.0)
            end
          end
        end
      end
    end
  end
end
