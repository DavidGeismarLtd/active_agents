# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    module Responses
      RSpec.describe ToolFormatter, type: :service do
        describe "#format" do
          context "with web_search tool" do
            it "formats to web_search_preview" do
              formatter = described_class.new(tools: [ :web_search ])

              result = formatter.format

              expect(result).to eq([ { type: "web_search_preview" } ])
            end
          end

          context "with code_interpreter tool" do
            it "formats correctly" do
              formatter = described_class.new(tools: [ :code_interpreter ])

              result = formatter.format

              expect(result).to eq([ { type: "code_interpreter" } ])
            end
          end

          context "with file_search tool" do
            it "formats without vector_store_ids when not configured" do
              formatter = described_class.new(tools: [ :file_search ])

              result = formatter.format

              expect(result).to eq([ { type: "file_search" } ])
            end

            it "includes vector_store_ids when configured" do
              formatter = described_class.new(
                tools: [ :file_search ],
                tool_config: { "file_search" => { "vector_store_ids" => [ "vs_123" ] } }
              )

              result = formatter.format

              expect(result).to eq([ { type: "file_search", vector_store_ids: [ "vs_123" ] } ])
            end

            it "limits vector_store_ids to 2" do
              formatter = described_class.new(
                tools: [ :file_search ],
                tool_config: { "file_search" => { "vector_store_ids" => [ "vs_1", "vs_2", "vs_3" ] } }
              )

              result = formatter.format

              expect(result[0][:vector_store_ids]).to eq([ "vs_1", "vs_2" ])
            end
          end

          context "with functions tool" do
            it "formats function definitions" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    {
                      "name" => "get_weather",
                      "description" => "Get the weather",
                      "parameters" => { "type" => "object", "properties" => {} }
                    }
                  ]
                }
              )

              result = formatter.format

              expect(result.length).to eq(1)
              expect(result[0][:type]).to eq("function")
              expect(result[0][:name]).to eq("get_weather")
              expect(result[0][:description]).to eq("Get the weather")
            end

            it "handles strict mode when true" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    { "name" => "test", "strict" => true }
                  ]
                }
              )

              result = formatter.format

              expect(result[0][:strict]).to eq(true)
            end

            it "handles strict mode when false" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    { "name" => "test", "strict" => false }
                  ]
                }
              )

              result = formatter.format

              expect(result[0][:strict]).to eq(false)
            end

            it "omits strict when not specified" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    { "name" => "test" }
                  ]
                }
              )

              result = formatter.format

              expect(result[0]).not_to have_key(:strict)
            end
          end

          context "with custom tool hash" do
            it "passes custom hashes through unchanged" do
              custom_tool = { type: "custom_tool", config: "value" }
              formatter = described_class.new(tools: [ custom_tool ])

              result = formatter.format

              expect(result).to eq([ custom_tool ])
            end
          end

          context "with unknown tool symbol" do
            it "formats to string type" do
              formatter = described_class.new(tools: [ :unknown_tool ])

              result = formatter.format

              expect(result).to eq([ { type: "unknown_tool" } ])
            end
          end
        end

        describe "#has_web_search_tool?" do
          it "returns true when web_search symbol is present" do
            formatter = described_class.new(tools: [ :web_search ])
            expect(formatter.has_web_search_tool?).to eq(true)
          end

          it "returns true when web_search_preview symbol is present" do
            formatter = described_class.new(tools: [ :web_search_preview ])
            expect(formatter.has_web_search_tool?).to eq(true)
          end

          it "returns true when web_search hash is present" do
            formatter = described_class.new(tools: [ { type: "web_search" } ])
            expect(formatter.has_web_search_tool?).to eq(true)
          end

          it "returns false when no web search tool" do
            formatter = described_class.new(tools: [ :file_search, :code_interpreter ])
            expect(formatter.has_web_search_tool?).to eq(false)
          end
        end
      end
    end
  end
end
