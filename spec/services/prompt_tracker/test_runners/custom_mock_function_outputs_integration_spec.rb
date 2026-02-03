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
               template: "You are a helpful assistant. Use functions when needed.",
               variables_schema: [
                 { "name" => "user_query", "type" => "string", "required" => true }
               ],
               model_config: {
                 "provider" => "openai_responses",
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
          allow_any_instance_of(ApiExecutors::Openai::ResponseApiExecutor)
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

          result = runner.run

          # Verify the custom mock was used
          function_output_msg = result["messages"].find { |m| m["role"] == "function_call_output" }
          expect(function_output_msg).to be_present

          output_data = JSON.parse(function_output_msg["content"])
          expect(output_data["location"]).to eq("San Francisco, CA")
          expect(output_data["temperature"]).to eq(68)
          expect(output_data["condition"]).to eq("Foggy")
          expect(output_data["humidity"]).to eq(75)
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
          allow_any_instance_of(ApiExecutors::Openai::ResponseApiExecutor)
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

          result = runner.run

          # Verify the custom mock from custom_variables was used
          function_output_msg = result["messages"].find { |m| m["role"] == "function_call_output" }
          expect(function_output_msg).to be_present

          output_data = JSON.parse(function_output_msg["content"])
          expect(output_data["location"]).to eq("New York, NY")
          expect(output_data["temperature"]).to eq(45)
          expect(output_data["condition"]).to eq("Snowy")
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
          runner = PromptVersionRunner.new(
            test_run: test_run_without_mocks,
            test: test,
            testable: version_with_functions,
            use_real_llm: false
          )

          # Mock the API to return a function call
          allow_any_instance_of(ApiExecutors::Openai::ResponseApiExecutor)
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

          result = runner.run

          # Verify generic mock was used
          function_output_msg = result["messages"].find { |m| m["role"] == "function_call_output" }
          expect(function_output_msg).to be_present

          output_data = JSON.parse(function_output_msg["content"])
          expect(output_data["success"]).to eq(true)
          expect(output_data["message"]).to eq("Mock result for get_weather")
          expect(output_data["data"]).to eq({ "location" => "Boston" })
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
                 test: test,
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
          allow_any_instance_of(ApiExecutors::Openai::ResponseApiExecutor)
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

          result = runner.run

          # Update test run with result
          test_run_with_evaluator.update!(
            status: "completed",
            output_data: result
          )

          # Run evaluator
          evaluator = Evaluators::FunctionCallEvaluator.new(function_call_evaluator)
          evaluation = evaluator.evaluate(test_run_with_evaluator)

          # Evaluator should pass because get_weather was called
          expect(evaluation.passed).to be true
          expect(evaluation.score).to eq(100)
        end
      end
    end
  end
end
