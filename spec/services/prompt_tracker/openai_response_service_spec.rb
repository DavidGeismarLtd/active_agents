# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe OpenaiResponseService do
    let(:model) { "gpt-4o" }
    let(:user_prompt) { "What's the weather in Berlin?" }
    let(:system_prompt) { "You are a helpful assistant." }
    let(:mock_client) { double("OpenAI::Client") }
    let(:mock_responses) { double("responses") }

    before do
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:responses).and_return(mock_responses)
      allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return("test-api-key")
    end

    describe ".call" do
      let(:api_response) do
        {
          "id" => "resp_abc123",
          "model" => "gpt-4o-2024-08-06",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "I don't have access to real-time weather data." }
              ]
            }
          ],
          "usage" => {
            "input_tokens" => 25,
            "output_tokens" => 15
          }
        }
      end

      it "makes a Response API call and returns normalized response" do
        allow(mock_responses).to receive(:create).and_return(api_response)

        response = described_class.call(
          model: model,
          input: user_prompt,
          instructions: system_prompt
        )

        expect(response[:text]).to eq("I don't have access to real-time weather data.")
        expect(response.response_id).to eq("resp_abc123")
        expect(response[:model]).to eq("gpt-4o-2024-08-06")
        expect(response[:usage][:prompt_tokens]).to eq(25)
        expect(response[:usage][:completion_tokens]).to eq(15)
        expect(response[:usage][:total_tokens]).to eq(40)
        expect(response[:web_search_results]).to eq([])
        expect(response[:code_interpreter_results]).to eq([])
        expect(response[:file_search_results]).to eq([])
        expect(response[:raw_response]).to eq(api_response)
      end

      it "passes correct parameters to the API" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            model: model,
            input: user_prompt,
            instructions: system_prompt,
            temperature: 0.7
          )
        ).and_return(api_response)

        described_class.call(
          model: model,
          input: user_prompt,
          instructions: system_prompt
        )
      end

      it "includes max_output_tokens when max_tokens is provided" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(max_output_tokens: 100)
        ).and_return(api_response)

        described_class.call(
          model: model,
          input: user_prompt,
          max_tokens: 100
        )
      end

      it "raises error when API key is missing" do
        allow(PromptTracker.configuration).to receive(:api_key_for).with(:openai).and_return(nil)

        expect {
          described_class.call(model: model, input: user_prompt)
        }.to raise_error(OpenaiResponseService::ResponseApiError, /OpenAI API key not configured/)
      end

      it "redacts sensitive data in error messages when API call fails" do
        # Create a long prompt and system instructions to test truncation
        long_input = "A" * 200
        long_instructions = "B" * 150
        function_tool = {
          type: "function",
          name: "get_weather",
          function: {
            name: "get_weather",
            description: "Get weather for a location",
            parameters: { type: "object", properties: { location: { type: "string" } } }
          }
        }

        # Mock a BadRequestError from Faraday
        error_response = {
          body: { error: { message: "Invalid request" } }.to_json
        }
        bad_request_error = Faraday::BadRequestError.new("Bad Request", error_response)

        allow(mock_responses).to receive(:create).and_raise(bad_request_error)

        expect {
          described_class.call(
            model: model,
            input: long_input,
            instructions: long_instructions,
            tools: [ :web_search, function_tool ]
          )
        }.to raise_error(OpenaiResponseService::ResponseApiError) do |error|
          # Error message should contain the API error
          expect(error.message).to include("Invalid request")

          # Input should be truncated
          expect(error.message).to include("truncated, total length: 200")
          expect(error.message).not_to include("A" * 200)

          # Instructions should be truncated
          expect(error.message).to include("truncated, total length: 150")
          expect(error.message).not_to include("B" * 150)

          # Function definitions should be redacted
          expect(error.message).to include("[REDACTED]")
          expect(error.message).not_to include("Get weather for a location")

          # Simple tools like web_search should still be visible
          expect(error.message).to include("web_search")
        end
      end
    end

    describe ".call with tools" do
      let(:api_response_with_tool) do
        {
          "id" => "resp_xyz789",
          "model" => "gpt-4o-2024-08-06",
          "output" => [
            {
              "type" => "web_search_call",
              "id" => "ws_123",
              "status" => "completed",
              "action" => {
                "query" => "weather in Berlin",
                "sources" => [
                  { "title" => "Berlin Weather", "url" => "https://example.com", "snippet" => "Sunny" }
                ]
              }
            },
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Based on my search, the weather in Berlin is sunny.",
                  "annotations" => [
                    {
                      "type" => "url_citation",
                      "title" => "Berlin Weather",
                      "url" => "https://example.com",
                      "start_index" => 0,
                      "end_index" => 50
                    }
                  ]
                }
              ]
            }
          ],
          "usage" => { "input_tokens" => 50, "output_tokens" => 30 }
        }
      end

      it "formats web_search tool correctly and includes sources parameter" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            tools: [ { type: "web_search_preview" } ],
            include: [ "web_search_call.action.sources" ]
          )
        ).and_return(api_response_with_tool)

        described_class.call(
          model: model,
          input: user_prompt,
          tools: [ :web_search ]
        )
      end

      it "extracts tool calls from response" do
        allow(mock_responses).to receive(:create).and_return(api_response_with_tool)

        response = described_class.call(
          model: model,
          input: user_prompt,
          tools: [ :web_search ]
        )

        # tool_calls only contains function_call items, not web_search_call
        # web_search results are in web_search_results instead
        expect(response[:tool_calls]).to be_an(Array)
        expect(response[:tool_calls]).to be_empty  # No function calls in this response
      end

      it "extracts web_search_results with both sources and citations" do
        allow(mock_responses).to receive(:create).and_return(api_response_with_tool)

        response = described_class.call(
          model: model,
          input: user_prompt,
          tools: [ :web_search ]
        )

        expect(response[:web_search_results]).to be_an(Array)
        expect(response[:web_search_results].length).to eq(1)
        expect(response[:web_search_results].first[:id]).to eq("ws_123")
        expect(response[:web_search_results].first[:status]).to eq("completed")
        expect(response[:web_search_results].first[:query]).to eq("weather in Berlin")
        expect(response[:web_search_results].first[:sources].length).to eq(1)
        expect(response[:web_search_results].first[:citations].length).to eq(1)
      end

      it "merges caller-provided include options with web_search include" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            tools: [ { type: "web_search_preview" } ],
            include: array_including(
              "web_search_call.action.sources",
              "some_other_field"
            )
          )
        ).and_return(api_response_with_tool)

        described_class.call(
          model: model,
          input: user_prompt,
          tools: [ :web_search ],
          include: [ "some_other_field" ]
        )
      end

      it "does not duplicate include values when merging" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            include: [ "web_search_call.action.sources" ]
          )
        ).and_return(api_response_with_tool)

        described_class.call(
          model: model,
          input: user_prompt,
          tools: [ :web_search ],
          include: [ "web_search_call.action.sources" ]  # Same as auto-added
        )
      end
    end

    describe ".call_with_context" do
      let(:previous_response_id) { "resp_previous123" }
      let(:api_response) do
        {
          "id" => "resp_followup456",
          "model" => "gpt-4o-2024-08-06",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "Your name is Alice." }
              ]
            }
          ],
          "usage" => { "input_tokens" => 30, "output_tokens" => 10 }
        }
      end

      it "includes previous_response_id in the API call" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            previous_response_id: previous_response_id
          )
        ).and_return(api_response)

        described_class.call_with_context(
          model: model,
          input: "What's my name?",
          previous_response_id: previous_response_id
        )
      end

      it "returns normalized response for multi-turn conversation" do
        allow(mock_responses).to receive(:create).and_return(api_response)

        response = described_class.call_with_context(
          model: model,
          input: "What's my name?",
          previous_response_id: previous_response_id
        )

        expect(response[:text]).to eq("Your name is Alice.")
        expect(response.response_id).to eq("resp_followup456")
      end

      it "passes tools but not temperature when previous_response_id is present" do
        # Tools MUST be passed on every request (not inherited)
        # Temperature and other sampling parameters are inherited (not passed again)
        function_definitions = [
          {
            "name" => "get_weather",
            "description" => "Get weather for a location",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "location" => { "type" => "string" }
              },
              "required" => [ "location" ]
            }
          }
        ]

        expect(mock_responses).to receive(:create) do |params|
          expect(params[:parameters]).to include(previous_response_id: previous_response_id)
          expect(params[:parameters]).to have_key(:tools)
          # strict is only included if explicitly set in the function definition
          expect(params[:parameters][:tools]).to eq([
            { type: "web_search_preview" },
            {
              type: "function",
              name: "get_weather",
              description: "Get weather for a location",
              parameters: {
                "type" => "object",
                "properties" => {
                  "location" => { "type" => "string" }
                },
                "required" => [ "location" ]
              }
            }
          ])
          expect(params[:parameters]).not_to have_key(:temperature)
          api_response
        end

        described_class.call_with_context(
          model: model,
          input: "What's my name?",
          previous_response_id: previous_response_id,
          tools: [ :web_search, :functions ],
          tool_config: { "functions" => function_definitions },
          temperature: 0.7  # This should be ignored (inherited)
        )
      end
    end

    describe "tool formatting" do
      let(:api_response) do
        {
          "id" => "resp_123",
          "model" => "gpt-4o",
          "output" => [],
          "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
        }
      end

      it "formats file_search tool correctly" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            tools: [ { type: "file_search" } ]
          )
        ).and_return(api_response)

        described_class.call(model: model, input: user_prompt, tools: [ :file_search ])
      end

      it "formats code_interpreter tool correctly" do
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            tools: [ { type: "code_interpreter" } ]
          )
        ).and_return(api_response)

        described_class.call(model: model, input: user_prompt, tools: [ :code_interpreter ])
      end

      it "passes through custom tool hashes" do
        custom_tool = { type: "function", name: "get_weather" }
        expect(mock_responses).to receive(:create).with(
          parameters: hash_including(
            tools: [ custom_tool ]
          )
        ).and_return(api_response)

        described_class.call(model: model, input: user_prompt, tools: [ custom_tool ])
      end
    end
  end
end
