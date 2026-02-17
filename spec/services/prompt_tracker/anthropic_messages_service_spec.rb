# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe AnthropicMessagesService do
    let(:model) { "claude-3-5-sonnet-20241022" }
    let(:messages) { [ { role: "user", content: "Hello!" } ] }
    let(:system_prompt) { "You are a helpful assistant." }

    # Mock RubyLLM chat and response
    let(:mock_chat) { double("RubyLLM::Chat") }
    let(:mock_response) do
      double(
        "RubyLLM::Message",
        content: "Hello! How can I help you today?",
        input_tokens: 15,
        output_tokens: 10,
        model_id: model,
        id: "msg_01XFDUDYJgAACzvnptvVoYEL",
        stop_reason: "end_turn",
        tool_calls: nil
      )
    end

    before do
      allow(RubyLLM).to receive(:chat).with(model: model).and_return(mock_chat)
      allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
      allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
      allow(mock_chat).to receive(:with_params).and_yield({}).and_return(mock_chat)
      allow(mock_chat).to receive(:ask).and_return(mock_response)
    end

    describe ".call" do
      it "makes a Messages API call and returns normalized response" do
        response = described_class.call(
          model: model,
          messages: messages,
          system: system_prompt
        )

        expect(response.text).to eq("Hello! How can I help you today?")
        expect(response.model).to eq(model)
        expect(response.usage[:prompt_tokens]).to eq(15)
        expect(response.usage[:completion_tokens]).to eq(10)
        expect(response.usage[:total_tokens]).to eq(25)
      end

      it "configures the chat with system prompt" do
        expect(mock_chat).to receive(:with_instructions).with(system_prompt)

        described_class.call(
          model: model,
          messages: messages,
          system: system_prompt
        )
      end

      it "configures the chat with temperature when provided" do
        expect(mock_chat).to receive(:with_temperature).with(0.5)

        described_class.call(
          model: model,
          messages: messages,
          temperature: 0.5
        )
      end

      it "configures max_tokens via with_params" do
        params_hash = {}
        allow(mock_chat).to receive(:with_params).and_yield(params_hash).and_return(mock_chat)

        described_class.call(
          model: model,
          messages: messages,
          max_tokens: 8192
        )

        expect(params_hash[:max_tokens]).to eq(8192)
      end

      it "uses default max_tokens when not specified" do
        params_hash = {}
        allow(mock_chat).to receive(:with_params).and_yield(params_hash).and_return(mock_chat)

        described_class.call(
          model: model,
          messages: messages
        )

        expect(params_hash[:max_tokens]).to eq(described_class::DEFAULT_MAX_TOKENS)
      end

      it "extracts last user message as prompt" do
        multi_messages = [
          { role: "user", content: "First message" },
          { role: "assistant", content: "Response" },
          { role: "user", content: "Second message" }
        ]

        expect(mock_chat).to receive(:ask).with("Second message")

        described_class.call(
          model: model,
          messages: multi_messages
        )
      end

      it "returns NormalizedLlmResponse" do
        response = described_class.call(model: model, messages: messages)

        expect(response).to be_a(NormalizedLlmResponse)
      end

      it "includes api_metadata" do
        allow(mock_response).to receive(:respond_to?).with(:id).and_return(true)
        allow(mock_response).to receive(:respond_to?).with(:stop_reason).and_return(true)
        allow(mock_response).to receive(:respond_to?).with(:tool_calls).and_return(false)

        response = described_class.call(model: model, messages: messages)

        expect(response.api_metadata[:message_id]).to eq("msg_01XFDUDYJgAACzvnptvVoYEL")
        expect(response.api_metadata[:stop_reason]).to eq("end_turn")
      end
    end

    describe "tool_calls extraction" do
      context "when response has tool_calls" do
        let(:mock_response_with_tools) do
          double(
            "RubyLLM::Message",
            content: "I'll check the weather.",
            input_tokens: 20,
            output_tokens: 15,
            model_id: model,
            id: "msg_123",
            stop_reason: "tool_use",
            tool_calls: [
              { "id" => "toolu_01", "name" => "get_weather", "input" => { "location" => "Berlin" } }
            ]
          )
        end

        before do
          allow(mock_chat).to receive(:ask).and_return(mock_response_with_tools)
          allow(mock_response_with_tools).to receive(:respond_to?).with(:tool_calls).and_return(true)
          allow(mock_response_with_tools).to receive(:respond_to?).with(:id).and_return(true)
          allow(mock_response_with_tools).to receive(:respond_to?).with(:stop_reason).and_return(true)
        end

        it "extracts tool calls from response" do
          response = described_class.call(model: model, messages: messages)

          expect(response.tool_calls.length).to eq(1)
          expect(response.tool_calls[0][:id]).to eq("toolu_01")
          expect(response.tool_calls[0][:function_name]).to eq("get_weather")
          expect(response.tool_calls[0][:arguments]).to eq({ "location" => "Berlin" })
        end
      end
    end

    describe "tool support" do
      let(:tool_config) do
        {
          "functions" => [
            {
              "name" => "get_weather",
              "description" => "Get the current weather",
              "parameters" => {
                "type" => "object",
                "properties" => {
                  "location" => { "type" => "string" }
                },
                "required" => [ "location" ]
              }
            }
          ]
        }
      end

      it "passes tools to the API via with_params" do
        params_hash = {}
        allow(mock_chat).to receive(:with_params).and_yield(params_hash).and_return(mock_chat)

        described_class.call(
          model: model,
          messages: messages,
          tools: [ :functions ],
          tool_config: tool_config
        )

        expect(params_hash[:tools]).to be_an(Array)
        expect(params_hash[:tools].length).to eq(1)
        expect(params_hash[:tools][0][:name]).to eq("get_weather")
        expect(params_hash[:tools][0][:description]).to eq("Get the current weather")
        expect(params_hash[:tools][0][:input_schema]).to eq({
          "type" => "object",
          "properties" => {
            "location" => { "type" => "string" }
          },
          "required" => [ "location" ]
        })
      end

      it "does not pass tools when tools array is empty" do
        params_hash = {}
        allow(mock_chat).to receive(:with_params).and_yield(params_hash).and_return(mock_chat)

        described_class.call(
          model: model,
          messages: messages,
          tools: [],
          tool_config: {}
        )

        expect(params_hash[:tools]).to be_nil
      end

      it "includes max_tokens along with tools" do
        params_hash = {}
        allow(mock_chat).to receive(:with_params).and_yield(params_hash).and_return(mock_chat)

        described_class.call(
          model: model,
          messages: messages,
          tools: [ :functions ],
          tool_config: tool_config,
          max_tokens: 8192
        )

        expect(params_hash[:max_tokens]).to eq(8192)
        expect(params_hash[:tools]).to be_an(Array)
      end
    end
  end
end
