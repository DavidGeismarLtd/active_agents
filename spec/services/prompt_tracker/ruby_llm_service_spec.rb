# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptTracker::RubyLlmService do
  let(:model) { "gpt-4o-mini" }
  let(:prompt) { "Hello!" }
  let(:system) { "You are a helpful assistant." }

  describe ".call" do
    context "basic call without tools" do
      let(:mock_response) do
        double(
          "RubyLLM::Message",
          content: "Hello! How can I help you today?",
          model_id: model,
          input_tokens: 10,
          output_tokens: 15,
          tool_calls: nil
        )
      end

      let(:mock_chat) do
        chat = double("RubyLLM::Chat")
        allow(chat).to receive(:with_instructions).and_return(chat)
        allow(chat).to receive(:with_temperature).and_return(chat)
        allow(chat).to receive(:with_params).and_return(chat)
        allow(chat).to receive(:with_tool).and_return(chat)
        allow(chat).to receive(:on_tool_call).and_return(chat)
        allow(chat).to receive(:on_tool_result).and_return(chat)
        allow(chat).to receive(:ask).with(prompt).and_return(mock_response)
        chat
      end

      before do
        allow(RubyLLM).to receive(:chat).with(model: model).and_return(mock_chat)
      end

      it "makes a successful call" do
        response = described_class.call(model: model, prompt: prompt, system: system)

        expect(response).to be_a(PromptTracker::NormalizedLlmResponse)
        expect(response.text).to eq("Hello! How can I help you today?")
      end

      it "passes system prompt to chat" do
        expect(mock_chat).to receive(:with_instructions).with(system).and_return(mock_chat)

        described_class.call(model: model, prompt: prompt, system: system)
      end

      it "passes temperature when provided" do
        expect(mock_chat).to receive(:with_temperature).with(0.5).and_return(mock_chat)

        described_class.call(model: model, prompt: prompt, temperature: 0.5)
      end

      it "skips temperature when not provided" do
        expect(mock_chat).not_to receive(:with_temperature)

        described_class.call(model: model, prompt: prompt)
      end

      it "passes max_tokens via with_params when provided" do
        expect(mock_chat).to receive(:with_params).and_yield({}).and_return(mock_chat)

        described_class.call(model: model, prompt: prompt, max_tokens: 1000)
      end

      it "logs the request" do
        expect(Rails.logger).to receive(:info).with(/\[RubyLlmService\] Request:.*model=#{model}/)
        expect(Rails.logger).to receive(:info).with(/\[RubyLlmService\] Response:/)

        described_class.call(model: model, prompt: prompt)
      end
    end

    context "with tools" do
      let(:tool_config) do
        {
          "functions" => [
            {
              "name" => "get_weather",
              "description" => "Get weather for a city",
              "parameters" => {
                "type" => "object",
                "properties" => {
                  "city" => { "type" => "string" }
                },
                "required" => [ "city" ]
              }
            }
          ]
        }
      end

      let(:mock_response) do
        double(
          "RubyLLM::Message",
          content: "The weather in Berlin is sunny, 72°F.",
          model_id: model,
          input_tokens: 50,
          output_tokens: 25,
          tool_calls: []
        )
      end

      let(:mock_chat) do
        chat = double("RubyLLM::Chat")
        allow(chat).to receive(:with_instructions).and_return(chat)
        allow(chat).to receive(:with_temperature).and_return(chat)
        allow(chat).to receive(:with_params).and_return(chat)
        allow(chat).to receive(:with_tool).and_return(chat)
        allow(chat).to receive(:on_tool_call).and_return(chat)
        allow(chat).to receive(:on_tool_result).and_return(chat)
        allow(chat).to receive(:ask).and_return(mock_response)
        chat
      end

      before do
        allow(RubyLLM).to receive(:chat).with(model: model).and_return(mock_chat)
      end

      it "registers tools via with_tool" do
        expect(mock_chat).to receive(:with_tool).and_return(mock_chat)

        described_class.call(
          model: model,
          prompt: "What's the weather in Berlin?",
          tools: [ :functions ],
          tool_config: tool_config
        )
      end

      it "uses DynamicToolBuilder to create tool classes" do
        expect(PromptTracker::RubyLlm::DynamicToolBuilder).to receive(:build).with(
          tool_config: tool_config,
          mock_function_outputs: nil
        ).and_call_original

        described_class.call(
          model: model,
          prompt: "What's the weather?",
          tools: [ :functions ],
          tool_config: tool_config
        )
      end

      it "passes mock_function_outputs to DynamicToolBuilder" do
        mock_outputs = { "get_weather" => { "temp" => 72 } }

        expect(PromptTracker::RubyLlm::DynamicToolBuilder).to receive(:build).with(
          tool_config: tool_config,
          mock_function_outputs: mock_outputs
        ).and_call_original

        described_class.call(
          model: model,
          prompt: "What's the weather?",
          tools: [ :functions ],
          tool_config: tool_config,
          mock_function_outputs: mock_outputs
        )
      end
    end
  end

  describe ".build_chat" do
    let(:mock_chat) do
      chat = double("RubyLLM::Chat")
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_temperature).and_return(chat)
      allow(chat).to receive(:with_params).and_return(chat)
      allow(chat).to receive(:with_tool).and_return(chat)
      allow(chat).to receive(:on_tool_call).and_return(chat)
      allow(chat).to receive(:on_tool_result).and_return(chat)
      chat
    end

    before do
      allow(RubyLLM).to receive(:chat).with(model: model).and_return(mock_chat)
    end

    it "returns a configured RubyLLM::Chat instance" do
      chat = described_class.build_chat(model: model, system: system)

      expect(chat).to eq(mock_chat)
    end

    it "passes system prompt to chat" do
      expect(mock_chat).to receive(:with_instructions).with(system).and_return(mock_chat)

      described_class.build_chat(model: model, system: system)
    end

    it "passes temperature when provided" do
      expect(mock_chat).to receive(:with_temperature).with(0.5).and_return(mock_chat)

      described_class.build_chat(model: model, temperature: 0.5)
    end

    it "skips temperature when not provided" do
      expect(mock_chat).not_to receive(:with_temperature)

      described_class.build_chat(model: model)
    end

    it "registers tools when tool_config is provided" do
      tool_config = {
        "functions" => [
          { "name" => "get_weather", "description" => "Get weather" }
        ]
      }

      expect(mock_chat).to receive(:with_tool).and_return(mock_chat)

      described_class.build_chat(
        model: model,
        tools: [ :functions ],
        tool_config: tool_config
      )
    end

    it "does not register tools when tools is empty" do
      expect(mock_chat).not_to receive(:with_tool)

      described_class.build_chat(model: model, tools: [])
    end
  end
end
