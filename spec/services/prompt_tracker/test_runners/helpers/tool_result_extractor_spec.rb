# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Helpers
      RSpec.describe ToolResultExtractor, type: :service do
        let(:responses) do
          [
            {
              web_search_results: [ { query: "test", results: [ "result1" ] } ],
              code_interpreter_results: [ { code: "print('hello')", output: "hello" } ],
              file_search_results: [ { files: [ "doc1.pdf" ] } ]
            },
            {
              web_search_results: [ { query: "another", results: [ "result2" ] } ],
              code_interpreter_results: [],
              file_search_results: [ { files: [ "doc2.pdf" ] } ]
            }
          ]
        end

        let(:extractor) { described_class.new(responses) }

        describe "#web_search_results" do
          it "aggregates web search results from all responses" do
            results = extractor.web_search_results

            expect(results.length).to eq(2)
            expect(results[0][:query]).to eq("test")
            expect(results[1][:query]).to eq("another")
          end

          it "returns empty array when no web search results" do
            extractor = described_class.new([ { text: "hello" } ])
            results = extractor.web_search_results

            expect(results).to eq([])
          end
        end

        describe "#code_interpreter_results" do
          it "aggregates code interpreter results from all responses" do
            results = extractor.code_interpreter_results

            expect(results.length).to eq(1)
            expect(results[0][:code]).to eq("print('hello')")
          end

          it "returns empty array when no code interpreter results" do
            extractor = described_class.new([ { text: "hello" } ])
            results = extractor.code_interpreter_results

            expect(results).to eq([])
          end
        end

        describe "#file_search_results" do
          it "aggregates file search results from all responses" do
            results = extractor.file_search_results

            expect(results.length).to eq(2)
            expect(results[0][:files]).to eq([ "doc1.pdf" ])
            expect(results[1][:files]).to eq([ "doc2.pdf" ])
          end

          it "returns empty array when no file search results" do
            extractor = described_class.new([ { text: "hello" } ])
            results = extractor.file_search_results

            expect(results).to eq([])
          end
        end

        describe "#all_results" do
          it "returns all tool results as a hash" do
            results = extractor.all_results

            expect(results).to have_key(:web_search_results)
            expect(results).to have_key(:code_interpreter_results)
            expect(results).to have_key(:file_search_results)
            expect(results[:web_search_results].length).to eq(2)
            expect(results[:code_interpreter_results].length).to eq(1)
            expect(results[:file_search_results].length).to eq(2)
          end
        end
      end
    end
  end
end
