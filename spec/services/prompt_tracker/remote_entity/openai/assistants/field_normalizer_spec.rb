# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module RemoteEntity
    module Openai
      module Assistants
        RSpec.describe FieldNormalizer do
          let(:prompt) { create(:prompt, name: "Test Assistant", slug: "test_assistant") }
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
                top_p: 1.0,
                tools: [ :code_interpreter, :file_search ]
              })
          end

          describe ".to_openai" do
            it "converts PromptVersion to OpenAI format" do
              result = described_class.to_openai(prompt_version)

              expect(result[:model]).to eq("gpt-4o")
              expect(result[:name]).to eq("Test Assistant")
              expect(result[:instructions]).to eq("You are a helpful assistant.")
              expect(result[:description]).to eq("Test description")
              expect(result[:temperature]).to eq(0.7)
              expect(result[:top_p]).to eq(1.0)
            end

            it "formats tools array correctly" do
              result = described_class.to_openai(prompt_version)

              expect(result[:tools]).to eq([
                { "type" => "code_interpreter" },
                { "type" => "file_search" }
              ])
            end

            it "includes metadata with version information as strings" do
              result = described_class.to_openai(prompt_version)

              # OpenAI requires all metadata values to be strings
              expect(result[:metadata][:prompt_id]).to eq(prompt.id.to_s)
              expect(result[:metadata][:prompt_slug]).to eq("test_assistant")
              expect(result[:metadata][:version_id]).to eq(prompt_version.id.to_s)
              expect(result[:metadata][:version_number]).to eq(prompt_version.version_number.to_s)
              expect(result[:metadata][:managed_by]).to eq("prompt_tracker")
              expect(result[:metadata][:last_synced_at]).to be_present
            end

            it "handles empty tools array" do
              prompt_version.update!(model_config: { tools: [] })
              result = described_class.to_openai(prompt_version)

              expect(result[:tools]).to eq([])
            end

            it "converts tool_config to tool_resources format" do
              prompt_version.update!(model_config: {
                provider: "openai",
                api: "assistants",
                model: "gpt-4o",
                tools: [ :file_search ],
                tool_config: {
                  "file_search" => {
                    "vector_store_ids" => [ "vs_abc123" ],
                    "vector_stores" => [ { "id" => "vs_abc123", "name" => "My Store" } ]
                  }
                }
              })
              result = described_class.to_openai(prompt_version)

              expect(result[:tool_resources]).to eq({
                "file_search" => { "vector_store_ids" => [ "vs_abc123" ] }
              })
            end

            it "returns nil tool_resources when tool_config is empty" do
              prompt_version.update!(model_config: { tools: [], tool_config: {} })
              result = described_class.to_openai(prompt_version)

              expect(result[:tool_resources]).to be_nil
            end
          end

          describe ".from_openai" do
            let(:assistant_data) do
              {
                "id" => "asst_abc123",
                "model" => "gpt-4o",
                "name" => "Test Assistant",
                "instructions" => "You are a helpful assistant.",
                "description" => "Test description",
                "temperature" => 0.7,
                "top_p" => 1.0,
                "tools" => [
                  { "type" => "code_interpreter" },
                  { "type" => "file_search" }
                ],
                "tool_resources" => {
                  "file_search" => {
                    "vector_store_ids" => [ "vs_abc123", "vs_def456" ]
                  }
                }
              }
            end

            it "converts OpenAI data to PromptTracker format" do
              result = described_class.from_openai(assistant_data)

              expect(result[:system_prompt]).to eq("You are a helpful assistant.")
              expect(result[:notes]).to eq("Test description")
            end

            it "builds model_config correctly" do
              result = described_class.from_openai(assistant_data)

              expect(result[:model_config][:provider]).to eq("openai")
              expect(result[:model_config][:api]).to eq("assistants")
              expect(result[:model_config][:assistant_id]).to eq("asst_abc123")
              expect(result[:model_config][:model]).to eq("gpt-4o")
              expect(result[:model_config][:temperature]).to eq(0.7)
              expect(result[:model_config][:top_p]).to eq(1.0)
            end

            it "formats tools array correctly" do
              result = described_class.from_openai(assistant_data)

              expect(result[:model_config][:tools]).to eq([ :code_interpreter, :file_search ])
            end

            it "converts tool_resources to tool_config format" do
              result = described_class.from_openai(assistant_data)

              expect(result[:model_config][:tool_config]).to eq({
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ],
                  "vector_stores" => [
                    { "id" => "vs_abc123", "name" => "vs_abc123" },
                    { "id" => "vs_def456", "name" => "vs_def456" }
                  ]
                }
              })
            end

            it "handles empty tool_resources" do
              assistant_data["tool_resources"] = {}
              result = described_class.from_openai(assistant_data)

              expect(result[:model_config][:tool_config]).to eq({})
            end

            it "includes metadata" do
              result = described_class.from_openai(assistant_data)

              expect(result[:model_config][:metadata][:name]).to eq("Test Assistant")
              expect(result[:model_config][:metadata][:description]).to eq("Test description")
              expect(result[:model_config][:metadata][:synced_at]).to be_present
              expect(result[:model_config][:metadata][:synced_from]).to eq("openai")
            end
          end

          describe ".format_tools_for_openai" do
            it "converts symbol array to hash array" do
              result = described_class.format_tools_for_openai([ :code_interpreter, :file_search ])

              expect(result).to eq([
                { "type" => "code_interpreter" },
                { "type" => "file_search" }
              ])
            end

            it "handles already formatted tools" do
              tools = [ { "type" => "code_interpreter" } ]
              result = described_class.format_tools_for_openai(tools)

              expect(result).to eq(tools)
            end

            it "returns empty array for nil" do
              expect(described_class.format_tools_for_openai(nil)).to eq([])
            end
          end

          describe ".format_tools_from_openai" do
            it "converts hash array to symbol array" do
              tools = [
                { "type" => "code_interpreter" },
                { "type" => "file_search" }
              ]
              result = described_class.format_tools_from_openai(tools)

              expect(result).to eq([ :code_interpreter, :file_search ])
            end

            it "returns empty array for nil" do
              expect(described_class.format_tools_from_openai(nil)).to eq([])
            end
          end

          describe ".format_tool_config_from_openai" do
            it "converts file_search tool_resources to tool_config" do
              tool_resources = {
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ]
                }
              }
              result = described_class.format_tool_config_from_openai(tool_resources)

              expect(result).to eq({
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ],
                  "vector_stores" => [
                    { "id" => "vs_abc123", "name" => "vs_abc123" },
                    { "id" => "vs_def456", "name" => "vs_def456" }
                  ]
                }
              })
            end

            it "uses provided vector_store_names when available" do
              tool_resources = {
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ]
                }
              }
              vector_store_names = {
                "vs_abc123" => "My Documents",
                "vs_def456" => "Knowledge Base"
              }

              result = described_class.format_tool_config_from_openai(tool_resources, vector_store_names: vector_store_names)

              expect(result).to eq({
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ],
                  "vector_stores" => [
                    { "id" => "vs_abc123", "name" => "My Documents" },
                    { "id" => "vs_def456", "name" => "Knowledge Base" }
                  ]
                }
              })
            end

            it "falls back to ID when vector_store_names is missing for an ID" do
              tool_resources = {
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123", "vs_def456" ]
                }
              }
              vector_store_names = {
                "vs_abc123" => "My Documents"
                # vs_def456 is not in the hash
              }

              result = described_class.format_tool_config_from_openai(tool_resources, vector_store_names: vector_store_names)

              expect(result["file_search"]["vector_stores"]).to eq([
                { "id" => "vs_abc123", "name" => "My Documents" },
                { "id" => "vs_def456", "name" => "vs_def456" }
              ])
            end

            it "returns empty hash for nil" do
              expect(described_class.format_tool_config_from_openai(nil)).to eq({})
            end

            it "returns empty hash for empty hash" do
              expect(described_class.format_tool_config_from_openai({})).to eq({})
            end
          end

          describe ".format_tool_resources_for_openai" do
            it "converts file_search tool_config to tool_resources" do
              tool_config = {
                "file_search" => {
                  "vector_store_ids" => [ "vs_abc123" ],
                  "vector_stores" => [ { "id" => "vs_abc123", "name" => "My Store" } ]
                }
              }
              result = described_class.format_tool_resources_for_openai(tool_config)

              expect(result).to eq({
                "file_search" => { "vector_store_ids" => [ "vs_abc123" ] }
              })
            end

            it "returns nil for nil" do
              expect(described_class.format_tool_resources_for_openai(nil)).to be_nil
            end

            it "returns nil for empty hash" do
              expect(described_class.format_tool_resources_for_openai({})).to be_nil
            end

            it "handles symbol keys" do
              tool_config = {
                file_search: {
                  vector_store_ids: [ "vs_abc123" ]
                }
              }
              result = described_class.format_tool_resources_for_openai(tool_config)

              expect(result).to eq({
                "file_search" => { "vector_store_ids" => [ "vs_abc123" ] }
              })
            end
          end
        end
      end
    end
  end
end
