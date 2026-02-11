# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        RSpec.describe CreateAsPromptVersionService do
          describe ".call" do
            let(:assistant_data) do
              {
                "id" => "asst_abc123",
                "model" => "gpt-4o",
                "instructions" => "You are a helpful assistant.",
                "name" => "Test Assistant",
                "description" => "A test assistant description",
                "temperature" => 0.7,
                "tools" => [ { "type" => "code_interpreter" } ]
              }
            end

            it "creates a Prompt with correct attributes" do
              result = described_class.call(assistant_data: assistant_data)

              expect(result.success?).to be true
              expect(result.prompt).to be_persisted
              expect(result.prompt.name).to eq("Test Assistant")
              expect(result.prompt.category).to eq("assistant")
            end

            it "generates a unique slug based on assistant_id" do
              result = described_class.call(assistant_data: assistant_data)

              expect(result.prompt.slug).to eq("assistant_asst_abc123")
            end

            it "creates a PromptVersion with correct attributes" do
              result = described_class.call(assistant_data: assistant_data)

              expect(result.prompt_version).to be_persisted
              expect(result.prompt_version.system_prompt).to eq("You are a helpful assistant.")
              expect(result.prompt_version.version_number).to eq(1)
              expect(result.prompt_version.status).to eq("draft")
            end

            it "sets model_config with assistant_id" do
              result = described_class.call(assistant_data: assistant_data)

              model_config = result.prompt_version.model_config
              expect(model_config["assistant_id"]).to eq("asst_abc123")
              expect(model_config["model"]).to eq("gpt-4o")
              expect(model_config["provider"]).to eq("openai")
              expect(model_config["api"]).to eq("assistants")
            end

            it "sets default user_prompt template" do
              result = described_class.call(assistant_data: assistant_data)

              expect(result.prompt_version.user_prompt).to eq("{{user_message}}")
            end

            context "when assistant has no name" do
              let(:assistant_data) do
                {
                  "id" => "asst_xyz789",
                  "model" => "gpt-4o",
                  "instructions" => "Instructions only"
                }
              end

              it "uses fallback name" do
                result = described_class.call(assistant_data: assistant_data)

                expect(result.prompt.name).to eq("Assistant asst_xyz789")
              end
            end

            context "when slug already exists" do
              before do
                create(:prompt, slug: "assistant_asst_abc123")
              end

              it "generates unique slug with counter" do
                result = described_class.call(assistant_data: assistant_data)

                expect(result.prompt.slug).to eq("assistant_asst_abc123_1")
              end
            end

            context "with tools in assistant data" do
              let(:assistant_data) do
                {
                  "id" => "asst_tools123",
                  "model" => "gpt-4o",
                  "instructions" => "Assistant with tools",
                  "name" => "Tools Assistant",
                  "tools" => [
                    { "type" => "code_interpreter" },
                    { "type" => "file_search" }
                  ]
                }
              end

              it "converts tools to PromptTracker format" do
                result = described_class.call(assistant_data: assistant_data)

                # Symbols are converted to strings when stored in JSON
                tools = result.prompt_version.model_config["tools"]
                expect(tools).to include("code_interpreter")
                expect(tools).to include("file_search")
              end
            end

            context "when creation fails" do
              before do
                allow(Prompt).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Prompt.new))
              end

              it "returns failure result" do
                result = described_class.call(assistant_data: assistant_data)

                expect(result.success?).to be false
                expect(result.prompt).to be_nil
                expect(result.prompt_version).to be_nil
                expect(result.errors).not_to be_empty
              end
            end
          end
        end
      end
    end
  end
end
