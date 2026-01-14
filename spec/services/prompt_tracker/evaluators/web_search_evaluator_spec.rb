# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module Evaluators
    RSpec.describe WebSearchEvaluator, type: :service do
      let(:web_search_results) do
        [
          {
            id: "ws-123",
            status: "completed",
            query: "Ruby on Rails web framework features 2024",
            sources: [
              { title: "Rails Blog", url: "https://rubyonrails.org/blog", snippet: "Rails 7 features..." },
              { title: "GitHub Rails", url: "https://github.com/rails/rails", snippet: "Ruby on Rails..." }
            ]
          }
        ]
      end

      let(:conversation_data) do
        {
          messages: [
            { role: "user", content: "What are the latest Ruby on Rails features?", turn: 1 },
            { role: "assistant", content: "Based on my search, Rails 7 includes...", turn: 1 }
          ],
          web_search_results: web_search_results
        }
      end

      let(:config) do
        {
          require_web_search: true,
          expected_queries: [ "Ruby on Rails" ],
          min_sources: 1
        }
      end

      let(:evaluator) { described_class.new(conversation_data, config) }

      describe "#initialize" do
        it "sets instance variables" do
          # conversation_data is normalized by the base class
          expect(evaluator.conversation_data[:web_search_results]).to be_present
          expect(evaluator.config[:require_web_search]).to be true
          expect(evaluator.config[:expected_queries]).to eq([ "Ruby on Rails" ])
        end

        it "merges config with defaults" do
          evaluator = described_class.new(conversation_data, {})
          expect(evaluator.config[:require_web_search]).to be true
          expect(evaluator.config[:expected_queries]).to eq([])
          expect(evaluator.config[:expected_domains]).to eq([])
          expect(evaluator.config[:threshold_score]).to eq(80)
        end
      end

      describe ".metadata" do
        it "returns evaluator metadata" do
          metadata = described_class.metadata

          expect(metadata[:name]).to eq("Web Search")
          expect(metadata[:description]).to include("web search")
          expect(metadata[:icon]).to eq("globe")
          expect(metadata[:category]).to eq(:tool_use)
        end
      end

      describe ".param_schema" do
        it "returns parameter schema" do
          schema = described_class.param_schema

          expect(schema).to have_key(:require_web_search)
          expect(schema).to have_key(:expected_queries)
          expect(schema).to have_key(:expected_domains)
          expect(schema).to have_key(:min_sources)
          expect(schema).to have_key(:threshold_score)
        end
      end

      describe "#evaluate_score" do
        context "when web search was used with all requirements met" do
          it "returns 100" do
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "when web search was not used" do
          let(:conversation_data) do
            { messages: [ { role: "assistant", content: "Hello" } ], web_search_results: [] }
          end

          it "returns 0" do
            expect(evaluator.evaluate_score).to eq(0)
          end
        end

        context "when web search is not required and not used" do
          let(:config) { { require_web_search: false } }
          let(:conversation_data) do
            { messages: [ { role: "assistant", content: "Hello" } ], web_search_results: [] }
          end

          it "returns 100" do
            expect(evaluator.evaluate_score).to eq(100)
          end
        end

        context "when expected queries are not found" do
          let(:config) do
            { require_web_search: true, expected_queries: [ "Python Django" ], require_all_queries: true }
          end

          it "returns partial score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
            expect(score).to be > 0
          end
        end
      end

      describe "#passed?" do
        context "when all requirements met" do
          it "returns true" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when web search not used but required" do
          let(:conversation_data) do
            { messages: [], web_search_results: [] }
          end

          it "returns false" do
            expect(evaluator.passed?).to be false
          end
        end
      end

      describe "#generate_feedback" do
        it "includes search count" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("Searches performed: 1")
        end

        it "includes queries made" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("Ruby on Rails")
        end

        it "indicates pass/fail status" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("✓")
        end

        context "when web search not used" do
          let(:conversation_data) { { messages: [], web_search_results: [] } }

          it "indicates failure" do
            feedback = evaluator.generate_feedback
            expect(feedback).to include("✗")
            expect(feedback).to include("not used")
          end
        end
      end

      describe "#metadata" do
        it "includes web search details" do
          metadata = evaluator.metadata

          expect(metadata["web_search_count"]).to eq(1)
          expect(metadata["queries"]).to include("Ruby on Rails web framework features 2024")
          expect(metadata["sources"].length).to eq(2)
        end
      end

      describe "domain matching" do
        let(:config) do
          {
            require_web_search: true,
            expected_domains: [ "rubyonrails.org", "github.com" ],
            require_all_domains: true
          }
        end

        it "matches expected domains" do
          expect(evaluator.passed?).to be true
        end

        context "when some domains not found" do
          let(:config) do
            {
              require_web_search: true,
              expected_domains: [ "rubyonrails.org", "stackoverflow.com" ],
              require_all_domains: true
            }
          end

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        context "with require_all_domains: false" do
          let(:config) do
            {
              require_web_search: true,
              expected_domains: [ "rubyonrails.org", "stackoverflow.com" ],
              require_all_domains: false
            }
          end

          it "passes if any domain found" do
            expect(evaluator.passed?).to be true
          end
        end
      end

      describe "query matching" do
        context "with partial matching" do
          let(:config) do
            { require_web_search: true, expected_queries: [ "Rails" ] }
          end

          it "matches partial queries" do
            expect(evaluator.send(:matched_queries)).to include("Rails")
          end
        end

        context "with case-insensitive matching" do
          let(:config) do
            { require_web_search: true, expected_queries: [ "ruby on rails" ] }
          end

          it "matches case-insensitively" do
            expect(evaluator.send(:matched_queries)).to include("ruby on rails")
          end
        end
      end

      describe "min_sources requirement" do
        context "when enough sources" do
          let(:config) { { require_web_search: true, min_sources: 2 } }

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when not enough sources" do
          let(:config) { { require_web_search: true, min_sources: 5 } }

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end
      end

      describe "#evaluate" do
        let(:assistant) { create(:openai_assistant) }
        let(:test) { create(:test, testable: assistant) }
        let(:test_run) { create(:test_run, :for_assistant, test: test) }
        let(:evaluator_with_test_run) do
          described_class.new(conversation_data, config.merge(test_run: test_run))
        end

        it "creates an evaluation record" do
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation).to be_persisted
          expect(evaluation.test_run).to eq(test_run)
          expect(evaluation.evaluator_type).to eq("PromptTracker::Evaluators::WebSearchEvaluator")
          expect(evaluation.score).to eq(100)
          expect(evaluation.passed).to be true
        end

        it "records details in metadata" do
          evaluation = evaluator_with_test_run.evaluate

          expect(evaluation.metadata["web_search_count"]).to eq(1)
          expect(evaluation.metadata["queries"]).to be_present
        end
      end
    end
  end
end
