# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Anthropic
    module Messages
      RSpec.describe ToolFormatter, type: :service do
        describe "#format" do
          context "with functions tool" do
            it "formats function definitions with input_schema" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    {
                      "name" => "get_weather",
                      "description" => "Get the weather for a location",
                      "parameters" => {
                        "type" => "object",
                        "properties" => {
                          "location" => { "type" => "string" }
                        },
                        "required" => [ "location" ]
                      }
                    }
                  ]
                }
              )

              result = formatter.format

              expect(result.length).to eq(1)
              expect(result[0][:name]).to eq("get_weather")
              expect(result[0][:description]).to eq("Get the weather for a location")
              expect(result[0][:input_schema]).to eq({
                "type" => "object",
                "properties" => { "location" => { "type" => "string" } },
                "required" => [ "location" ]
              })
              # Anthropic format doesn't have type: "function" wrapper
              expect(result[0]).not_to have_key(:type)
            end

            it "handles multiple functions" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    { "name" => "func1", "description" => "First function" },
                    { "name" => "func2", "description" => "Second function" }
                  ]
                }
              )

              result = formatter.format

              expect(result.length).to eq(2)
              expect(result.map { |f| f[:name] }).to eq(%w[func1 func2])
            end

            it "uses empty schema when parameters not provided" do
              formatter = described_class.new(
                tools: [ :functions ],
                tool_config: {
                  "functions" => [ { "name" => "no_params" } ]
                }
              )

              result = formatter.format

              expect(result[0][:input_schema]).to eq({ type: "object", properties: {} })
            end
          end

          context "with web_search tool" do
            it "formats web_search for Anthropic" do
              formatter = described_class.new(tools: [ :web_search ])

              result = formatter.format

              expect(result).to eq([ { type: "web_search", name: "web_search" } ])
            end
          end

          context "with custom tool hash" do
            it "passes custom hashes through unchanged" do
              custom_tool = { name: "custom_tool", description: "A custom tool", input_schema: {} }
              formatter = described_class.new(tools: [ custom_tool ])

              result = formatter.format

              expect(result).to eq([ custom_tool ])
            end
          end

          context "with unsupported tools" do
            it "ignores file_search (not supported by Anthropic)" do
              formatter = described_class.new(tools: [ :file_search ])

              result = formatter.format

              expect(result).to be_empty
            end

            it "ignores code_interpreter (not supported by Anthropic)" do
              formatter = described_class.new(tools: [ :code_interpreter ])

              result = formatter.format

              expect(result).to be_empty
            end
          end

          context "with empty tools" do
            it "returns empty array" do
              formatter = described_class.new(tools: [])

              expect(formatter.format).to eq([])
            end
          end
        end

        describe "#any?" do
          it "returns true when tools are present" do
            formatter = described_class.new(tools: [ :functions ])
            expect(formatter.any?).to eq(true)
          end

          it "returns false when tools are empty" do
            formatter = described_class.new(tools: [])
            expect(formatter.any?).to eq(false)
          end
        end
      end
    end
  end
end
