# frozen_string_literal: true

# {:content=>
#   "Pas de souci, c'est bien d'y réfléchir pour améliorer ton équilibre alimentaire ! 🍔 Pour t'aider au mieux, j'aimerais te poser quelques questions :\n\n1. À quelle fréquence vas-tu au McDonald's ou dans des fast-foods en général ?\n2. Qu'est-ce que tu choisis généralement quand tu y vas ?\n3. As-tu des contraintes de temps ou de travail qui t'amènent à y aller souvent ?\n4. As-tu des objectifs spécifiques en matière de nutrition (perte de poids, plus d'énergie, etc.) ?\n5. Y a-t-il des aliments que tu évites ou que tu ne peux pas consommer pour des raisons de santé ?\n\nCes informations m'aideront à te donner des conseils plus adaptés à ta situation. 😊",
#  :usage=>{"prompt_tokens"=>2806, "completion_tokens"=>155, "total_tokens"=>2961, "prompt_token_details"=>{"cached_tokens"=>0}, "completion_tokens_details"=>{"reasoning_tokens"=>0}},
#  :assistant_id=>"asst_HPnWFxxtUBbk4PoLJ9d83pS6",
#  :run_steps=>
#   {"object"=>"list",
#    "data"=>
#     [{"id"=>"step_M0mFBgRNi52EHtr7Xys3G0Ts",
#       "object"=>"thread.run.step",
#       "created_at"=>1771175405,
#       "run_id"=>"run_hCNlRwZvFdQ6wCGuyFIuB3DV",
#       "assistant_id"=>"asst_HPnWFxxtUBbk4PoLJ9d83pS6",
#       "thread_id"=>"thread_TT71pcMf3oxBEyAe0cOvDIQI",
#       "type"=>"message_creation",
#       "status"=>"completed",
#       "cancelled_at"=>nil,
#       "completed_at"=>1771175407,
#       "expires_at"=>nil,
#       "failed_at"=>nil,
#       "last_error"=>nil,
#       "step_details"=>{"type"=>"message_creation", "message_creation"=>{"message_id"=>"msg_O0b7KAUUfB4LLewiFofRlrQS"}},
#       "usage"=>{"prompt_tokens"=>2806, "completion_tokens"=>155, "total_tokens"=>2961, "prompt_token_details"=>{"cached_tokens"=>0}, "completion_tokens_details"=>{"reasoning_tokens"=>0}}}],
#    "first_id"=>"step_M0mFBgRNi52EHtr7Xys3G0Ts",
#    "last_id"=>"step_M0mFBgRNi52EHtr7Xys3G0Ts",
#    "has_more"=>false},
#  :thread_id=>"thread_TT71pcMf3oxBEyAe0cOvDIQI",
#  :run_id=>"run_hCNlRwZvFdQ6wCGuyFIuB3DV",
#  :annotations=>[]}
module PromptTracker
  module LlmResponseNormalizers
    module Openai
      # Normalizer for OpenAI Assistants API.
      #
      # Transforms raw Assistants API data (messages, run, run_steps) into
      # NormalizedLlmResponse objects. Handles extraction of file search results
      # and function tool calls from run steps.
      #
      # @example
      #   LlmResponseNormalizers::Openai::Assistants.normalize({
      #     content: "Hello!",
      #     run: run_data,
      #     usage: usage_data,
      #     run_steps: run_steps_data,
      #     assistant_message: message_data,
      #     thread_id: "thread_abc",
      #     run_id: "run_xyz",
      #     annotations: []
      #   })
      #
      class Assistants < Base
        def normalize
          NormalizedLlmResponse.new(
            text: raw_response[:content],
            usage: extract_usage,
            model: raw_response[:assistant_id],
            tool_calls: extract_tool_calls,
            file_search_results: extract_file_search_results,
            web_search_results: [],  # Assistants API doesn't have web_search
            code_interpreter_results: [],  # Could be extracted if needed
            api_metadata: {
              thread_id: raw_response[:thread_id],
              run_id: raw_response[:run_id],
              annotations: raw_response[:annotations] || [],
              run_steps: run_steps_data
            },
            raw_response: raw_response
          )
        end

        private

        def run_steps_data
          @run_steps_data ||= raw_response[:run_steps] || {}
        end

        def usage_data
          @usage_data ||= raw_response[:usage] || {}
        end

        # Extract usage information
        def extract_usage
          {
            prompt_tokens: usage_data["prompt_tokens"] || 0,
            completion_tokens: usage_data["completion_tokens"] || 0,
            total_tokens: usage_data["total_tokens"] || 0
          }
        end

        # Extract file_search results from run steps
        def extract_file_search_results
          results = []

          run_steps_data["data"]&.each do |step|
            next unless step["type"] == "tool_calls"

            step.dig("step_details", "tool_calls")&.each do |tool_call|
              next unless tool_call["type"] == "file_search"

              file_search = tool_call["file_search"]

              file_search["results"]&.each do |result|
                results << {
                  file_id: result["file_id"],
                  file_name: result["file_name"],
                  score: result["score"],
                  content: result["content"]
                }
              end
            end
          end

          results
        end

        # Extract function tool calls from run steps
        def extract_tool_calls
          results = []

          run_steps_data["data"]&.each do |step|
            next unless step["type"] == "tool_calls"

            step.dig("step_details", "tool_calls")&.each do |tool_call|
              next unless tool_call["type"] == "function"

              function = tool_call["function"]
              results << {
                id: tool_call["id"],
                type: "function",
                function_name: function["name"],
                arguments: parse_json_arguments(function["arguments"])
              }
            end
          end

          results
        end
      end
    end
  end
end
