# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        RSpec.describe PullService do
          let(:prompt) { create(:prompt, name: "Test Assistant") }
          let(:prompt_version) do
            create(:prompt_version,
              prompt: prompt,
              system_prompt: "Original instructions",
              notes: "Original description",
              model_config: {
                provider: "openai",
                api: "assistants",
                model: "gpt-4o",
                temperature: 0.7,
                assistant_id: "asst_abc123"
              })
          end

          let(:openai_client) { instance_double(OpenAI::Client) }
          let(:assistants_api) { instance_double("Assistants") }

          before do
            allow(OpenAI::Client).to receive(:new).and_return(openai_client)
            allow(openai_client).to receive(:assistants).and_return(assistants_api)
            allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test-api-key")
          end

          describe ".call" do
            let(:assistant_response) do
              {
                "id" => "asst_abc123",
                "model" => "gpt-4o-mini",
                "instructions" => "Updated instructions from OpenAI",
                "name" => "Test Assistant",
                "description" => "Updated description",
                "temperature" => 0.9,
                "tools" => [ { "type" => "code_interpreter" } ]
              }
            end

            it "fetches assistant data from OpenAI" do
              expect(assistants_api).to receive(:retrieve).with(id: "asst_abc123").and_return(assistant_response)

              result = described_class.call(prompt_version: prompt_version)

              expect(result.success?).to be true
            end

            it "updates PromptVersion with remote data" do
              allow(assistants_api).to receive(:retrieve).and_return(assistant_response)

              described_class.call(prompt_version: prompt_version)

              prompt_version.reload
              expect(prompt_version.system_prompt).to eq("Updated instructions from OpenAI")
              expect(prompt_version.notes).to eq("Updated description")
              expect(prompt_version.model_config["model"]).to eq("gpt-4o-mini")
              expect(prompt_version.model_config["temperature"]).to eq(0.9)
            end

            it "returns the updated prompt_version in result" do
              allow(assistants_api).to receive(:retrieve).and_return(assistant_response)

              result = described_class.call(prompt_version: prompt_version)

              expect(result.prompt_version).to eq(prompt_version)
              expect(result.synced_at).to be_present
            end

            it "returns failure result when assistant_id is missing" do
              prompt_version.update!(model_config: { provider: "openai", api: "assistants" })

              result = described_class.call(prompt_version: prompt_version)

              expect(result.success?).to be false
              expect(result.errors).to include(/No assistant_id/)
            end

            it "returns failure result on API error" do
              allow(assistants_api).to receive(:retrieve).and_raise(StandardError.new("API Error"))

              result = described_class.call(prompt_version: prompt_version)

              expect(result.success?).to be false
              expect(result.errors).to include("API Error")
            end

            context "with tools in response" do
              let(:assistant_response) do
                {
                  "id" => "asst_abc123",
                  "model" => "gpt-4o",
                  "instructions" => "Instructions with tools",
                  "name" => "Test Assistant",
                  "tools" => [
                    { "type" => "code_interpreter" },
                    { "type" => "file_search" }
                  ]
                }
              end

              it "converts tools to PromptTracker format" do
                allow(assistants_api).to receive(:retrieve).and_return(assistant_response)

                described_class.call(prompt_version: prompt_version)

                prompt_version.reload
                # Symbols are converted to strings when stored in JSON
                expect(prompt_version.model_config["tools"]).to include("code_interpreter")
                expect(prompt_version.model_config["tools"]).to include("file_search")
              end
            end
          end
        end
      end
    end
  end
end
