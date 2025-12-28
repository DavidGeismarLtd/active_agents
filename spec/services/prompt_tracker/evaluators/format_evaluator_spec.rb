# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe FormatEvaluator do
      let(:prompt) do
        Prompt.create!(
          name: "test_prompt",
          description: "Test",
          category: "test"
        )
      end

      let(:version) do
        prompt.prompt_versions.create!(
          user_prompt: "Test",
          status: "active",
        )
      end

      def create_response(text)
        version.llm_responses.create!(
          rendered_prompt: "Test",
          provider: "openai",
          model: "gpt-4",
          response_text: text,
          status: "success"
        )
      end

      describe ".param_schema" do
        it "defines schema for format parameters" do
          schema = FormatEvaluator.param_schema
          expect(schema[:format]).to eq({ type: :symbol })
          expect(schema[:required_keys]).to eq({ type: :array })
          expect(schema[:require_headers]).to eq({ type: :boolean })
          expect(schema[:max_parse_errors]).to eq({ type: :integer })
          expect(schema[:schema]).to eq({ type: :json })
          expect(schema[:strict]).to eq({ type: :boolean })
        end
      end

      describe ".process_params" do
        it "converts format string to symbol" do
          params = { format: "json" }
          result = FormatEvaluator.process_params(params)
          expect(result["format"]).to eq(:json)
        end

        it "parses JSON schema" do
          params = { schema: '{"type": "object"}' }
          result = FormatEvaluator.process_params(params)
          expect(result["schema"]).to eq({ "type" => "object" })
        end
      end

      describe "JSON format" do
        it "scores 100 for valid JSON" do
          response = create_response('{"name": "John", "age": 30}')
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 0 for invalid JSON" do
          response = create_response("not json")
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          expect(evaluator.evaluate_score).to eq(0)
        end

        it "validates required keys" do
          response = create_response('{"name": "John", "age": 30}')
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :json,
            required_keys: [ "name", "age" ]
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 50 when half of required keys missing" do
          response = create_response('{"name": "John"}')
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :json,
            required_keys: [ "name", "age" ]
          })

          expect(evaluator.evaluate_score).to eq(50)
        end

        it "provides partial scoring for some required keys" do
          response = create_response('{"name": "John"}')
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :json,
            required_keys: [ "name", "age", "email" ]
          })

          score = evaluator.evaluate_score
          expect(score).to be > 0
          expect(score).to be < 100
        end

        it "generates appropriate feedback for valid JSON" do
          response = create_response('{"name": "John"}')
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/valid json/i)
        end

        it "generates appropriate feedback for invalid JSON" do
          response = create_response("not json")
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          feedback = evaluator.generate_feedback
          expect(feedback).to match(/invalid json/i)
        end

        it "handles complex nested JSON" do
          json = '{"user": {"name": "John", "address": {"city": "NYC"}}}'
          response = create_response(json)
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "handles JSON arrays" do
          json = '[{"name": "John"}, {"name": "Jane"}]'
          response = create_response(json)
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "Markdown format" do
        it "scores 100 when headers required and present" do
          response = create_response("# Title\n\nContent here")
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :markdown,
            require_headers: true
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 50 when headers required but missing" do
          response = create_response("Just plain text")
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :markdown,
            require_headers: true
          })

          expect(evaluator.evaluate_score).to eq(50)
        end

        it "scores 100 when headers not required" do
          response = create_response("Just plain text")
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :markdown,
            require_headers: false
          })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "handles multiple header levels" do
          markdown = "# H1\n## H2\n### H3\nContent"
          response = create_response(markdown)
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :markdown,
            require_headers: true
          })

          expect(evaluator.evaluate_score).to eq(100)
        end
      end

      describe "Plain text format" do
        it "scores 100 for non-empty text" do
          response = create_response("Some plain text")
          evaluator = FormatEvaluator.new(response.response_text, { format: :plain_text })

          expect(evaluator.evaluate_score).to eq(100)
        end

        it "scores 0 for empty text" do
          response = create_response("")
          evaluator = FormatEvaluator.new(response.response_text, { format: :plain_text })

          expect(evaluator.evaluate_score).to eq(0)
        end
      end

      describe "general" do
        it "raises error for invalid format" do
          response = create_response("text")

          expect {
            FormatEvaluator.new(response.response_text, { format: :invalid })
          }.to raise_error(ArgumentError, /invalid format/i)
        end

        it "creates evaluation record" do
          response = create_response('{"name": "John"}')
          evaluator = FormatEvaluator.new(response.response_text, { format: :json })

          evaluation = evaluator.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::FormatEvaluator")
          expect(evaluation.score).to eq(100)
        end

        it "includes metadata" do
          response = create_response('{"name": "John"}')
          evaluator = FormatEvaluator.new(response.response_text, {
            format: :json,
            required_keys: [ "name" ]
          })

          metadata = evaluator.metadata
          expect(metadata[:format]).to eq(:json)
          expect(metadata[:format_valid]).to be true
        end
      end
    end
  end
end
