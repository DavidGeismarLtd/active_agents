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
          expect(schema).to have_key(:min_sources_consulted)
          expect(schema).to have_key(:min_sources_cited)
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
          expect(metadata["sources_consulted"]).to eq(2)
          expect(metadata["sources_consulted_list"].length).to eq(2)
          expect(metadata["sources_cited"]).to eq(0)
          expect(metadata["sources_cited_list"].length).to eq(0)
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
        context "when enough sources consulted" do
          let(:config) { { require_web_search: true, min_sources_consulted: 2 } }

          it "passes" do
            expect(evaluator.passed?).to be true
          end
        end

        context "when not enough sources consulted" do
          let(:config) { { require_web_search: true, min_sources_consulted: 5 } }

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        context "when not enough sources cited" do
          let(:config) { { require_web_search: true, min_sources_cited: 5 } }

          it "reduces score" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end
      end

      describe "multiple web searches with shared citations" do
        # This tests the fix for the citation duplication bug where
        # extract_web_search_results assigns the full citations array to every web_search_call
        let(:web_search_results) do
          [
            {
              id: "ws-1",
              status: "completed",
              query: "Ruby programming",
              sources: [
                { title: "Ruby Lang", url: "https://ruby-lang.org", snippet: "Ruby is..." },
                { title: "GitHub", url: "https://github.com", snippet: "GitHub is..." }
              ],
              citations: [
                { title: "Ruby Lang", url: "https://ruby-lang.org", start_index: 0, end_index: 20 },
                { title: "GitHub", url: "https://github.com", start_index: 21, end_index: 40 },
                { title: "Stack Overflow", url: "https://stackoverflow.com", start_index: 41, end_index: 60 }
              ]
            },
            {
              id: "ws-2",
              status: "completed",
              query: "Python programming",
              sources: [
                { title: "Ruby Lang", url: "https://ruby-lang.org", snippet: "Ruby is..." },
                { title: "Python Org", url: "https://python.org", snippet: "Python is..." }
              ],
              citations: [
                { title: "Ruby Lang", url: "https://ruby-lang.org", start_index: 0, end_index: 20 },
                { title: "GitHub", url: "https://github.com", start_index: 21, end_index: 40 },
                { title: "Stack Overflow", url: "https://stackoverflow.com", start_index: 41, end_index: 60 }
              ]
            }
          ]
        end

        let(:conversation_data) do
          {
            messages: [
              { role: "user", content: "Compare Ruby and Python", turn: 1 },
              { role: "assistant", content: "Based on my research...", turn: 1 }
            ],
            web_search_results: web_search_results
          }
        end

        let(:config) { { require_web_search: true } }

        it "deduplicates citations by URL to prevent multiplication" do
          # Should count 3 unique citations, not 6 (3 citations × 2 web searches)
          expect(evaluator.send(:all_sources_cited).length).to eq(3)
        end

        it "returns unique citation objects" do
          cited = evaluator.send(:all_sources_cited)
          urls = cited.map { |c| c[:url] }
          expect(urls).to contain_exactly(
            "https://ruby-lang.org",
            "https://github.com",
            "https://stackoverflow.com"
          )
        end

        it "reports correct sources_cited_count in metadata" do
          metadata = evaluator.metadata
          expect(metadata["sources_cited"]).to eq(3)
        end

        it "includes deduplicated sources_cited_list in metadata" do
          metadata = evaluator.metadata
          expect(metadata["sources_cited_list"].length).to eq(3)
        end

        it "generates correct feedback with deduplicated count" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("Sources cited: 3")
        end

        context "with min_sources_cited requirement" do
          let(:config) { { require_web_search: true, min_sources_cited: 3 } }

          it "passes when deduplicated count meets requirement" do
            expect(evaluator.passed?).to be true
          end
        end

        context "with min_sources_cited requirement not met" do
          let(:config) { { require_web_search: true, min_sources_cited: 5 } }

          it "fails when deduplicated count does not meet requirement" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end

        it "deduplicates sources consulted by URL to prevent multiplication" do
          # Should count 3 unique sources, not 4 (2 sources in ws-1 + 2 sources in ws-2, with 1 duplicate)
          expect(evaluator.send(:all_sources_consulted).length).to eq(3)
        end

        it "returns unique sources consulted objects" do
          consulted = evaluator.send(:all_sources_consulted)
          urls = consulted.map { |s| s[:url] }
          expect(urls).to contain_exactly(
            "https://ruby-lang.org",
            "https://github.com",
            "https://python.org"
          )
        end

        it "reports correct sources_consulted_count in metadata" do
          metadata = evaluator.metadata
          expect(metadata["sources_consulted"]).to eq(3)
        end

        it "includes deduplicated sources_consulted_list in metadata" do
          metadata = evaluator.metadata
          expect(metadata["sources_consulted_list"].length).to eq(3)
        end

        it "generates correct feedback with deduplicated sources consulted count" do
          feedback = evaluator.generate_feedback
          expect(feedback).to include("Sources consulted: 3")
        end

        context "with min_sources_consulted requirement" do
          let(:config) { { require_web_search: true, min_sources_consulted: 3 } }

          it "passes when deduplicated count meets requirement" do
            expect(evaluator.passed?).to be true
          end
        end

        context "with min_sources_consulted requirement not met" do
          let(:config) { { require_web_search: true, min_sources_consulted: 5 } }

          it "fails when deduplicated count does not meet requirement" do
            score = evaluator.evaluate_score
            expect(score).to be < 100
          end
        end
      end

      describe "#evaluate" do
        let(:prompt_version) { create(:prompt_version, :with_assistants) }
        let(:test) { create(:test, testable: prompt_version) }
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
