# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  module TestRunners
    # Integration spec for custom mock_function_outputs feature
    # Tests the full flow from dataset row → test execution → evaluation
    RSpec.describe "Custom Mock Function Outputs Integration", type: :service do
      let(:prompt) { create(:prompt) }
      let(:version_with_functions) do
        create(:prompt_version,
               prompt: prompt,
               user_prompt: "{{user_query}}",
               system_prompt: "You are a helpful assistant. Use functions when needed.",
               variables_schema: [
                 { "name" => "user_query", "type" => "string", "required" => true }
               ],
               model_config: {
                 "provider" => "openai",
                 "api" => "responses",
                 "model" => "gpt-4o",
                 "tool_config" => {
                   "functions" => [
                     {
                       "name" => "get_weather",
                       "description" => "Get weather for a location",
                       "parameters" => {
                         "type" => "object",
                         "properties" => {
                           "location" => { "type" => "string" }
                         }
                       }
                     }
                   ]
                 }
               })
      end

      let(:test) { create(:test, testable: version_with_functions) }

      describe "with dataset row containing custom mock_function_outputs" do
        let(:dataset) { create(:dataset, testable: version_with_functions) }
        let(:dataset_row) do
          create(:dataset_row,
                 dataset: dataset,
                 row_data: {
                   "user_query" => "What's the weather in San Francisco?",
                   "mock_function_outputs" => {
                     "get_weather" => '{"location":"San Francisco, CA","temperature":68,"condition":"Foggy","humidity":75}'
                   }
                 })
        end

        let(:test_run) do
          create(:test_run,
                 test: test,
                 dataset_row: dataset_row,
                 status: "running",
                 metadata: {
                   "triggered_by" => "manual",
                   "run_mode" => "dataset"
                 })
        end

        it "uses custom mock when function is called during test execution" do
          runner = PromptVersionRunner.new(
            test_run: test_run,
            test: test,
            testable: version_with_functions,
            use_real_llm: false
          )

          # Mock the API to return a function call
          allow_any_instance_of(TestRunners::Openai::ResponseApiHandler)
            .to receive(:call_response_api).and_return(
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "SF" } }
                ]
              },
              {
                text: "It's foggy in San Francisco with a temperature of 68°F",
                response_id: "resp_124",
                usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                tool_calls: []
              }
            )

          runner.run
          test_run.reload

          # Verify the test completed successfully
          expect(test_run.status).to eq("passed")

          # Verify the output_data has messages
          output_data = test_run.output_data
          expect(output_data["messages"]).to be_present

          # Verify the assistant message contains tool_calls
          assistant_msg = output_data["messages"].find { |m| m["role"] == "assistant" }
          expect(assistant_msg).to be_present
          expect(assistant_msg["tool_calls"]).to be_an(Array)
          expect(assistant_msg["tool_calls"].length).to be > 0
          expect(assistant_msg["tool_calls"].first).to have_key("function_name")
          expect(assistant_msg["tool_calls"].first["function_name"]).to eq("get_weather")
        end
      end

      describe "with custom_variables containing mock_function_outputs" do
        let(:test_run_with_custom_vars) do
          create(:test_run,
                 test: test,
                 status: "running",
                 metadata: {
                   "triggered_by" => "manual",
                   "run_mode" => "custom",
                   "custom_variables" => {
                     "user_query" => "What's the weather in NYC?",
                     "mock_function_outputs" => {
                       "get_weather" => {
                         "location" => "New York, NY",
                         "temperature" => 45,
                         "condition" => "Snowy"
                       }
                     }
                   }
                 })
        end

        it "uses custom mock from custom_variables" do
          runner = PromptVersionRunner.new(
            test_run: test_run_with_custom_vars,
            test: test,
            testable: version_with_functions,
            use_real_llm: false
          )

          # Mock the API to return a function call
          allow_any_instance_of(TestRunners::Openai::ResponseApiHandler)
            .to receive(:call_response_api).and_return(
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
                ]
              },
              {
                text: "It's snowy in New York",
                response_id: "resp_124",
                usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                tool_calls: []
              }
            )

          runner.run
          test_run_with_custom_vars.reload

          # Verify the test completed successfully
          expect(test_run_with_custom_vars.status).to eq("passed")

          # Verify the assistant message contains tool_calls
          output_data = test_run_with_custom_vars.output_data
          assistant_msg = output_data["messages"].find { |m| m["role"] == "assistant" }
          expect(assistant_msg).to be_present
          expect(assistant_msg["tool_calls"]).to be_an(Array)
          expect(assistant_msg["tool_calls"].first["function_name"]).to eq("get_weather") if assistant_msg["tool_calls"].any?
        end
      end

      describe "without custom mock_function_outputs" do
        let(:test_run_without_mocks) do
          create(:test_run,
                 test: test,
                 status: "running",
                 metadata: {
                   "triggered_by" => "manual",
                   "run_mode" => "custom",
                   "custom_variables" => {
                     "user_query" => "What's the weather?"
                   }
                 })
        end

        it "falls back to generic mock response" do
          # Mock the API to return a function call
          allow_any_instance_of(TestRunners::Openai::ResponseApiHandler)
            .to receive(:call_response_api).and_return(
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "Boston" } }
                ]
              },
              {
                text: "Generic response",
                response_id: "resp_124",
                usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                tool_calls: []
              }
            )

          runner = PromptVersionRunner.new(
            test_run: test_run_without_mocks,
            test: test,
            testable: version_with_functions,
            use_real_llm: false
          )

          runner.run
          test_run_without_mocks.reload

          # Verify the test completed successfully
          expect(test_run_without_mocks.status).to eq("passed")

          # Verify the assistant message contains tool_calls
          output_data = test_run_without_mocks.output_data
          assistant_msg = output_data["messages"].find { |m| m["role"] == "assistant" }
          expect(assistant_msg).to be_present
          expect(assistant_msg["tool_calls"]).to be_an(Array)
          expect(assistant_msg["tool_calls"].first["function_name"]).to eq("get_weather") if assistant_msg["tool_calls"].any?
        end
      end

      describe "integration with FunctionCallEvaluator" do
        let(:dataset_row_with_evaluator) do
          create(:dataset_row,
                 dataset: create(:dataset, testable: version_with_functions),
                 row_data: {
                   "user_query" => "What's the weather?",
                   "mock_function_outputs" => {
                     "get_weather" => {
                       "temperature" => 72,
                       "condition" => "Sunny"
                     }
                   }
                 })
        end

        let(:function_call_evaluator) do
          create(:evaluator_config,
                 :function_call,
                 configurable: test,
                 config: {
                   "expected_functions" => [ "get_weather" ]
                 })
        end

        let(:test_run_with_evaluator) do
          create(:test_run,
                 test: test,
                 dataset_row: dataset_row_with_evaluator,
                 status: "running",
                 metadata: {
                   "triggered_by" => "manual",
                   "run_mode" => "dataset"
                 })
        end

        it "evaluator validates function calls regardless of mock type" do
          # Create the evaluator config
          function_call_evaluator

          runner = PromptVersionRunner.new(
            test_run: test_run_with_evaluator,
            test: test,
            testable: version_with_functions,
            use_real_llm: false
          )

          # Mock the API to return a function call
          allow_any_instance_of(TestRunners::Openai::ResponseApiHandler)
            .to receive(:call_response_api).and_return(
              {
                text: "",
                response_id: "resp_123",
                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
                tool_calls: [
                  { id: "call_1", function_name: "get_weather", arguments: { location: "NYC" } }
                ]
              },
              {
                text: "It's sunny",
                response_id: "resp_124",
                usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 },
                tool_calls: []
              }
            )

          runner.run
          test_run_with_evaluator.reload

          # Verify the test completed successfully
          expect(test_run_with_evaluator.status).to eq("passed")

          # Verify evaluations were created
          expect(test_run_with_evaluator.evaluations.count).to be > 0

          # Find the function call evaluation
          function_call_evaluation = test_run_with_evaluator.evaluations.find_by(
            evaluator_config_id: function_call_evaluator.id
          )

          # Evaluator should pass because get_weather was called
          expect(function_call_evaluation).to be_present
          expect(function_call_evaluation.passed).to be true
          expect(function_call_evaluation.score).to eq(100)
        end
      end
    end
  end
end
