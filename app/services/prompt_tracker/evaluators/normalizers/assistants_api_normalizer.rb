# frozen_string_literal: true

module PromptTracker
  module Evaluators
    module Normalizers
      # Normalizer for OpenAI Assistants API responses.
      #
      # The Assistants API has a unique structure with:
      # - Threads containing messages
      # - Runs with run_steps containing detailed tool execution info
      # - File search results in run_steps
      #
      # @example Normalize a conversation
      #   normalizer = AssistantsApiNormalizer.new
      #   normalized = normalizer.normalize_conversation({
      #     messages: [...],
      #     run_steps: [...]
      #   })
      #
      class AssistantsApiNormalizer < BaseNormalizer
        # Normalize a single response from Assistants API
        #
        # For Assistants API, single responses are typically the last assistant message
        #
        # @param raw_response [Hash, String] the raw response
        # @return [Hash] normalized single response format
        def normalize_single_response(raw_response)
          case raw_response
          when String
            { text: raw_response, tool_calls: [], metadata: {} }
          when Hash
            {
              text: extract_text(raw_response),
              tool_calls: extract_tool_calls(raw_response),
              metadata: extract_metadata(raw_response)
            }
          else
            { text: raw_response.to_s, tool_calls: [], metadata: {} }
          end
        end

        # Normalize a conversation from Assistants API
        #
        # @param raw_data [Hash] raw data containing:
        #   - messages: Array of messages from the thread
        #   - run_steps: Array of run steps (Assistants-specific)
        # @return [Hash] normalized conversation format
        def normalize_conversation(raw_data)
          messages = raw_data[:messages] || raw_data["messages"] || []
          run_steps = raw_data[:run_steps] || raw_data["run_steps"] || []

          {
            messages: normalize_messages(messages),
            tool_usage: extract_tool_usage(messages, run_steps),
            file_search_results: extract_file_search_results(run_steps),
            web_search_results: [],  # Assistants API doesn't have web search
            code_interpreter_results: extract_code_interpreter_results(run_steps),
            run_steps: run_steps
          }
        end

        private

        def extract_text(response)
          # Handle content array format from Assistants API
          content = response[:content] || response["content"]

          case content
          when Array
            content.filter_map do |item|
              if (item[:type] || item["type"]) == "text"
                text_obj = item[:text] || item["text"]
                text_obj.is_a?(Hash) ? (text_obj[:value] || text_obj["value"]) : text_obj
              end
            end.join("\n")
          when String
            content
          else
            response[:text] || response["text"] || ""
          end
        end

        def extract_tool_calls(response)
          tool_calls = response[:tool_calls] || response["tool_calls"] || []
          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type],
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_metadata(response)
          {
            id: response[:id] || response["id"],
            role: response[:role] || response["role"],
            assistant_id: response[:assistant_id] || response["assistant_id"],
            thread_id: response[:thread_id] || response["thread_id"],
            run_id: response[:run_id] || response["run_id"]
          }.compact
        end

        def normalize_messages(messages)
          messages.map.with_index do |msg, index|
            content = msg[:content] || msg["content"]
            text = case content
            when Array
                     content.filter_map do |item|
                       if (item[:type] || item["type"]) == "text"
                         text_obj = item[:text] || item["text"]
                         text_obj.is_a?(Hash) ? (text_obj[:value] || text_obj["value"]) : text_obj
                       end
                     end.join("\n")
            when String
                     content
            else
                     ""
            end

            {
              role: msg[:role] || msg["role"],
              content: text,
              tool_calls: extract_message_tool_calls(msg),
              turn: msg[:turn] || msg["turn"] || calculate_turn(messages, index)
            }
          end
        end

        def extract_message_tool_calls(message)
          tool_calls = message[:tool_calls] || message["tool_calls"] || []
          tool_calls.map do |tc|
            {
              id: tc["id"] || tc[:id],
              type: tc["type"] || tc[:type],
              function_name: tc.dig("function", "name") || tc.dig(:function, :name),
              arguments: parse_arguments(tc.dig("function", "arguments") || tc.dig(:function, :arguments))
            }
          end
        end

        def extract_tool_usage(messages, run_steps)
          # Combine tool calls from messages and detailed info from run_steps
          tool_calls_from_messages = messages.flat_map { |m| extract_message_tool_calls(m) }

          tool_calls_from_messages.map do |tc|
            {
              function_name: tc[:function_name],
              call_id: tc[:id],
              arguments: tc[:arguments],
              result: find_tool_result(run_steps, tc[:id])
            }
          end
        end

        def find_tool_result(run_steps, call_id)
          run_steps.each do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []

            tool_calls.each do |tc|
              return tc["output"] || tc[:output] if (tc["id"] || tc[:id]) == call_id
            end
          end
          nil
        end

        def extract_file_search_results(run_steps)
          run_steps.flat_map do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []

            tool_calls.filter_map do |tc|
              next unless (tc["type"] || tc[:type]) == "file_search"

              file_search = tc["file_search"] || tc[:file_search] || {}
              results = file_search["results"] || file_search[:results] || []

              {
                query: nil,  # File search query isn't exposed in the API response
                files: results.map { |r| r["file_name"] || r[:file_name] },
                scores: results.map { |r| r["score"] || r[:score] }
              }
            end
          end
        end

        def calculate_turn(messages, current_index)
          turn = 0
          messages.each_with_index do |msg, idx|
            break if idx > current_index
            turn += 1 if (msg[:role] || msg["role"]) == "user"
          end
          turn
        end

        # Extract code interpreter results from run_steps
        #
        # @param run_steps [Array<Hash>] array of run step data
        # @return [Array<Hash>] array of code interpreter results
        def extract_code_interpreter_results(run_steps)
          run_steps.flat_map do |step|
            step_details = step["step_details"] || step[:step_details] || {}
            tool_calls = step_details["tool_calls"] || step_details[:tool_calls] || []

            tool_calls.filter_map do |tc|
              next unless (tc["type"] || tc[:type]) == "code_interpreter"

              ci = tc["code_interpreter"] || tc[:code_interpreter] || {}
              input = ci["input"] || ci[:input] || ""
              outputs = ci["outputs"] || ci[:outputs] || []

              {
                id: tc["id"] || tc[:id],
                status: "completed",  # Assistants API doesn't expose status per tool call
                code: input,
                language: detect_language(input),
                output: extract_code_outputs(outputs),
                files_created: extract_files_from_outputs(outputs),
                error: nil
              }
            end
          end
        end

        def detect_language(code)
          return nil if code.nil? || code.empty?

          # Simple heuristic detection
          return "python" if code.include?("import ") || code.include?("def ") || code.include?("print(")
          return "javascript" if code.include?("const ") || code.include?("let ") || code.include?("function ")
          return "ruby" if code.include?("require ") || (code.include?("def ") && code.include?("end"))

          nil
        end

        def extract_code_outputs(outputs)
          outputs.filter_map do |output|
            type = output["type"] || output[:type]
            case type
            when "logs"
              output["logs"] || output[:logs]
            when "image"
              "[Image output]"
            else
              output["text"] || output[:text]
            end
          end.join("\n")
        end

        def extract_files_from_outputs(outputs)
          outputs.filter_map do |output|
            type = output["type"] || output[:type]
            next unless type == "image"

            file_id = output.dig("image", "file_id") || output.dig(:image, :file_id)
            { file_id: file_id } if file_id
          end
        end
      end
    end
  end
end
