# frozen_string_literal: true

module PromptTracker
  module TestRunners
    module Helpers
      # Extracts tool results from API responses.
      #
      # This class aggregates tool results (web_search, code_interpreter, file_search)
      # from multiple API responses across a conversation. Used primarily with
      # OpenAI Response API which supports built-in tools.
      #
      # @example Extract tool results
      #   extractor = ToolResultExtractor.new(responses)
      #   web_results = extractor.web_search_results
      #   code_results = extractor.code_interpreter_results
      #   file_results = extractor.file_search_results
      #
      class ToolResultExtractor
        # @param responses [Array<Hash>] array of API responses
        def initialize(responses)
          @responses = responses
        end

        # Extract all web search results from responses
        #
        # @return [Array<Hash>] aggregated web search results
        def web_search_results
          @responses.flat_map { |r| r[:web_search_results] || [] }
        end

        # Extract all code interpreter results from responses
        #
        # @return [Array<Hash>] aggregated code interpreter results
        def code_interpreter_results
          @responses.flat_map { |r| r[:code_interpreter_results] || [] }
        end

        # Extract all file search results from responses
        #
        # @return [Array<Hash>] aggregated file search results
        def file_search_results
          @responses.flat_map { |r| r[:file_search_results] || [] }
        end

        # Extract all tool results as a hash
        #
        # @return [Hash] hash with all tool result types
        def all_results
          {
            web_search_results: web_search_results,
            code_interpreter_results: code_interpreter_results,
            file_search_results: file_search_results
          }
        end
      end
    end
  end
end
