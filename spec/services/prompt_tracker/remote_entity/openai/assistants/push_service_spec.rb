# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        RSpec.describe PushService do
          let(:prompt) { create(:prompt, name: "Test Assistant") }
          let(:prompt_version) do
            create(:prompt_version,
              prompt: prompt,
              system_prompt: "You are a helpful assistant.",
              notes: "Test description",
              model_config: {
                provider: "openai",
                api: "assistants",
                model: "gpt-4o",
                temperature: 0.7,
                tools: [ :code_interpreter ]
              })
          end

          let(:openai_client) { instance_double(OpenAI::Client) }
          let(:assistants_api) { instance_double("Assistants") }

          before do
            allow(OpenAI::Client).to receive(:new).and_return(openai_client)
            allow(openai_client).to receive(:assistants).and_return(assistants_api)
            allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test-api-key")
          end

          describe ".create" do
            let(:create_response) do
              {
                "id" => "asst_abc123",
                "model" => "gpt-4o",
                "instructions" => "You are a helpful assistant.",
                "name" => "Test Assistant",
                "description" => "Test description"
              }
            end

            it "creates a new assistant on OpenAI" do
              expect(assistants_api).to receive(:create).with(
                parameters: hash_including(
                  model: "gpt-4o",
                  instructions: "You are a helpful assistant.",
                  name: "Test Assistant"
                )
              ).and_return(create_response)

              result = described_class.create(prompt_version: prompt_version)

              expect(result.success?).to be true
              expect(result.assistant_id).to eq("asst_abc123")
            end

            it "updates PromptVersion with assistant_id" do
              allow(assistants_api).to receive(:create).and_return(create_response)

              described_class.create(prompt_version: prompt_version)

              prompt_version.reload
              expect(prompt_version.model_config["assistant_id"]).to eq("asst_abc123")
              expect(prompt_version.model_config["metadata"]["sync_status"]).to eq("synced")
              expect(prompt_version.model_config["metadata"]["synced_at"]).to be_present
            end

            it "returns failure result on error" do
              allow(assistants_api).to receive(:create).and_raise(StandardError.new("API Error"))

              result = described_class.create(prompt_version: prompt_version)

              expect(result.success?).to be false
              expect(result.errors).to include("API Error")
            end
          end

          describe ".update" do
            let(:update_response) do
              {
                "id" => "asst_abc123",
                "model" => "gpt-4o",
                "instructions" => "Updated instructions",
                "name" => "Test Assistant"
              }
            end

            before do
              prompt_version.update!(
                model_config: prompt_version.model_config.merge(assistant_id: "asst_abc123")
              )
            end

            it "updates an existing assistant on OpenAI" do
              expect(assistants_api).to receive(:modify).with(
                id: "asst_abc123",
                parameters: hash_including(
                  model: "gpt-4o",
                  instructions: "You are a helpful assistant."
                )
              ).and_return(update_response)

              result = described_class.update(prompt_version: prompt_version)

              expect(result.success?).to be true
              expect(result.assistant_id).to eq("asst_abc123")
            end

            it "updates sync metadata" do
              allow(assistants_api).to receive(:modify).and_return(update_response)

              described_class.update(prompt_version: prompt_version)

              prompt_version.reload
              expect(prompt_version.model_config["metadata"]["sync_status"]).to eq("synced")
              expect(prompt_version.model_config["metadata"]["synced_at"]).to be_present
            end

            it "returns failure result when assistant_id is missing" do
              prompt_version.update!(model_config: { provider: "openai", api: "assistants" })

              result = described_class.update(prompt_version: prompt_version)

              expect(result.success?).to be false
              expect(result.errors).to include(/No assistant_id/)
            end

            it "returns failure result on API error" do
              allow(assistants_api).to receive(:modify).and_raise(StandardError.new("API Error"))

              result = described_class.update(prompt_version: prompt_version)

              expect(result.success?).to be false
              expect(result.errors).to include("API Error")
            end
          end
        end
      end
    end
  end
end
