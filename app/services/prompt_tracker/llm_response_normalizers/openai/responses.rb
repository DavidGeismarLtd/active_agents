# frozen_string_literal: true

module PromptTracker
  module LlmResponseNormalizers
    module Openai
      # Normalizer for OpenAI Responses API.
      #
      # Transforms raw Response API responses into NormalizedLlmResponse objects.
      # Handles extraction of text, tool calls, file search, web search,
      # and code interpreter results.
      #
      # @example
      #   LlmResponseNormalizers::Openai::Responses.normalize(raw_api_response)
      #
      class Responses < Base
        def normalize
          NormalizedLlmResponse.new(
            text: extract_text_from_output,
            usage: extract_usage,
            model: raw_response["model"],
            tool_calls: extract_tool_calls_from_output,
            file_search_results: extract_file_search_results(output),
            web_search_results: extract_web_search_results(output),
            code_interpreter_results: extract_code_interpreter_results(output),
            api_metadata: {
              response_id: raw_response["id"]
            },
            raw_response: raw_response
          )
        end

        private

        def output
          @output ||= raw_response["output"] || []
        end

        # Extract text from Response API output
        def extract_text_from_output
          text_parts = output.flat_map do |item|
            next [] unless item["type"] == "message"

            content = item["content"] || []
            content.filter_map do |c|
              c["text"] if c["type"] == "output_text"
            end
          end

          text_parts.join("\n").presence || raw_response["text"] || ""
        end

        # Extract tool calls from Response API output
        def extract_tool_calls_from_output
          output.filter_map do |item|
            next unless item["type"] == "function_call"

            {
              id: item["call_id"] || item["id"],
              type: "function",
              function_name: item["name"],
              arguments: parse_json_arguments(item["arguments"])
            }
          end
        end

        # Extract usage information
        def extract_usage
          usage = raw_response["usage"] || {}
          {
            prompt_tokens: usage["input_tokens"] || 0,
            completion_tokens: usage["output_tokens"] || 0,
            total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
          }
        end

        # Extract file search results from Response API output
        def extract_file_search_results(output_items)
          output_items.filter_map do |item|
            next unless item["type"] == "file_search_call"

            results = item["results"] || []
            {
              query: item["query"],
              files: results.map { |r| r["filename"] },
              scores: results.map { |r| r["score"] }
            }
          end
        end

        # Extract web search results from Response API output
        def extract_web_search_results(output_items)
          citations = extract_url_citations(output_items)

          output_items.filter_map do |item|
            next unless item["type"] == "web_search_call"

            {
              id: item["id"],
              status: item["status"],
              query: extract_web_search_query(item),
              sources: extract_web_search_sources(item),
              citations: citations
            }
          end
        end

        # Extract query from web search call item
        def extract_web_search_query(item)
          action = item["action"] || {}
          action["query"] || action["queries"]&.first || item["query"]
        end

        # Extract sources from web_search_call.action.sources
        def extract_web_search_sources(item)
          action = item["action"] || {}
          sources = action["sources"] || []

          sources.map do |source|
            {
              title: source["title"],
              url: source["url"],
              snippet: source["snippet"]
            }
          end
        end

        # Extract URL citations from message annotations
        def extract_url_citations(output_items)
          output_items.flat_map do |item|
            next [] unless item["type"] == "message"

            content = item["content"] || []
            content.flat_map do |c|
              annotations = c["annotations"] || []
              annotations.filter_map do |ann|
                next unless ann["type"] == "url_citation"

                {
                  title: ann["title"],
                  url: ann["url"],
                  start_index: ann["start_index"],
                  end_index: ann["end_index"]
                }
              end
            end
          end
        end

        # Extract code interpreter results from Response API output
        def extract_code_interpreter_results(output_items)
          output_items.filter_map do |item|
            next unless item["type"] == "code_interpreter_call"

            ci = item["code_interpreter"] || {}
            {
              id: item["id"],
              status: item["status"],
              code: ci["code"] || item["code"],
              language: ci["language"] || detect_code_language(ci["code"]),
              output: extract_code_output(ci),
              files_created: ci["files_created"] || [],
              error: ci["error"]
            }
          end
        end

        # Extract code output from code interpreter result
        def extract_code_output(code_interpreter)
          output_val = code_interpreter["output"]
          return output_val if output_val.is_a?(String)

          if output_val.is_a?(Array)
            output_val.filter_map { |o| o["text"] || o["logs"] }.join("\n")
          else
            output_val.to_s
          end
        end

        # Simple heuristic language detection for code
        def detect_code_language(code)
          return nil if code.nil?

          return "python" if code.include?("import ") || code.include?("def ") || code.include?("print(")
          return "javascript" if code.include?("const ") || code.include?("let ") || code.include?("function ")
          return "ruby" if code.include?("require ") || (code.include?("def ") && code.include?("end"))

          nil
        end
      end
    end
  end
end
