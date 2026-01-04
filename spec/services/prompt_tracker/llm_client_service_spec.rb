# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/schema"

module PromptTracker
  RSpec.describe LlmClientService do
    describe ".call" do
      let(:prompt) { "What is the capital of France?" }
      let(:model) { "gpt-4" }
      let(:temperature) { 0.7 }
      let(:provider) { "openai" }

      let(:chat_double) { double("RubyLLM::Chat") }
      let(:chat_with_temp_double) { double("RubyLLM::Chat with temperature") }
      let(:response_double) do
        double(
          "RubyLLM::Message",
          content: "The capital of France is Paris.",
          model_id: "gpt-4-0613",
          input_tokens: 10,
          output_tokens: 8,
          raw: {
            "usage" => {
              "prompt_tokens" => 10,
              "completion_tokens" => 8,
              "total_tokens" => 18
            }
          }
        )
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(chat_double)
        allow(chat_double).to receive(:with_temperature).and_return(chat_with_temp_double)
        allow(chat_with_temp_double).to receive(:ask).and_return(response_double)
        allow(chat_double).to receive(:ask).and_return(response_double)
      end

      context "when provider is openai_assistants" do
        let(:provider) { "openai_assistants" }
        let(:assistant_id) { "asst_abc123" }
        let(:assistant_response) do
          {
            text: "The weather is sunny.",
            usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
            model: assistant_id,
            raw: { thread_id: "thread_123", run_id: "run_456" }
          }
        end

        it "routes to OpenaiAssistantService" do
          allow(OpenaiAssistantService).to receive(:call).and_return(assistant_response)

          result = described_class.call(
            provider: provider,
            model: assistant_id,
            prompt: prompt
          )

          expect(OpenaiAssistantService).to have_received(:call).with(
            assistant_id: assistant_id,
            prompt: prompt,
            timeout: 60
          )
          expect(result).to eq(assistant_response)
        end
      end

      context "when model starts with asst_" do
        let(:assistant_id) { "asst_xyz789" }
        let(:assistant_response) do
          {
            text: "Assistant response",
            usage: { prompt_tokens: 5, completion_tokens: 10, total_tokens: 15 },
            model: assistant_id,
            raw: { thread_id: "thread_abc", run_id: "run_def" }
          }
        end

        it "routes to OpenaiAssistantService even with different provider" do
          allow(OpenaiAssistantService).to receive(:call).and_return(assistant_response)

          result = described_class.call(
            provider: "openai",  # Different provider
            model: assistant_id,  # But model starts with asst_
            prompt: prompt
          )

          expect(OpenaiAssistantService).to have_received(:call).with(
            assistant_id: assistant_id,
            prompt: prompt,
            timeout: 60
          )
          expect(result).to eq(assistant_response)
        end
      end

      it "calls RubyLLM.chat with model only" do
        described_class.call(
          provider: provider,
          model: model,
          prompt: prompt,
          temperature: temperature
        )

        expect(RubyLLM).to have_received(:chat).with(model: model)
      end

      it "applies temperature using with_temperature" do
        described_class.call(
          provider: provider,
          model: model,
          prompt: prompt,
          temperature: temperature
        )

        expect(chat_double).to have_received(:with_temperature).with(temperature)
      end

      it "calls ask with the prompt" do
        described_class.call(
          provider: provider,
          model: model,
          prompt: prompt,
          temperature: temperature
        )

        expect(chat_with_temp_double).to have_received(:ask).with(prompt)
      end

      it "returns formatted response" do
        result = described_class.call(
          provider: provider,
          model: model,
          prompt: prompt,
          temperature: temperature
        )

        expect(result[:text]).to eq("The capital of France is Paris.")
        expect(result[:usage][:prompt_tokens]).to eq(10)
        expect(result[:usage][:completion_tokens]).to eq(8)
        expect(result[:usage][:total_tokens]).to eq(18)
        expect(result[:model]).to eq("gpt-4-0613")
        expect(result[:raw]).to eq(response_double)
      end

      it "applies max_tokens using with_params" do
        chat_with_params_double = double("RubyLLM::Chat with params")
        allow(chat_with_temp_double).to receive(:with_params).and_yield({}).and_return(chat_with_params_double)
        allow(chat_with_params_double).to receive(:ask).and_return(response_double)

        described_class.call(
          provider: provider,
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: 100
        )

        expect(chat_with_temp_double).to have_received(:with_params)
      end

      it "handles API errors by raising them" do
        allow(chat_with_temp_double).to receive(:ask).and_raise(StandardError.new("Rate limit exceeded"))

        expect do
          described_class.call(
            provider: provider,
            model: model,
            prompt: prompt,
            temperature: temperature
          )
        end.to raise_error(StandardError, /Rate limit exceeded/)
      end

      context "with Anthropic model" do
        let(:model) { "claude-3-opus-20240229" }

        it "works with Claude models (RubyLLM auto-detects provider)" do
          expect do
            described_class.call(
              provider: "anthropic",  # Provider is ignored
              model: model,
              prompt: prompt
            )
          end.not_to raise_error
        end
      end

      context "with response_schema parameter" do
        let(:response_schema) do
          {
            "type" => "object",
            "properties" => {
              "sentiment" => { "type" => "string", "description" => "The sentiment" },
              "confidence" => { "type" => "number", "description" => "Confidence score" }
            },
            "required" => %w[sentiment confidence]
          }
        end

        let(:schema_chat_double) { double("RubyLLM::Chat with schema") }
        let(:structured_response) do
          double(
            "RubyLLM::Message",
            content: { sentiment: "positive", confidence: 0.95 },
            model_id: "gpt-4-0613",
            input_tokens: 10,
            output_tokens: 8,
            raw: {}
          )
        end

        before do
          allow(chat_double).to receive(:with_schema).and_return(schema_chat_double)
          allow(chat_with_temp_double).to receive(:with_schema).and_return(schema_chat_double)
          allow(schema_chat_double).to receive(:ask).and_return(structured_response)
        end

        it "converts JSON Schema to RubyLLM::Schema and uses structured output" do
          allow(JsonSchemaAdapter).to receive(:to_ruby_llm_schema).and_call_original

          described_class.call(
            provider: provider,
            model: model,
            prompt: prompt,
            response_schema: response_schema
          )

          expect(JsonSchemaAdapter).to have_received(:to_ruby_llm_schema).with(response_schema)
        end

        it "uses with_schema on the chat" do
          described_class.call(
            provider: provider,
            model: model,
            prompt: prompt,
            response_schema: response_schema
          )

          expect(chat_with_temp_double).to have_received(:with_schema)
        end

        it "returns structured response as JSON" do
          result = described_class.call(
            provider: provider,
            model: model,
            prompt: prompt,
            response_schema: response_schema
          )

          expect(result[:text]).to eq('{"sentiment":"positive","confidence":0.95}')
          expect(result[:usage][:prompt_tokens]).to eq(10)
          expect(result[:usage][:completion_tokens]).to eq(8)
        end
      end
    end

    describe ".call_with_schema" do
      let(:prompt) { "Evaluate this response" }
      let(:provider) { "openai" }
      let(:model) { "gpt-4o-2024-08-06" }

      # Create a simple schema class for testing
      let(:schema_class) do
        Class.new(RubyLLM::Schema) do
          number :score, description: "Score from 0-10"
          string :feedback, description: "Feedback text"
        end
      end

      let(:chat_double) { double("RubyLLM::Chat") }
      let(:chat_with_temp_double) { double("RubyLLM::Chat with temperature") }
      let(:schema_chat_double) { double("RubyLLM::Chat with schema") }
      let(:response_double) do
        double(
          "RubyLLM::Message",
          content: { score: 8.5, feedback: "Good response" },
          model_id: "gpt-4o-2024-08-06",
          input_tokens: 50,
          output_tokens: 20,
          raw: {
            "usage" => {
              "prompt_tokens" => 50,
              "completion_tokens" => 20,
              "total_tokens" => 70
            }
          }
        )
      end

      before do
        allow(RubyLLM).to receive(:chat).and_return(chat_double)
        allow(chat_double).to receive(:with_temperature).and_return(chat_with_temp_double)
        allow(chat_with_temp_double).to receive(:with_schema).and_return(schema_chat_double)
        allow(chat_double).to receive(:with_schema).and_return(schema_chat_double)
        allow(schema_chat_double).to receive(:ask).and_return(response_double)
      end

      it "calls RubyLLM.chat with model only" do
        described_class.call_with_schema(
          provider: provider,
          model: model,
          prompt: prompt,
          schema: schema_class
        )

        expect(RubyLLM).to have_received(:chat).with(model: model)
      end

      it "applies default temperature 0.7 using with_temperature" do
        described_class.call_with_schema(
          provider: provider,
          model: model,
          prompt: prompt,
          schema: schema_class
        )

        expect(chat_double).to have_received(:with_temperature).with(0.7)
      end

      it "calls with_schema with the schema class" do
        described_class.call_with_schema(
          provider: provider,
          model: model,
          prompt: prompt,
          schema: schema_class
        )

        expect(chat_with_temp_double).to have_received(:with_schema).with(schema_class)
      end

      it "calls ask with the prompt" do
        described_class.call_with_schema(
          provider: provider,
          model: model,
          prompt: prompt,
          schema: schema_class
        )

        expect(schema_chat_double).to have_received(:ask).with(prompt)
      end

      it "returns formatted response with structured content as JSON" do
        result = described_class.call_with_schema(
          provider: provider,
          model: model,
          prompt: prompt,
          schema: schema_class
        )

        expect(result[:text]).to eq('{"score":8.5,"feedback":"Good response"}')
        expect(result[:usage][:prompt_tokens]).to eq(50)
        expect(result[:usage][:completion_tokens]).to eq(20)
        expect(result[:usage][:total_tokens]).to eq(70)
        expect(result[:model]).to eq("gpt-4o-2024-08-06")
      end

      it "works with any model (RubyLLM handles compatibility)" do
        expect do
          described_class.call_with_schema(
            provider: provider,
            model: "gpt-4o",
            prompt: prompt,
            schema: schema_class
          )
        end.not_to raise_error
      end

      it "works with Claude models too" do
        expect do
          described_class.call_with_schema(
            provider: "anthropic",
            model: "claude-3-opus-20240229",
            prompt: prompt,
            schema: schema_class
          )
        end.not_to raise_error
      end

      it "raises ArgumentError when schema is missing" do
        expect do
          described_class.call_with_schema(
            provider: provider,
            model: model,
            prompt: prompt,
            schema: nil
          )
        end.to raise_error(ArgumentError, /Schema is required/)
      end

      it "handles API errors by raising them" do
        allow(schema_chat_double).to receive(:ask).and_raise(StandardError.new("Invalid schema"))

        expect do
          described_class.call_with_schema(
            provider: provider,
            model: model,
            prompt: prompt,
            schema: schema_class
          )
        end.to raise_error(StandardError, /Invalid schema/)
      end
    end
  end
end
