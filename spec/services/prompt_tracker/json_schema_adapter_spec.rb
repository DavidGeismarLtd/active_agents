# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/schema"

module PromptTracker
  RSpec.describe JsonSchemaAdapter do
    describe ".to_ruby_llm_schema" do
      context "with a simple object schema" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "sentiment" => { "type" => "string", "description" => "The sentiment" },
              "confidence" => { "type" => "number", "description" => "Confidence score" }
            },
            "required" => %w[sentiment confidence]
          }
        end

        it "returns a RubyLLM::Schema subclass" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end

        it "creates a valid schema class" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be_a(Class)
          expect(schema_class.ancestors).to include(RubyLLM::Schema)
        end
      end

      context "with various property types" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "score" => { "type" => "number" },
              "count" => { "type" => "integer" },
              "active" => { "type" => "boolean" }
            }
          }
        end

        it "handles string, number, integer, and boolean types" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end
      end

      context "with array properties" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "tags" => {
                "type" => "array",
                "items" => { "type" => "string" },
                "description" => "List of tags"
              }
            }
          }
        end

        it "handles array of strings" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end
      end

      context "with array of objects" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "items" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "name" => { "type" => "string" },
                    "value" => { "type" => "number" }
                  }
                }
              }
            }
          }
        end

        it "handles array of objects with nested properties" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end
      end

      context "with nested object properties" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "metadata" => {
                "type" => "object",
                "properties" => {
                  "created_at" => { "type" => "string" },
                  "version" => { "type" => "number" }
                },
                "description" => "Metadata object"
              }
            }
          }
        end

        it "handles nested object properties" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end
      end

      context "with unknown types" do
        let(:json_schema) do
          {
            "type" => "object",
            "properties" => {
              "custom_field" => { "type" => "custom_type" }
            }
          }
        end

        it "defaults unknown types to string" do
          schema_class = described_class.to_ruby_llm_schema(json_schema)

          expect(schema_class).to be < RubyLLM::Schema
        end
      end
    end

    describe "validation" do
      it "raises ArgumentError for non-Hash input" do
        expect { described_class.to_ruby_llm_schema("not a hash") }
          .to raise_error(ArgumentError, /must be a Hash/)
      end

      it "raises ArgumentError for missing type property" do
        expect { described_class.to_ruby_llm_schema({ "properties" => {} }) }
          .to raise_error(ArgumentError, /must have a 'type' property/)
      end

      it "raises ArgumentError for object type without properties" do
        expect { described_class.to_ruby_llm_schema({ "type" => "object" }) }
          .to raise_error(ArgumentError, /must have 'properties'/)
      end
    end
  end
end
