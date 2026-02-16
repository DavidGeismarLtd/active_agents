# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Openai
    module Responses
      RSpec.describe RequestBuilder, type: :service do
        describe "#build" do
          context "single-turn request" do
            it "builds basic parameters" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello"
              )

              result = builder.build

              expect(result[:model]).to eq("gpt-4o")
              expect(result[:input]).to eq("Hello")
            end

            it "includes instructions when provided" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                instructions: "You are helpful"
              )

              result = builder.build

              expect(result[:instructions]).to eq("You are helpful")
            end

            it "includes temperature when provided" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                temperature: 0.8
              )

              result = builder.build

              expect(result[:temperature]).to eq(0.8)
            end

            it "includes max_output_tokens when provided" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                max_tokens: 1000
              )

              result = builder.build

              expect(result[:max_output_tokens]).to eq(1000)
            end

            it "formats tools using ToolFormatter" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                tools: [ :web_search, :code_interpreter ]
              )

              result = builder.build

              expect(result[:tools]).to eq([
                { type: "web_search_preview" },
                { type: "code_interpreter" }
              ])
            end

            it "includes web_search sources when web_search tool is present" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                tools: [ :web_search ]
              )

              result = builder.build

              expect(result[:include]).to eq([ "web_search_call.action.sources" ])
            end

            it "does not include tools when empty" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                tools: []
              )

              result = builder.build

              expect(result).not_to have_key(:tools)
            end
          end

          context "multi-turn request" do
            it "includes previous_response_id" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "What's my name?",
                previous_response_id: "resp_123"
              )

              result = builder.build

              expect(result[:previous_response_id]).to eq("resp_123")
            end

            it "does not include temperature for multi-turn" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                previous_response_id: "resp_123",
                temperature: 0.8
              )

              result = builder.build

              expect(result).not_to have_key(:temperature)
            end

            it "includes tools for multi-turn" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                previous_response_id: "resp_123",
                tools: [ :web_search ]
              )

              result = builder.build

              expect(result[:tools]).to eq([ { type: "web_search_preview" } ])
            end

            it "does not include web_search sources for multi-turn" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                previous_response_id: "resp_123",
                tools: [ :web_search ]
              )

              result = builder.build

              expect(result).not_to have_key(:include)
            end
          end

          context "with additional options" do
            it "merges additional options" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                store: true
              )

              result = builder.build

              expect(result[:store]).to eq(true)
            end

            it "combines include arrays" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                tools: [ :web_search ],
                include: [ "custom.field" ]
              )

              result = builder.build

              expect(result[:include]).to include("web_search_call.action.sources")
              expect(result[:include]).to include("custom.field")
            end

            it "excludes timeout from merged options" do
              builder = described_class.new(
                model: "gpt-4o",
                input: "Hello",
                timeout: 30
              )

              result = builder.build

              expect(result).not_to have_key(:timeout)
            end
          end
        end
      end
    end
  end
end
