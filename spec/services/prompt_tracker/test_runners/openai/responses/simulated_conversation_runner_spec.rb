# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    module Openai
      module Responses
        RSpec.describe SimulatedConversationRunner, type: :service do
          let(:model_config) do
            {
              provider: "openai",
              api: "responses",
              model: "gpt-4o",
              temperature: 0.7
            }
          end

          let(:runner) do
            described_class.new(
              model_config: model_config,
              use_real_llm: false
            )
          end

          describe "#execute" do
            let(:params) do
              {
                system_prompt: "You are helpful.",
                max_turns: 1,
                first_user_message: "Hello"
              }
            end

            it "returns output_data with messages" do
              result = runner.execute(params)

              expect(result).to be_a(Hash)
              expect(result["messages"]).to be_an(Array)
              expect(result["messages"].length).to eq(2)
            end

            it "includes tool results in output_data" do
              result = runner.execute(params)

              expect(result).to have_key("web_search_results")
              expect(result).to have_key("code_interpreter_results")
              expect(result).to have_key("file_search_results")
            end

            context "when runner instance is reused for multiple execute calls" do
              it "correctly extracts tool results from each execution independently" do
                # First execution with mock responses that include web search results
                allow(runner).to receive(:mock_response_api_response).and_return(
                  PromptTracker::NormalizedResponse.new(
                    text: "First response",
                    usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
                    model: "gpt-4o",
                    tool_calls: [],
                    file_search_results: [],
                    web_search_results: [ { query: "first query", results: [ "result1" ] } ],
                    code_interpreter_results: [],
                    api_metadata: { response_id: "resp_1" },
                    raw_response: {}
                  )
                )

                first_result = runner.execute(params)

                expect(first_result["web_search_results"]).to eq([ { query: "first query", results: [ "result1" ] } ])
                expect(first_result["code_interpreter_results"]).to eq([])

                # Second execution with different mock responses
                allow(runner).to receive(:mock_response_api_response).and_return(
                  PromptTracker::NormalizedResponse.new(
                    text: "Second response",
                    usage: { prompt_tokens: 15, completion_tokens: 25, total_tokens: 40 },
                    model: "gpt-4o",
                    tool_calls: [],
                    file_search_results: [],
                    web_search_results: [],
                    code_interpreter_results: [ { code: "print('hello')", output: "hello" } ],
                    api_metadata: { response_id: "resp_2" },
                    raw_response: {}
                  )
                )

                second_result = runner.execute(params)

                # Second execution should NOT include results from first execution
                expect(second_result["web_search_results"]).to eq([])
                expect(second_result["code_interpreter_results"]).to eq([ { code: "print('hello')", output: "hello" } ])

                # Verify first result hasn't been mutated
                expect(first_result["web_search_results"]).to eq([ { query: "first query", results: [ "result1" ] } ])
              end
            end
          end
        end
      end
    end
  end
end
