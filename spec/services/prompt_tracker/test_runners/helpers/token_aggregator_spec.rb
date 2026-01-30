# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Helpers
      RSpec.describe TokenAggregator, type: :service do
        let(:aggregator) { described_class.new }

        describe "#aggregate_from_messages" do
          it "aggregates tokens from assistant messages" do
            messages = [
              { "role" => "user", "content" => "Hello" },
              { "role" => "assistant", "content" => "Hi", "usage" => { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } },
              { "role" => "user", "content" => "How are you?" },
              { "role" => "assistant", "content" => "Good", "usage" => { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 } }
            ]

            result = aggregator.aggregate_from_messages(messages)

            expect(result).to eq(
              "prompt_tokens" => 30,
              "completion_tokens" => 15,
              "total_tokens" => 45
            )
          end

          it "returns nil when no messages have usage data" do
            messages = [
              { "role" => "user", "content" => "Hello" },
              { "role" => "assistant", "content" => "Hi" }
            ]

            result = aggregator.aggregate_from_messages(messages)

            expect(result).to be_nil
          end

          it "ignores user messages" do
            messages = [
              { "role" => "user", "content" => "Hello", "usage" => { prompt_tokens: 100, completion_tokens: 0, total_tokens: 100 } },
              { "role" => "assistant", "content" => "Hi", "usage" => { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
            ]

            result = aggregator.aggregate_from_messages(messages)

            expect(result).to eq(
              "prompt_tokens" => 10,
              "completion_tokens" => 5,
              "total_tokens" => 15
            )
          end

          it "handles missing token fields gracefully" do
            messages = [
              { "role" => "assistant", "content" => "Hi", "usage" => { prompt_tokens: 10 } },
              { "role" => "assistant", "content" => "Bye", "usage" => { completion_tokens: 5 } }
            ]

            result = aggregator.aggregate_from_messages(messages)

            expect(result).to eq(
              "prompt_tokens" => 10,
              "completion_tokens" => 5,
              "total_tokens" => 0
            )
          end
        end

        describe "#aggregate_from_responses" do
          it "aggregates tokens from API responses" do
            responses = [
              { usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } },
              { usage: { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 } }
            ]

            result = aggregator.aggregate_from_responses(responses)

            expect(result).to eq(
              prompt_tokens: 30,
              completion_tokens: 15,
              total_tokens: 45
            )
          end

          it "returns zero counts when no responses have usage data" do
            responses = [
              { text: "Hello" },
              { text: "World" }
            ]

            result = aggregator.aggregate_from_responses(responses)

            expect(result).to eq(
              prompt_tokens: 0,
              completion_tokens: 0,
              total_tokens: 0
            )
          end

          it "handles missing token fields gracefully" do
            responses = [
              { usage: { prompt_tokens: 10 } },
              { usage: { completion_tokens: 5 } }
            ]

            result = aggregator.aggregate_from_responses(responses)

            expect(result).to eq(
              prompt_tokens: 10,
              completion_tokens: 5,
              total_tokens: 0
            )
          end
        end
      end
    end
  end
end
