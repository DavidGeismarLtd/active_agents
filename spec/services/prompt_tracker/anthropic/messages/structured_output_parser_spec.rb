# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Anthropic
    module Messages
      RSpec.describe StructuredOutputParser, type: :service do
        describe ".parse" do
          it "provides a convenient class method" do
            content = '{"score": 85}'
            result = described_class.parse(content)

            expect(result[:score]).to eq(85)
          end
        end

        describe "#parse" do
          context "with Hash content (passthrough)" do
            it "returns the hash with indifferent access" do
              content = { "overall_score" => 75, "feedback" => "Good response" }
              parser = described_class.new(content)

              result = parser.parse

              expect(result[:overall_score]).to eq(75)
              expect(result["overall_score"]).to eq(75)
              expect(result[:feedback]).to eq("Good response")
            end
          end

          context "with JSON wrapped in ```json code blocks" do
            it "extracts and parses the JSON" do
              content = <<~CONTENT
                ```json
                {
                  "overall_score": 75,
                  "feedback": "The response is well-structured and helpful."
                }
                ```
              CONTENT

              parser = described_class.new(content)
              result = parser.parse

              expect(result[:overall_score]).to eq(75)
              expect(result[:feedback]).to eq("The response is well-structured and helpful.")
            end

            it "handles single-line code blocks" do
              content = '```json{"score": 90}```'
              parser = described_class.new(content)

              result = parser.parse

              expect(result[:score]).to eq(90)
            end
          end

          context "with JSON wrapped in plain ``` code blocks" do
            it "extracts and parses the JSON" do
              content = <<~CONTENT
                ```
                {"overall_score": 80, "feedback": "Good job!"}
                ```
              CONTENT

              parser = described_class.new(content)
              result = parser.parse

              expect(result[:overall_score]).to eq(80)
              expect(result[:feedback]).to eq("Good job!")
            end
          end

          context "with raw JSON string" do
            it "parses the JSON directly" do
              content = '{"overall_score": 95, "feedback": "Excellent!"}'
              parser = described_class.new(content)

              result = parser.parse

              expect(result[:overall_score]).to eq(95)
              expect(result[:feedback]).to eq("Excellent!")
            end

            it "handles whitespace around JSON" do
              content = "  \n  {\"score\": 42}  \n  "
              parser = described_class.new(content)

              result = parser.parse

              expect(result[:score]).to eq(42)
            end
          end

          context "with complex nested JSON" do
            it "parses nested structures" do
              content = <<~CONTENT
                ```json
                {
                  "overall_score": 70,
                  "feedback": "Needs improvement",
                  "details": {
                    "clarity": 80,
                    "accuracy": 60
                  },
                  "suggestions": ["Be more specific", "Add examples"]
                }
                ```
              CONTENT

              parser = described_class.new(content)
              result = parser.parse

              expect(result[:overall_score]).to eq(70)
              expect(result[:details][:clarity]).to eq(80)
              expect(result[:suggestions]).to eq([ "Be more specific", "Add examples" ])
            end
          end

          context "with invalid JSON" do
            it "raises JSON::ParserError" do
              content = '```json\n{invalid json}\n```'
              parser = described_class.new(content)

              expect { parser.parse }.to raise_error(JSON::ParserError)
            end
          end

          context "with real Claude response format" do
            it "handles the actual Claude response with newlines" do
              # This is the exact format from the user's pry session
              content = "```json\n{\n  \"overall_score\": 75,\n  \"feedback\": \"The response provides a well-structured approach.\"\n}\n```"

              parser = described_class.new(content)
              result = parser.parse

              expect(result[:overall_score]).to eq(75)
              expect(result[:feedback]).to include("well-structured")
            end
          end
        end
      end
    end
  end
end
