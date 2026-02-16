# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe SyncOpenaiAssistantsToPromptVersionsService, type: :service do
    let(:mock_client) { instance_double(OpenAI::Client) }
    let(:mock_assistants) { double("assistants") }

    let(:assistant_data_1) do
      {
        "id" => "asst_123",
        "name" => "Customer Support Assistant",
        "description" => "Helps with customer inquiries",
        "instructions" => "You are a helpful customer support assistant.",
        "model" => "gpt-4o",
        "temperature" => 0.7,
        "top_p" => 1.0,
        "tools" => [ { "type" => "code_interpreter" } ],
        "tool_resources" => { "code_interpreter" => { "file_ids" => [] } }
      }
    end

    let(:assistant_data_2) do
      {
        "id" => "asst_456",
        "name" => "Sales Assistant",
        "description" => "Helps with sales questions",
        "instructions" => "You are a sales expert.",
        "model" => "gpt-4o-mini",
        "temperature" => 0.5,
        "top_p" => 0.9,
        "tools" => [],
        "tool_resources" => {}
      }
    end

    before do
      # Reset cached client in VectorStoreOperations to prevent mock leaks between tests
      PromptTracker::Openai::VectorStoreOperations.instance_variable_set(:@client, nil)

      # Stub configuration
      allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test_api_key")

      # Stub OpenAI client
      allow(OpenAI::Client).to receive(:new).with(access_token: "test_api_key").and_return(mock_client)
      allow(mock_client).to receive(:assistants).and_return(mock_assistants)
      allow(mock_assistants).to receive(:list).and_return({
        "data" => [ assistant_data_1, assistant_data_2 ]
      })
    end

    describe "#call" do
      it "returns a result hash with success and counts" do
        result = described_class.new.call

        expect(result).to include(
          success: true,
          created_count: 2,
          created_prompts: be_an(Array),
          created_versions: be_an(Array),
          errors: []
        )
      end

      it "creates Prompts from OpenAI assistants" do
        expect {
          described_class.new.call
        }.to change(Prompt, :count).by(2)
      end

      it "creates PromptVersions from OpenAI assistants" do
        expect {
          described_class.new.call
        }.to change(PromptVersion, :count).by(2)
      end

      it "creates one Prompt per assistant" do
        result = described_class.new.call

        expect(result[:created_prompts].count).to eq(2)
        expect(result[:created_versions].count).to eq(2)
      end

      it "creates prompts with unique slugs based on assistant_id" do
        result = described_class.new.call

        prompts = result[:created_prompts]
        expect(prompts[0].slug).to eq("assistant_asst_123")
        expect(prompts[1].slug).to eq("assistant_asst_456")
      end

      it "creates prompts with assistant name" do
        result = described_class.new.call

        prompts = result[:created_prompts]
        expect(prompts[0].name).to eq("Customer Support Assistant")
        expect(prompts[1].name).to eq("Sales Assistant")
      end

      it "creates prompts with category 'assistant'" do
        result = described_class.new.call

        prompts = result[:created_prompts]
        expect(prompts[0].category).to eq("assistant")
        expect(prompts[1].category).to eq("assistant")
      end

      it "creates version_number 1 for each prompt" do
        result = described_class.new.call

        versions = result[:created_versions]
        expect(versions[0].version_number).to eq(1)
        expect(versions[1].version_number).to eq(1)
      end

      it "stores assistant_id in model_config[:assistant_id]" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["assistant_id"]).to eq("asst_123")
      end

      it "stores model name in model_config[:model]" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["model"]).to eq("gpt-4o")
      end

      it "stores api as 'assistants' in model_config" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["api"]).to eq("assistants")
      end

      it "stores provider as 'openai' in model_config" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["provider"]).to eq("openai")
      end

      it "stores instructions in system_prompt" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.system_prompt).to eq("You are a helpful customer support assistant.")
      end

      it "sets user_prompt to default template" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.user_prompt).to eq("{{user_message}}")
      end

      it "sets status to draft" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.status).to eq("draft")
      end

      it "stores temperature in model_config" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["temperature"]).to eq(0.7)
      end

      it "stores tools in model_config as normalized string array" do
        result = described_class.new.call

        version = result[:created_versions].first
        # Tools should be normalized from hash format to string array
        expect(version.model_config["tools"]).to eq([ "code_interpreter" ])
      end

      it "stores tool_config in model_config (converted from tool_resources)" do
        result = described_class.new.call

        version = result[:created_versions].first
        # FieldNormalizer converts tool_resources to tool_config format
        expect(version.model_config["tool_config"]).to eq({ "code_interpreter" => { "file_ids" => [] } })
      end

      it "stores assistant metadata in model_config" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.model_config["metadata"]["name"]).to eq("Customer Support Assistant")
        expect(version.model_config["metadata"]["description"]).to eq("Helps with customer inquiries")
        expect(version.model_config["metadata"]["synced_at"]).to be_present
      end

      it "adds notes indicating sync source" do
        result = described_class.new.call

        version = result[:created_versions].first
        expect(version.notes).to include("Synced from OpenAI Assistant")
        expect(version.notes).to include("Customer Support Assistant")
      end

      context "with complex tools including file_search" do
        let(:assistant_with_file_search) do
          {
            "id" => "asst_789",
            "name" => "Research Assistant",
            "description" => "Helps with research",
            "instructions" => "You are a research assistant.",
            "model" => "gpt-4o",
            "temperature" => 0.7,
            "top_p" => 1.0,
            "tools" => [
              { "type" => "file_search", "file_search" => { "ranking_options" => { "ranker" => "auto" } } },
              { "type" => "code_interpreter" }
            ],
            "tool_resources" => {
              "file_search" => {
                "vector_store_ids" => [ "vs_123", "vs_456" ]
              }
            }
          }
        end

        let(:mock_vector_stores) { double("vector_stores") }

        before do
          allow(mock_assistants).to receive(:list).and_return({
            "data" => [ assistant_with_file_search ]
          })

          # Mock vector_stores API for fetching vector store names
          allow(mock_client).to receive(:vector_stores).and_return(mock_vector_stores)
          allow(mock_vector_stores).to receive(:retrieve).with(id: "vs_123").and_return({ "name" => "Research Documents" })
          allow(mock_vector_stores).to receive(:retrieve).with(id: "vs_456").and_return({ "name" => "Knowledge Base" })
        end

        it "normalizes tools from hash format to string array" do
          result = described_class.new.call

          version = result[:created_versions].first
          # FieldNormalizer converts tools to symbols, but JSON serialization converts them back to strings
          expect(version.model_config["tools"]).to eq([ "file_search", "code_interpreter" ])
        end

        it "preserves tool_config with vector store configuration" do
          result = described_class.new.call

          version = result[:created_versions].first
          # FieldNormalizer converts tool_resources to tool_config format with vector store names
          expect(version.model_config["tool_config"]).to eq({
            "file_search" => {
              "vector_store_ids" => [ "vs_123", "vs_456" ],
              "vector_stores" => [
                { "id" => "vs_123", "name" => "Research Documents" },
                { "id" => "vs_456", "name" => "Knowledge Base" }
              ]
            }
          })
        end
      end

      context "when API call fails" do
        before do
          allow(mock_assistants).to receive(:list).and_raise(StandardError.new("API error"))
        end

        it "returns success: false" do
          result = described_class.new.call

          expect(result[:success]).to be false
        end

        it "includes error message" do
          result = described_class.new.call

          expect(result[:errors]).to include(/Failed to fetch assistants/)
        end

        it "does not create any prompts or versions" do
          expect {
            described_class.new.call
          }.not_to change(Prompt, :count)
        end
      end

      context "when Prompt creation fails" do
        before do
          # Make the first prompt creation fail
          allow_any_instance_of(Prompt).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new)
        end

        it "continues processing other assistants" do
          result = described_class.new.call

          expect(result[:errors].size).to eq(2)
          expect(result[:created_count]).to eq(0)
        end

        it "includes error messages" do
          result = described_class.new.call

          expect(result[:errors].first).to include("Failed to create prompt/version")
        end
      end

      context "when API key is not configured" do
        before do
          allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return(nil)
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
        end

        it "raises SyncError" do
          expect {
            described_class.new.call
          }.to raise_error(SyncOpenaiAssistantsToPromptVersionsService::SyncError, /OpenAI API key not configured/)
        end
      end

      context "when API returns empty data" do
        before do
          allow(mock_assistants).to receive(:list).and_return({ "data" => [] })
        end

        it "returns success with zero count" do
          result = described_class.new.call

          expect(result).to include(
            success: true,
            created_count: 0,
            created_prompts: [],
            created_versions: [],
            errors: []
          )
        end
      end

      context "when API returns nil data" do
        before do
          allow(mock_assistants).to receive(:list).and_return({})
        end

        it "handles nil data gracefully" do
          result = described_class.new.call

          expect(result).to include(
            success: true,
            created_count: 0,
            created_prompts: [],
            created_versions: [],
            errors: []
          )
        end
      end
    end
  end
end
