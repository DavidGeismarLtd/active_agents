# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Anthropic
    module Messages
      RSpec.describe RequestBuilder, type: :service do
        describe "#build" do
          let(:model) { "claude-3-5-sonnet-20241022" }
          let(:messages) { [ { role: "user", content: "Hello!" } ] }

          context "with minimal parameters" do
            it "builds required parameters" do
              builder = described_class.new(
                model: model,
                messages: messages
              )

              result = builder.build

              expect(result[:model]).to eq(model)
              expect(result[:messages]).to eq([ { role: "user", content: "Hello!" } ])
              expect(result[:max_tokens]).to eq(RequestBuilder::DEFAULT_MAX_TOKENS)
            end
          end

          context "with system prompt" do
            it "adds system as separate parameter" do
              builder = described_class.new(
                model: model,
                messages: messages,
                system: "You are a helpful assistant."
              )

              result = builder.build

              expect(result[:system]).to eq("You are a helpful assistant.")
              # System should NOT be in messages array (unlike OpenAI)
              expect(result[:messages]).not_to include(hash_including(role: "system"))
            end
          end

          context "with temperature" do
            it "includes temperature when specified" do
              builder = described_class.new(
                model: model,
                messages: messages,
                temperature: 0.5
              )

              result = builder.build

              expect(result[:temperature]).to eq(0.5)
            end

            it "omits temperature when not specified" do
              builder = described_class.new(
                model: model,
                messages: messages
              )

              result = builder.build

              expect(result).not_to have_key(:temperature)
            end
          end

          context "with max_tokens" do
            it "uses provided max_tokens" do
              builder = described_class.new(
                model: model,
                messages: messages,
                max_tokens: 8192
              )

              result = builder.build

              expect(result[:max_tokens]).to eq(8192)
            end

            it "uses default when not provided" do
              builder = described_class.new(
                model: model,
                messages: messages
              )

              result = builder.build

              expect(result[:max_tokens]).to eq(4096)
            end
          end

          context "with tools" do
            it "includes formatted tools" do
              builder = described_class.new(
                model: model,
                messages: messages,
                tools: [ :functions ],
                tool_config: {
                  "functions" => [
                    { "name" => "get_weather", "description" => "Get weather" }
                  ]
                }
              )

              result = builder.build

              expect(result[:tools]).to be_present
              expect(result[:tools][0][:name]).to eq("get_weather")
            end

            it "omits tools when empty" do
              builder = described_class.new(
                model: model,
                messages: messages,
                tools: []
              )

              result = builder.build

              expect(result).not_to have_key(:tools)
            end
          end

          context "with multi-turn conversation" do
            it "formats all messages correctly" do
              multi_turn_messages = [
                { role: "user", content: "Hello" },
                { role: "assistant", content: "Hi there!" },
                { role: "user", content: "How are you?" }
              ]

              builder = described_class.new(
                model: model,
                messages: multi_turn_messages
              )

              result = builder.build

              expect(result[:messages].length).to eq(3)
              expect(result[:messages][0]).to eq({ role: "user", content: "Hello" })
              expect(result[:messages][1]).to eq({ role: "assistant", content: "Hi there!" })
              expect(result[:messages][2]).to eq({ role: "user", content: "How are you?" })
            end
          end
        end
      end
    end
  end
end
